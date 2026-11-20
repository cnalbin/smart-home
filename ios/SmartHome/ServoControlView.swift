import SwiftUI

enum ServoDevice {
    case door, window

    var title: String { self == .door ? "门" : "窗" }
    var target: ControlTarget { self == .door ? .door : .window }
    var symbol: String { self == .door ? "door.left.hand.closed" : "window.vertical.closed" }

    func lastAction(in state: ControlOutputs?) -> String {
        switch self == .door ? state?.doorTarget : state?.windowTarget {
        case "open": return "开" + title
        case "closed": return "关" + title
        default: return "暂无"
        }
    }
}

struct ServoDeviceLink: View {
    let device: ServoDevice
    var compact = false

    var body: some View {
        NavigationLink { ServoControlView(device: device) } label: {
            HStack(spacing: compact ? 5 : 10) {
                DeviceIcon(symbol: device.symbol, size: compact ? 33 : 42)
                if compact {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(device.title).font(.subheadline.bold()).foregroundStyle(ink)
                        Text("位置未确认").font(.caption2).foregroundStyle(muted)
                    }
                    Spacer(minLength: 0)
                } else {
                    Text(device.title).font(.subheadline.bold()).foregroundStyle(ink)
                    Spacer()
                    Text("位置未确认").font(.caption).foregroundStyle(muted)
                }
                Chevron()
            }.padding(compact ? 9 : 12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct ServoControlView: View {
    private enum Action: String, Identifiable {
        case open, closed

        var id: Self { self }
        var verb: String { self == .open ? "开" : "关" }
    }

    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore
    @State private var confirmation: Action?
    let device: ServoDevice

    var body: some View {
        DashboardPage {
            DashboardCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        DeviceIcon(symbol: device.symbol, size: 66)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.title).font(.title2.bold()).foregroundStyle(ink)
                            Text("实际位置未确认").font(.subheadline).foregroundStyle(muted)
                        }
                    }
                    Divider()
                    HStack {
                        Text("上次指令").foregroundStyle(muted)
                        Spacer()
                        Text(device.lastAction(in: control.snapshot?.state)).foregroundStyle(ink)
                    }.font(.subheadline)
                }.padding(15)
            }
            Text("操作").font(.headline).foregroundStyle(ink).padding(.top, 8)
            HStack(spacing: 10) {
                actionButton(.open)
                actionButton(.closed)
            }.disabled(!control.canOperateServos)
            if control.online && control.snapshot?.canControl == true && control.snapshot?.servoControlAvailable != true {
                Label("舵机控制未启用", systemImage: "info.circle").font(.footnote).foregroundStyle(muted)
            } else if !control.online && control.connectionMessage == nil {
                Label("ESP32 未连接", systemImage: "info.circle").font(.footnote).foregroundStyle(muted)
            }
            ControlFeedback(target: device.target)
        }
        .navigationTitle(device.title + "控制")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await control.refresh(using: session) }
        .sheet(item: $confirmation) { action in
            confirmationSheet(for: action)
                .presentationDetents([.height(238), .medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func actionButton(_ action: Action) -> some View {
        Button { confirmation = action } label: {
            Text(action.verb + device.title)
        }.buttonStyle(DashboardButtonStyle(outlined: true))
    }

    private func confirmationSheet(for action: Action) -> some View {
        let title = "确认" + action.verb + device.title
        return VStack(spacing: 12) {
            Text(title).font(.title3.bold()).foregroundStyle(ink).accessibilityAddTraits(.isHeader)
            Text("请确认\(device.title)边无人或障碍物。")
                .font(.subheadline).foregroundStyle(muted).multilineTextAlignment(.center)
            Button(title) {
                confirmation = nil
                Task { await control.send(device.target, value: action.rawValue, using: session) }
            }.buttonStyle(DashboardButtonStyle()).disabled(!control.canOperateServos)
            Button("取消", role: .cancel) { confirmation = nil }
                .buttonStyle(DashboardButtonStyle(outlined: true, accent: muted))
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DashboardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var outlined = false
    var accent = blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(outlined ? accent : .white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(outlined ? Color.white : accent, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if outlined { RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 1) }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.43)
    }
}
