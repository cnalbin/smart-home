import SwiftUI
import UIKit

private struct RGBColor {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(_ number: UInt32) {
        red = UInt8((number >> 16) & 255)
        green = UInt8((number >> 8) & 255)
        blue = UInt8(number & 255)
    }

    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.first == "#" ? String(trimmed.dropFirst()) : trimmed
        guard digits.utf8.count == 6,
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let number = UInt32(digits, radix: 16) else { return nil }
        self.init(number)
    }

    var hex: String { String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue)) }
    var color: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }
    var uiColor: UIColor { UIColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1) }
}

enum LampState {
    static func title(for raw: String?) -> String {
        guard let raw else { return "状态未知" }
        if raw == "off" { return "已关闭" }
        if let preset = LampPreset(rawValue: raw) { return preset.title }
        if let effect = LampEffect(rawValue: raw) { return effect.title }
        if let color = RGBColor(hex: raw) { return color.hex == "#FF7043" ? "珊瑚橙" : color.hex }
        return "状态未知"
    }

    static func color(for raw: String?) -> Color? {
        guard let raw else { return nil }
        if let preset = LampPreset(rawValue: raw) { return preset.color }
        return RGBColor(hex: raw)?.color
    }
}

private enum LampPreset: String, Identifiable {
    case red, orange, yellow, green, cyan, blue, purple, white

    static let shortcuts: [Self] = [.red, .orange, .yellow, .green, .blue, .white]
    var id: Self { self }

    var title: String {
        switch self {
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "暖黄色"
        case .green: return "绿色"
        case .cyan: return "蓝绿色"
        case .blue: return "蓝色"
        case .purple: return "紫色"
        case .white: return "白色"
        }
    }

    var color: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return Color(red: 1, green: 0.77, blue: 0.19)
        case .green: return .green
        case .cyan: return .cyan
        case .blue: return .blue
        case .purple: return .purple
        case .white: return .white
        }
    }
}

private enum LampEffect: String, CaseIterable, Identifiable {
    case rainbow, chase, breath, fade, blink, bounce

    var id: Self { self }
    var legacy: Bool { self == .rainbow || self == .chase }
    var title: String {
        switch self {
        case .rainbow: return "彩虹"
        case .chase: return "跑灯"
        case .breath: return "呼吸"
        case .fade: return "渐变"
        case .blink: return "闪烁"
        case .bounce: return "往返扫描"
        }
    }
    var symbol: String {
        switch self {
        case .rainbow: return "rainbow"
        case .chase: return "circle.dotted"
        case .breath: return "waveform.path.ecg"
        case .fade: return "circle.hexagongrid"
        case .blink: return "sparkles"
        case .bounce: return "arrow.left.and.right"
        }
    }
}

struct RGBControlView: View {
    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore
    @State private var duration = Duration.continuous

    private enum Duration: Int, CaseIterable, Identifiable {
        case continuous = 0, five = 5, fifteen = 15, thirty = 30

        var id: Self { self }
        var minutes: Int? { self == .continuous ? nil : rawValue }
        var label: String { self == .continuous ? "持续" : "\(rawValue) 分钟" }
    }

    var body: some View {
        DashboardPage {
            currentStatus
            DashboardCard {
                NavigationLink { RGBColorPickerView() } label: {
                    HStack(spacing: 10) {
                        DeviceIcon(symbol: "paintpalette")
                        Text("自选颜色").font(.subheadline.bold()).foregroundStyle(ink)
                        Spacer()
                        Chevron()
                    }.padding(10).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Label("常用颜色", systemImage: "slider.horizontal.3").font(.headline).foregroundStyle(ink)
            DashboardCard {
                HStack(spacing: 0) {
                    ForEach(LampPreset.shortcuts) { preset in
                        Button {
                            Task { await control.send(.rgb, value: preset.rawValue, using: session) }
                        } label: {
                            let selected = control.snapshot?.state?.rgb == preset.rawValue
                            Circle().fill(preset.color).overlay(Circle().strokeBorder(ink.opacity(0.24)))
                                .frame(width: 35, height: 35)
                                .padding(3)
                                .overlay { if selected { Circle().strokeBorder(blue, lineWidth: 2) } }
                                .frame(maxWidth: .infinity, minHeight: 47)
                                .contentShape(Rectangle())
                                .accessibilityLabel(preset.title)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }.buttonStyle(.plain).disabled(!control.canOperate)
                    }
                }.padding(.horizontal, 5)
            }
            HStack {
                Label("灯效", systemImage: "lightbulb").font(.headline).foregroundStyle(ink)
                Spacer()
                Menu {
                    Picker("播放时长", selection: $duration) {
                        ForEach(Duration.allCases) { option in
                            Text(option.label).tag(option).disabled(!control.advancedRGB && option != .continuous)
                        }
                    }
                } label: {
                    Label("播放时长 · " + duration.label, systemImage: "timer")
                        .font(.caption.weight(.semibold)).foregroundStyle(blue)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white, in: Capsule())
                }.disabled((!control.advancedRGB && duration == .continuous) || control.pendingTarget != nil)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                ForEach(LampEffect.allCases) { effect in effectButton(effect) }
            }
            Button("关闭 RGB 灯") {
                Task { await control.send(.rgb, value: "off", using: session) }
            }.buttonStyle(DashboardButtonStyle(outlined: true)).disabled(!control.canOperate)
            if control.online && !control.advancedRGB {
                Text("自选颜色、新灯效和定时需要更新 ESP32 固件。").font(.footnote).foregroundStyle(muted)
            }
            ControlFeedback(target: .rgb)
        }
        .navigationTitle("RGB 灯")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable { await control.refresh(using: session) }
    }

    private var currentStatus: some View {
        let state = control.snapshot?.state
        let effect = state.flatMap { LampEffect(rawValue: $0.rgb) }
        return DashboardCard {
            HStack(spacing: 12) {
                DeviceIcon(symbol: "circle.hexagongrid", size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(control.online ? (effect == nil ? "当前颜色" : "当前灯效") : "上次上报")
                        .font(.caption).foregroundStyle(muted)
                    HStack(spacing: 7) {
                        if let color = LampState.color(for: state?.rgb) {
                            Circle().fill(color).overlay(Circle().strokeBorder(ink.opacity(0.15)))
                                .frame(width: 18, height: 18)
                        }
                        Text(LampState.title(for: state?.rgb)).font(.title3.bold()).foregroundStyle(ink)
                    }
                    if control.online, let seconds = state?.rgbRemainingSeconds {
                        Text("剩余 " + String(format: "%02d:%02d", seconds / 60, seconds % 60))
                            .font(.caption.monospacedDigit()).foregroundStyle(muted)
                    }
                }
            }.padding(14)
        }
    }

    private func effectButton(_ effect: LampEffect) -> some View {
        let selected = control.snapshot?.state?.rgb == effect.rawValue
        let minutes = duration.minutes
        let unsupported = !control.advancedRGB && (!effect.legacy || minutes != nil)
        return Button {
            Task { await control.send(.rgb, value: effect.rawValue, durationMinutes: minutes, using: session) }
        } label: {
            DashboardCard {
                HStack(spacing: 6) {
                    DeviceIcon(symbol: effect.symbol, size: 30)
                    Text(effect.title).font(.subheadline.bold()).foregroundStyle(ink)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "play.circle.fill" : "play.circle")
                        .font(.body).foregroundStyle(blue).accessibilityHidden(true)
                }.padding(8)
            }
        }.buttonStyle(.plain)
            .disabled(!control.canOperate || unsupported)
            .opacity(unsupported ? 0.5 : 1)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct RGBColorPickerView: View {
    @EnvironmentObject private var control: ControlStore
    @EnvironmentObject private var session: SensorStore
    @Environment(\.dismiss) private var dismiss
    @State private var hue = 0.04
    @State private var saturation = 0.74
    @State private var brightness = 1.0
    @State private var hex = "#FF7043"

    private var preview: Color { RGBColor(hex: hex)?.color ?? Color(hue: hue, saturation: saturation, brightness: brightness) }
    private var hueColor: Color { Color(hue: hue, saturation: 1, brightness: 1) }

    var body: some View {
        DashboardPage {
            DashboardCard {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 10).fill(preview)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ink.opacity(0.14)))
                        .frame(width: 54, height: 54).accessibilityLabel(hex)
                    Divider().frame(height: 43)
                    Text("颜色预览").font(.headline).foregroundStyle(ink)
                }.padding(14)
            }
            DashboardCard {
                VStack(spacing: 14) {
                    saturationPalette
                    HStack(spacing: 12) {
                        Text("色相").font(.caption.bold())
                        hueSlider
                    }
                    HStack(spacing: 12) {
                        Text("十六进制颜色").font(.caption.bold())
                        TextField("#RRGGBB", text: Binding(get: { hex }, set: { text in
                            hex = text
                            synchronizeControls(text)
                        }))
                            .font(.subheadline.monospaced()).textInputAutocapitalization(.characters)
                            .autocorrectionDisabled().submitLabel(.done)
                            .padding(7).background(canvas.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(muted.opacity(0.25)))
                            .accessibilityLabel("十六进制颜色")
                    }
                    Text(RGBColor(hex: hex) == nil ? "请输入 6 位十六进制颜色值" : "选择后点应用")
                        .font(.caption2).foregroundStyle(muted)
                }.foregroundStyle(ink).padding(13)
            }
            Button("应用颜色") {
                guard let color = RGBColor(hex: hex) else { return }
                Task {
                    if await control.send(.rgb, value: color.hex, using: session) { dismiss() }
                }
            }.buttonStyle(DashboardButtonStyle())
                .disabled(RGBColor(hex: hex) == nil || !control.canOperate || !control.advancedRGB)
            if control.online && !control.advancedRGB {
                Text("自选颜色需要更新 ESP32 固件。").font(.footnote).foregroundStyle(muted)
            }
            ControlFeedback(target: .rgb)
        }
        .navigationTitle("自选颜色")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            if let raw = control.snapshot?.state?.rgb, raw.hasPrefix("#"), let current = RGBColor(hex: raw) {
                hex = current.hex
            }
            synchronizeControls(hex)
        }
    }

    private var saturationPalette: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [.white, hueColor], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                Circle().strokeBorder(.white, lineWidth: 2).shadow(radius: 2).frame(width: 19, height: 19)
                    .position(x: marker(saturation, length: proxy.size.width),
                              y: marker(1 - brightness, length: proxy.size.height))
            }.clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    saturation = bounded(drag.location.x / proxy.size.width)
                    brightness = 1 - bounded(drag.location.y / proxy.size.height)
                    updateHex()
                })
                .accessibilityHidden(true)
        }.frame(height: 162)
    }

    private var hueSlider: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule().fill(LinearGradient(
                    colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) },
                    startPoint: .leading, endPoint: .trailing
                )).frame(height: 14)
                Circle().fill(hueColor).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(radius: 2).frame(width: 19, height: 19)
                    .position(x: marker(hue, length: proxy.size.width), y: proxy.size.height / 2)
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    hue = bounded(drag.location.x / proxy.size.width)
                    updateHex()
                })
        }.frame(height: 36)
            .accessibilityRepresentation {
                Slider(value: Binding(get: { hue }, set: { selected in
                    hue = selected
                    updateHex()
                }), in: 0...1) { Text("色相") }
            }
    }

    private func marker(_ fraction: Double, length: CGFloat) -> CGFloat {
        min(max(length * CGFloat(fraction), 9.5), max(length - 9.5, 9.5))
    }

    private func bounded(_ value: CGFloat) -> Double { min(max(Double(value), 0), 1) }

    private func updateHex() {
        let uiColor = UIColor(hue: CGFloat(hue), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: nil)
        hex = String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()),
                     Int((blue * 255).rounded()))
    }

    private func synchronizeControls(_ text: String) {
        guard let color = RGBColor(hex: text) else { return }
        var nextHue: CGFloat = 0
        var nextSaturation: CGFloat = 0
        var nextBrightness: CGFloat = 0
        color.uiColor.getHue(&nextHue, saturation: &nextSaturation, brightness: &nextBrightness, alpha: nil)
        if nextSaturation > 0 { hue = Double(nextHue) }
        saturation = Double(nextSaturation)
        brightness = Double(nextBrightness)
    }
}
