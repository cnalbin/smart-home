import SwiftUI

struct DevicesView: View {
    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("设备").font(.largeTitle.bold()).foregroundStyle(ink)
                    HStack(spacing: 8) {
                        Circle().fill(control.online ? green : Color.secondary).frame(width: 9, height: 9)
                        Text("客厅 · " + connectionLabel).font(.subheadline).foregroundStyle(ink)
                    }
                }
                if let message = control.connectionMessage {
                    controlNotice(message)
                }
                VStack(alignment: .leading, spacing: 12) {
                    section("设备控制", symbol: "slider.horizontal.3")
                    VStack(spacing: 0) {
                        switchRow("黄灯", symbol: "lightbulb", target: .light, enabled: control.snapshot?.state?.light)
                        separator
                        switchRow("风扇", symbol: "fan", target: .fan, enabled: control.snapshot?.state?.fan)
                        separator
                        NavigationLink {
                            LampControlView()
                        } label: {
                            deviceRow("RGB 灯", symbol: "circle.hexagongrid", detail: lampName, dot: lampColor)
                        }.buttonStyle(.plain)
                        separator
                        NavigationLink {
                            ServoControlView()
                        } label: {
                            deviceRow("门窗", symbol: "door.left.hand.closed", detail: "状态未确认")
                        }.buttonStyle(.plain)
                    }.background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))

                    if let message = control.commandMessage {
                        controlNotice(message)
                    } else if control.snapshot?.canControl == false {
                        controlNotice("当前账号仅可查看设备")
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    section("环境监测", symbol: "leaf")
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            metric("温度", symbol: "thermometer.medium", reading: control.snapshot?.state?.temperature,
                                   unit: "°C")
                            Divider().frame(height: 46)
                            metric("湿度", symbol: "drop", reading: control.snapshot?.state?.humidity, unit: "%")
                        }.padding(16)
                        Divider().padding(.horizontal, 16)
                        NavigationLink {
                            ControlSensorsView()
                        } label: {
                            HStack {
                                Text("查看传感器").foregroundStyle(ink)
                                Spacer()
                                chevron
                            }.padding(16).frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }.background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 17))
                    if !control.online && control.snapshot?.state != nil {
                        Text("以上为上次上报的读数").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 22)
        }
        .background(canvas)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await control.refresh(using: session) }
    }

    private var connectionLabel: String {
        if control.connectionMessage != nil { return "连接异常" }
        if control.snapshot == nil { return "正在连接" }
        return control.online ? "在线" : "离线"
    }

    private var lamp: LampMode? {
        guard let mode = control.snapshot?.state?.rgb else { return nil }
        return LampMode(rawValue: mode)
    }

    private var lampName: String { control.pendingTarget == .rgb ? "正在执行…" : lamp?.title ?? "状态未知" }
    private var lampColor: Color? { lamp?.color }

    private var separator: some View { Divider().padding(.leading, 68).padding(.trailing, 14) }
    private var chevron: some View {
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private func section(_ title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(green).accessibilityHidden(true)
            Text(title).foregroundStyle(ink)
        }.font(.title3.bold()).accessibilityAddTraits(.isHeader)
    }

    private func switchRow(_ title: String, symbol: String, target: ControlTarget, enabled: Bool?) -> some View {
        let busy = control.pendingTarget == target
        let detail = busy ? "正在执行…" : enabled.map { $0 ? "已开启" : "已关闭" } ?? "状态未知"
        return HStack(spacing: 12) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(ink)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if busy {
                ProgressView().accessibilityLabel("正在执行")
            } else {
                Toggle(title, isOn: Binding(get: { enabled == true }, set: { desired in
                    Task { await control.send(target, value: desired ? "on" : "off", using: session) }
                }))
                .labelsHidden()
                .disabled(!control.canOperate || enabled == nil)
                .accessibilityLabel(title)
                .accessibilityValue(detail)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 59)
    }

    private func deviceRow(_ title: String, symbol: String, detail: String, dot: Color? = nil) -> some View {
        HStack(spacing: 12) {
            icon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(ink)
                HStack(spacing: 6) {
                    if let dot {
                        Circle().fill(dot).overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                            .frame(width: 12, height: 12).accessibilityHidden(true)
                    }
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer()
            chevron
        }.padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 59).contentShape(Rectangle())
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.title3).foregroundStyle(green)
            .frame(width: 43, height: 43)
            .background(green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private func metric(_ title: String, symbol: String, reading: Int?, unit: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(green).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(reading.map { "\($0)\(unit)" } ?? "—").font(.title2.bold()).foregroundStyle(ink)
                    .minimumScaleFactor(0.7).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}

private func controlNotice(_ value: String) -> some View {
    Label(value, systemImage: "exclamationmark.circle").font(.footnote)
        .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
}

private enum LampMode: String, CaseIterable, Identifiable {
    case off, red, orange, yellow, green, cyan, blue, purple, white, rainbow, chase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "已关闭"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "暖黄色"
        case .green: return "绿色"
        case .cyan: return "蓝绿色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .white: return "白色"
        case .rainbow: return "彩虹"
        case .chase: return "跑灯"
        }
    }

    var color: Color? {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return Color(red: 1, green: 0.75, blue: 0.20)
        case .green: return .green
        case .cyan: return .cyan
        case .blue: return .blue
        case .purple: return .purple
        case .white: return .white
        case .off, .rainbow, .chase: return nil
        }
    }
}

private struct LampControlView: View {
    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore

    var body: some View {
        List {
            Section("颜色与灯效") {
                ForEach(LampMode.allCases.filter { $0 != .off }) { mode in
                    Button {
                        Task { await control.send(.rgb, value: mode.rawValue, using: session) }
                    } label: {
                        HStack(spacing: 12) {
                            if let color = mode.color {
                                Circle().fill(color).overlay(Circle().strokeBorder(.black.opacity(0.15)))
                                    .frame(width: 22, height: 22).accessibilityHidden(true)
                            } else {
                                Image(systemName: "sparkles").frame(width: 22).accessibilityHidden(true)
                            }
                            Text(mode.title).foregroundStyle(ink)
                            Spacer()
                            if control.snapshot?.state?.rgb == mode.rawValue {
                                Image(systemName: "checkmark").foregroundStyle(green)
                            }
                        }.frame(minHeight: 36).contentShape(Rectangle())
                    }.disabled(!control.canOperate)
                }
            }
            Button("关闭 RGB 灯") {
                Task { await control.send(.rgb, value: LampMode.off.rawValue, using: session) }
            }.disabled(!control.canOperate)
            if control.pendingTarget == .rgb { ProgressView("正在执行…") }
            if let message = control.commandMessage ?? control.connectionMessage { controlNotice(message) }
        }
        .scrollContentBackground(.hidden)
        .background(canvas)
        .navigationTitle("RGB 灯")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct ServoControlView: View {
    private struct Action {
        let title: String
        let target: ControlTarget
        let value: String
    }

    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore
    @State private var action: Action?
    @State private var confirm = false

    var body: some View {
        List {
            Section("门") {
                Text(targetLabel(control.snapshot?.state?.doorTarget)).foregroundStyle(.secondary)
                controlButton("开门", target: .door, value: "open")
                controlButton("关门", target: .door, value: "closed")
            }
            Section("窗") {
                Text(targetLabel(control.snapshot?.state?.windowTarget)).foregroundStyle(.secondary)
                controlButton("开窗", target: .window, value: "open")
                controlButton("关窗", target: .window, value: "closed")
            }
            if control.pendingTarget == .door || control.pendingTarget == .window { ProgressView("正在执行…") }
            if let message = control.commandMessage ?? control.connectionMessage {
                controlNotice(message)
            } else if control.snapshot?.servoControlAvailable != true {
                controlNotice("门窗控制尚未启用或当前账号无权限")
            }
        }
        .scrollContentBackground(.hidden)
        .background(canvas)
        .navigationTitle("门窗")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("确认门窗操作", isPresented: $confirm, titleVisibility: .visible, presenting: action) { item in
            Button("确认" + item.title) {
                Task { await control.send(item.target, value: item.value, using: session) }
            }
            Button("取消", role: .cancel) {}
        } message: { _ in
            Text("请确认门窗周围无人或障碍物。")
        }
    }

    private func controlButton(_ title: String, target: ControlTarget, value: String) -> some View {
        Button(title) {
            action = Action(title: title, target: target, value: value)
            confirm = true
        }.disabled(!control.canOperateServos)
    }

    private func targetLabel(_ target: String?) -> String {
        guard let target else { return "位置未确认" }
        return (target == "open" ? "上次指令：打开" : "上次指令：关闭") + " · 位置未确认"
    }
}

private struct ControlSensorsView: View {
    @EnvironmentObject private var control: ControlStore

    var body: some View {
        List {
            Section(control.online ? "最近上报" : "上次上报 · 设备离线") {
                sensor("温度", value: control.snapshot?.state?.temperature, unit: " °C")
                sensor("湿度", value: control.snapshot?.state?.humidity, unit: " %")
                sensor("雨水原始值", value: control.snapshot?.state?.rain)
                sensor("气体传感器电平", value: control.snapshot?.state?.gas)
                sensor("人体传感器电平", value: control.snapshot?.state?.motion)
            }
        }
        .scrollContentBackground(.hidden)
        .background(canvas)
        .navigationTitle("环境监测")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func sensor(_ title: String, value: Int?, unit: String = "") -> some View {
        LabeledContent(title, value: value.map { "\($0)\(unit)" } ?? "—")
    }
}
