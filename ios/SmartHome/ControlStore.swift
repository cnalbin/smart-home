import Foundation
import SwiftUI

struct ControlOutputs: Decodable {
    let light: Bool
    let fan: Bool
    let rgb: String
    let doorTarget: String?
    let windowTarget: String?
    let temperature: Int?
    let humidity: Int?
    let rain: Int?
    let gas: Int?
    let motion: Int?
    let rgbAdvanced: Bool?
    let rgbRemainingSeconds: Int?
}

struct ControlSnapshot: Decodable {
    let online: Bool
    let canControl: Bool
    let servoControlAvailable: Bool
    let seenAt: String?
    let state: ControlOutputs?

    var lastSeen: Date? {
        guard let seenAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: seenAt) ?? ISO8601DateFormatter().date(from: seenAt)
    }
}

enum ControlTarget: String {
    case light, fan, rgb, door, window
}

private struct ControlRequest: Encodable {
    let id: UUID
    let requestedAt: Int64
    let target: String
    let value: String
    let durationMinutes: Int?
}

private struct ControlReceipt: Decodable {
    enum Status: String, Decodable {
        case pending = "PENDING"
        case applied = "APPLIED"
        case rejected = "REJECTED"
        case unknown = "UNKNOWN"
    }

    let id: UUID
    let status: Status
}

@MainActor
final class ControlStore: ObservableObject {
    @Published private(set) var snapshot: ControlSnapshot?
    @Published private(set) var pendingTarget: ControlTarget?
    @Published private(set) var connectionMessage: String?
    @Published private(set) var commandMessage: String?
    @Published private(set) var messageTarget: ControlTarget?
    private var revision = 0
    private let controlPath = ["api", "control"]

    var online: Bool { snapshot?.online == true && connectionMessage == nil }
    var canOperate: Bool { online && snapshot?.canControl == true && pendingTarget == nil }
    var canOperateServos: Bool { canOperate && snapshot?.servoControlAvailable == true }
    var advancedRGB: Bool { snapshot?.state?.rgbAdvanced == true }

    func refresh(using session: SensorStore) async {
        guard pendingTarget == nil else { return }
        await loadSnapshot(using: session)
    }

    @discardableResult
    func send(_ target: ControlTarget, value: String, durationMinutes: Int? = nil, using session: SensorStore) async -> Bool {
        let servo = target == .door || target == .window
        guard servo ? canOperateServos : canOperate else { return false }
        revision += 1
        pendingTarget = target
        messageTarget = target
        commandMessage = nil
        defer { pendingTarget = nil }

        let id = UUID()
        let request = ControlRequest(id: id, requestedAt: Int64(Date().timeIntervalSince1970 * 1000),
                                     target: target.rawValue, value: value, durationMinutes: durationMinutes)
        var applied = false
        do {
            let receipt = try await submit(request, using: session)
            guard receipt.id == id else { throw URLError(.badServerResponse) }
            var status = receipt.status
            if status == .pending {
                status = try await waitForReceipt(id, using: session)
            }
            switch status {
            case .applied:
                applied = true
                if servo { commandMessage = "舵机指令已执行，门窗实际位置未确认" }
            case .rejected:
                commandMessage = "设备未执行，请刷新状态后再操作"
            case .pending, .unknown:
                commandMessage = "执行结果未知，请核对设备状态"
            }
        } catch is CancellationError {
            return false
        } catch APIError.status(403) {
            commandMessage = "当前账号没有此设备的控制权限"
        } catch APIError.status(409) {
            commandMessage = "设备正在处理另一条指令，请稍后再试"
        } catch APIError.status(503) {
            commandMessage = "控制板离线，请稍后再试"
        } catch APIError.status(400) {
            commandMessage = "指令无效，请检查手机时间后再试"
        } catch APIError.status(422) {
            commandMessage = "当前控制板固件需要更新"
        } catch {
            commandMessage = "执行结果未知，请核对设备状态"
        }
        await loadSnapshot(using: session)
        return applied
    }

    private func loadSnapshot(using session: SensorStore) async {
        revision += 1
        let current = revision
        do {
            let data = try await session.authorizedData(path: controlPath)
            let updated = try JSONDecoder().decode(ControlSnapshot.self, from: data)
            guard current == revision, !Task.isCancelled else { return }
            snapshot = updated
            connectionMessage = nil
        } catch {
            guard current == revision, !Task.isCancelled, !(error is CancellationError) else { return }
            if (error as? URLError)?.code == .cancelled { return }
            if (error as? APIError) == .status(404) {
                snapshot = nil
                connectionMessage = "当前后端尚未接入设备控制"
            } else {
                connectionMessage = "控制服务暂时无法连接"
            }
        }
    }

    private func submit(_ request: ControlRequest, using session: SensorStore) async throws -> ControlReceipt {
        let body = try JSONEncoder().encode(request)
        let data = try await session.authorizedData(path: controlPath + ["commands"], body: body)
        return try JSONDecoder().decode(ControlReceipt.self, from: data)
    }

    private func waitForReceipt(_ id: UUID, using session: SensorStore) async throws -> ControlReceipt.Status {
        let path = controlPath + ["commands", id.uuidString.lowercased()]
        for _ in 0..<17 {
            try await Task.sleep(nanoseconds: 750_000_000)
            let data = try await session.authorizedData(path: path)
            let receipt = try JSONDecoder().decode(ControlReceipt.self, from: data)
            guard receipt.id == id else { throw URLError(.badServerResponse) }
            if receipt.status != .pending { return receipt.status }
        }
        return .unknown
    }
}
