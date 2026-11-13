import Foundation
import SwiftUI

struct Reading: Decodable, Identifiable {
    let id: Int64
    let deviceId: String
    let temperature: Double
    let humidity: Double
    let measuredAt: Date?
    let receivedAt: Date
    var time: Date { measuredAt ?? receivedAt }
}
struct ReadingPage: Decodable {
    let items: [Reading]
    let nextBeforeId: Int64
}
struct ChartPoint: Decodable, Identifiable {
    let time: Date
    let temperature: Double
    let humidity: Double
    let count: Int
    var id: Date { time }
}

enum Period: String, CaseIterable {
    case day = "日", week = "周", month = "月"
    var bucket: Int { switch self { case .day: return 60; case .week: return 3600; case .month: return 86400 } }
    var days: Int { switch self { case .day: return 1; case .week: return 7; case .month: return 30 } }
    var range: (Date, Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.startOfDay(for: Date())
        return (calendar.date(byAdding: .day, value: 1 - days, to: today)!,
                calendar.date(byAdding: .day, value: 1, to: today)!)
    }
}

enum APIError: LocalizedError {
    case address, credentials, unauthorized, status(Int), invalidDate
    var errorDescription: String? {
        switch self {
        case .address: return "服务器地址无效，请检查应用配置"
        case .credentials: return "应用连接配置不完整，请联系管理员"
        case .unauthorized: return "服务器认证失败，请联系管理员"
        case .status(let code): return "服务器返回错误（\(code)）"
        case .invalidDate: return "服务器返回了无法识别的时间"
        }
    }
}

@MainActor
final class SensorStore: ObservableObject {
    let serverURL = "https://home.u2483924.nyat.app:34977"
    let deviceId = "esp32-livingroom"
    private let token: String
    @Published var latest: Reading?
    @Published var history: [Reading] = []
    @Published var points: [ChartPoint] = []
    @Published var error = ""
    @Published var loading = false
    @Published var loadingMore = false
    @Published var period: Period = .day
    @Published var nextBeforeId: Int64 = 0
    private var generation = 0
    private var loadedPeriod: Period?
    private var loadedRangeStart: Date?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        if let url = Bundle.main.url(forResource: "ServiceConfig", withExtension: "plist"),
           let dictionary = NSDictionary(contentsOf: url), let value = dictionary["API_TOKEN"] as? String {
            token = value
        } else { token = "" }
    }
    var isConfigured: Bool { !serverURL.isEmpty && !token.isEmpty && !deviceId.isEmpty }
    var online: Bool {
        guard let latest else { return false }
        let age = Date().timeIntervalSince(latest.receivedAt)
        return age >= -60 && age < 180
    }
    private func request<T: Decodable>(_ type: T.Type, suffix: String = "", query: [URLQueryItem] = []) async throws -> T {
        guard let base = URL(string: serverURL), base.scheme?.lowercased() == "https", base.host != nil else { throw APIError.address }
        guard !token.isEmpty, !deviceId.isEmpty else { throw APIError.credentials }
        let endpoint = base.appendingPathComponent("api").appendingPathComponent("devices")
            .appendingPathComponent(deviceId).appendingPathComponent("readings")
        let url = suffix.isEmpty ? endpoint : endpoint.appendingPathComponent(suffix)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.address }
        if !query.isEmpty { components.queryItems = query }
        guard let finalURL = components.url else { throw APIError.address }
        var request = URLRequest(url: finalURL)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 401 || response.statusCode == 403 { throw APIError.unauthorized }
        guard response.statusCode == 200 else { throw APIError.status(response.statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = fractional.date(from: raw) { return value }
            if let value = ISO8601DateFormatter().date(from: raw) { return value }
            throw APIError.invalidDate
        }
        return try decoder.decode(type, from: data)
    }
    private func dateString(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func rangeQuery(_ period: Period) -> [URLQueryItem] {
        let (from, to) = period.range
        return [URLQueryItem(name: "from", value: dateString(from)), URLQueryItem(name: "to", value: dateString(to))]
    }
    func refresh() async {
        guard isConfigured else { return }
        loading = true
        generation += 1
        let version = generation, selected = period, rangeStart = period.range.0
        defer { if version == generation { loading = false } }
        do {
            let newest: Reading = try await request(Reading.self, suffix: "latest")
            guard version == generation, selected == period else { return }
            latest = newest
            let page: ReadingPage = try await request(ReadingPage.self, query: rangeQuery(selected) + [URLQueryItem(name: "limit", value: "50")])
            let chart: [ChartPoint] = try await request([ChartPoint].self, suffix: "chart", query: rangeQuery(selected) + [URLQueryItem(name: "bucketSeconds", value: String(selected.bucket))])
            guard version == generation, selected == period else { return }
            if loadedPeriod == selected && loadedRangeStart == rangeStart && history.count > 50 {
                let ids = Set(page.items.map(\.id))
                history = page.items + history.filter { !ids.contains($0.id) }
            } else {
                history = page.items
                nextBeforeId = page.nextBeforeId
            }
            loadedPeriod = selected; loadedRangeStart = rangeStart; points = chart; error = ""
        } catch {
            guard version == generation else { return }
            if let apiError = error as? APIError, case .status(404) = apiError { self.error = "暂无温湿度数据，请确认设备正在上传" }
            else { self.error = error.localizedDescription }
        }
    }
    func loadMore() async {
        guard nextBeforeId > 0, !loadingMore, !loading else { return }
        loadingMore = true
        let version = generation, selected = period, cursor = nextBeforeId
        defer { loadingMore = false }
        do {
            let page: ReadingPage = try await request(ReadingPage.self, query: rangeQuery(selected) + [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "beforeId", value: String(cursor))])
            guard version == generation, selected == period else { return }
            let known = Set(history.map(\.id))
            history.append(contentsOf: page.items.filter { !known.contains($0.id) })
            nextBeforeId = page.nextBeforeId
        } catch { if version == generation { self.error = error.localizedDescription } }
    }
}
