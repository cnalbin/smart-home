import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore

    var body: some View {
        DashboardPage {
            DashboardHeading(title: "设备", subtitle: "客厅", showsConnection: true)
            section("照明与风扇") {
                DashboardCard {
                    VStack(spacing: 0) {
                        SwitchDeviceRow(device: .light)
                        Divider().padding(.leading, 64)
                        RGBDeviceLink()
                        Divider().padding(.leading, 64)
                        SwitchDeviceRow(device: .fan)
                    }
                }
            }
            section("开合控制") {
                DashboardCard { ServoDeviceLink(device: .door) }
                DashboardCard { ServoDeviceLink(device: .window) }
            }
            section("传感器") {
                DashboardCard {
                    NavigationLink { EnvironmentView() } label: {
                        HStack(spacing: 10) {
                            DeviceIcon(symbol: "thermometer.medium")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("环境监测").font(.subheadline.bold()).foregroundStyle(ink)
                                Text("温湿度、雨水、气体、人体").font(.caption).foregroundStyle(muted)
                            }
                            Spacer(minLength: 4)
                            Chevron()
                        }.padding(12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            ControlFeedback(target: control.messageTarget)
        }
        .navigationTitle("设备")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await control.refresh(using: session) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(ink).accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

enum SwitchDevice {
    case light, fan

    var title: String { self == .light ? "黄灯" : "风扇" }
    var symbol: String { self == .light ? "lightbulb" : "fan" }
    var target: ControlTarget { self == .light ? .light : .fan }

    func isOn(in state: ControlOutputs?) -> Bool? {
        self == .light ? state?.light : state?.fan
    }
}

struct SwitchDeviceRow: View {
    @EnvironmentObject private var session: SensorStore
    @EnvironmentObject private var control: ControlStore
    let device: SwitchDevice
    var compact = false

    var body: some View {
        let reported = device.isOn(in: control.snapshot?.state)
        let pending = control.pendingTarget == device.target
        HStack(spacing: compact ? 6 : 10) {
            DeviceIcon(symbol: device.symbol, foreground: device == .light ? .orange : blue, size: compact ? 33 : 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.title).font(.subheadline.bold()).foregroundStyle(ink)
                Text(status(reported, pending: pending)).font(.caption2).foregroundStyle(muted)
            }.accessibilityHidden(true)
            Spacer(minLength: 0)
            Toggle(device.title, isOn: Binding(
                get: { reported == true },
                set: { next in
                    Task { await control.send(device.target, value: next ? "on" : "off", using: session) }
                }
            ))
            .labelsHidden()
            .tint(blue)
            .scaleEffect(compact ? 0.82 : 0.94, anchor: .trailing)
            .fixedSize()
            .disabled(!control.canOperate || reported == nil)
            .accessibilityValue(status(reported, pending: pending))
        }.padding(compact ? 9 : 12)
    }

    private func status(_ reported: Bool?, pending: Bool) -> String {
        if pending { return "执行中" }
        guard let reported else { return "未知" }
        return reported ? "已开启" : "已关闭"
    }
}

struct RGBDeviceLink: View {
    @EnvironmentObject private var control: ControlStore

    var body: some View {
        NavigationLink { RGBControlView() } label: {
            HStack(spacing: 10) {
                DeviceIcon(symbol: "circle.hexagongrid")
                VStack(alignment: .leading, spacing: 3) {
                    Text("RGB 灯").font(.subheadline.bold()).foregroundStyle(ink)
                    HStack(spacing: 5) {
                        if let color = LampState.color(for: control.snapshot?.state?.rgb) {
                            Circle().fill(color).overlay(Circle().strokeBorder(ink.opacity(0.15)))
                                .frame(width: 9, height: 9).accessibilityHidden(true)
                        }
                        Text(LampState.title(for: control.snapshot?.state?.rgb)).font(.caption).foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 4)
                Chevron()
            }.padding(12).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct ControlFeedback: View {
    @EnvironmentObject private var control: ControlStore
    let target: ControlTarget?

    var body: some View {
        if let target, target == control.pendingTarget {
            ProgressView("等待设备回执…").font(.footnote).foregroundStyle(muted)
        } else if let message = message {
            Label(message, systemImage: "info.circle").font(.footnote).foregroundStyle(muted)
        }
    }

    private var message: String? {
        if target != nil, target == control.messageTarget, let text = control.commandMessage { return text }
        if let text = control.connectionMessage { return text }
        if control.snapshot?.canControl == false { return "当前账号仅可查看设备" }
        return nil
    }
}

enum BoardSensor: String, CaseIterable, Identifiable {
    case rain, gas, motion

    var id: Self { self }
    var title: String {
        switch self {
        case .rain: return "雨水"
        case .gas: return "气体"
        case .motion: return "人体"
        }
    }
    var fullTitle: String {
        switch self {
        case .rain: return "雨水传感器"
        case .gas: return "气体传感器"
        case .motion: return "人体感应"
        }
    }
    var symbol: String {
        switch self {
        case .rain: return "cloud.rain"
        case .gas: return "flame"
        case .motion: return "figure.walk.motion"
        }
    }
    var unit: String { self == .rain ? "原始值" : "电平" }

    func reading(in state: ControlOutputs?) -> Int? {
        switch self {
        case .rain: return state?.rain
        case .gas: return state?.gas
        case .motion: return state?.motion
        }
    }
}

struct SensorTile: View {
    let sensor: BoardSensor
    let reading: Int?

    var body: some View {
        DashboardCard {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    DeviceIcon(symbol: sensor.symbol, size: 25)
                    Text(sensor.title).font(.caption.bold())
                }
                Text(reading.map(String.init) ?? "—").font(.title3.bold()).monospacedDigit()
                Text(sensor.unit).font(.caption2).foregroundStyle(muted)
            }.padding(.vertical, 8).frame(maxWidth: .infinity)
        }.foregroundStyle(ink).accessibilityElement(children: .combine)
    }
}

struct EnvironmentView: View {
    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore

    var body: some View {
        DashboardPage {
            HStack {
                Text(control.online ? "最近上报" : "上次上报 · ESP32 未连接")
                Spacer()
                Text(control.snapshot?.lastSeen.map { formatTime($0, "HH:mm") } ?? "—")
            }.font(.subheadline).foregroundStyle(muted)
            EnvironmentCard(
                title: nil,
                temperature: value(control.snapshot?.state?.temperature.map(Double.init), unit: "°C", decimals: 0),
                humidity: value(control.snapshot?.state?.humidity.map(Double.init), unit: "%", decimals: 0)
            ) { EmptyView() }
            Text("传感器读数").font(.headline).foregroundStyle(ink).padding(.top, 8)
            DashboardCard {
                VStack(spacing: 0) {
                    ForEach(BoardSensor.allCases) { sensor in
                        HStack(spacing: 12) {
                            DeviceIcon(symbol: sensor.symbol, size: 48)
                            Text(sensor.fullTitle).font(.subheadline.bold()).foregroundStyle(ink)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(sensor.reading(in: control.snapshot?.state).map(String.init) ?? "—")
                                    .font(.title2.bold()).monospacedDigit().foregroundStyle(ink)
                                Text(sensor.unit).font(.caption2).foregroundStyle(muted)
                            }
                        }.padding(12).accessibilityElement(children: .combine)
                        if sensor != .motion { Divider().padding(.leading, 67) }
                    }
                }
            }
        }
        .navigationTitle("环境监测")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await control.refresh(using: session) }
    }
}
