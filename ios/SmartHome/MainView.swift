import SwiftUI

let ink = Color(red: 0.05, green: 0.10, blue: 0.19)
let blue = Color(red: 0.07, green: 0.30, blue: 0.80)
let canvas = Color(red: 0.92, green: 0.94, blue: 0.97)
let card = Color(red: 0.89, green: 0.92, blue: 0.98)
let muted = Color(red: 0.29, green: 0.36, blue: 0.46)
let onlineGreen = Color(red: 0.02, green: 0.48, blue: 0.28)
let beijing = TimeZone(identifier: "Asia/Shanghai")!

func formatTime(_ date: Date, _ format: String = "MM月dd日 HH:mm") -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = beijing
    formatter.dateFormat = format
    return formatter.string(from: date)
}

func value(_ value: Double?, unit: String, decimals: Int) -> String {
    guard let value else { return "—" + unit }
    return String(format: "%.*f%@", decimals, value, unit)
}

struct MainView: View {
    @EnvironmentObject private var store: SensorStore
    @StateObject private var controlStore = ControlStore()
    @State private var selection = 0
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(selection: $selection) }
                .tabItem { Label("首页", systemImage: selection == 0 ? "house.fill" : "house") }.tag(0)
            NavigationStack { DevicesView() }
                .tabItem { Label("设备", systemImage: selection == 1 ? "square.grid.2x2.fill" : "square.grid.2x2") }
                .tag(1)
            NavigationStack { SensorDetailView() }
                .tabItem { Label("记录", systemImage: "chart.bar.xaxis") }.tag(2)
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: selection == 3 ? "gearshape.fill" : "gearshape") }.tag(3)
        }
        .tint(blue)
        .environmentObject(controlStore)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await controlStore.refresh(using: store)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .task { await store.refresh() }
        .onChange(of: store.period) { _ in Task { await store.refresh() } }
        .onReceive(timer) { _ in
            if scenePhase == .active && store.isConfigured { Task { await store.refresh() } }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && store.isConfigured { Task { await store.refresh() } }
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var store: SensorStore
    @EnvironmentObject private var control: ControlStore
    @Binding var selection: Int

    var body: some View {
        DashboardPage {
            DashboardHeading(title: "我的家", subtitle: "客厅", showsConnection: true)
            EnvironmentCard(
                title: "实时环境",
                temperature: value(control.online ? control.snapshot?.state?.temperature.map(Double.init) : store.latest?.temperature,
                                   unit: "°C", decimals: 0),
                humidity: value(control.online ? control.snapshot?.state?.humidity.map(Double.init) : store.latest?.humidity,
                                unit: "%", decimals: 0)
            ) {
                HStack {
                    let updated = control.online ? control.snapshot?.lastSeen : store.latest?.time
                    Text(updated.map { formatTime($0, "HH:mm") + (control.online ? " 更新" : " 采集记录") } ?? "等待设备上报")
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 8)
                    NavigationLink {
                        SensorDetailView(fromHome: true)
                    } label: {
                        Label("查看记录", systemImage: "chevron.right")
                            .labelStyle(TrailingIconStyle())
                    }.buttonStyle(.plain)
                }.font(.footnote.weight(.medium)).foregroundStyle(.white)
            }
            HStack(spacing: 8) {
                ForEach(BoardSensor.allCases) { sensor in
                    NavigationLink {
                        EnvironmentView()
                    } label: {
                        SensorTile(sensor: sensor, reading: sensor.reading(in: control.snapshot?.state))
                    }.buttonStyle(.plain)
                }
            }
            HStack {
                Text("快捷控制").font(.title3.bold()).foregroundStyle(ink)
                Spacer()
                Button { selection = 1 } label: {
                    Label("全部设备", systemImage: "chevron.right")
                        .labelStyle(TrailingIconStyle())
                        .font(.footnote.weight(.semibold))
                }
            }
            HStack(spacing: 8) {
                SwitchDeviceRow(device: .light, compact: true).background(.white, in: RoundedRectangle(cornerRadius: 13))
                SwitchDeviceRow(device: .fan, compact: true).background(.white, in: RoundedRectangle(cornerRadius: 13))
            }
            DashboardCard { RGBDeviceLink() }
            HStack(spacing: 8) {
                DashboardCard { ServoDeviceLink(device: .door, compact: true) }
                DashboardCard { ServoDeviceLink(device: .window, compact: true) }
            }
            ControlFeedback(target: control.messageTarget)
        }
        .navigationTitle("首页")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            async let readings: Void = store.refresh()
            async let controls: Void = control.refresh(using: store)
            _ = await (readings, controls)
        }
    }
}

struct DashboardPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
            .background(canvas.ignoresSafeArea())
            .toolbarBackground(canvas, for: .navigationBar)
            .toolbarBackground(.white, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

struct DashboardHeading: View {
    @EnvironmentObject private var control: ControlStore
    let title: String
    var subtitle: String? = nil
    var showsConnection = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.bold()).foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(muted) }
            }
            Spacer(minLength: 8)
            if showsConnection {
                let text = control.online ? "ESP32 在线" : (control.snapshot == nil ? "ESP32 未连接" : "ESP32 离线")
                Label(text, systemImage: "circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(control.online ? onlineGreen : muted)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background((control.online ? onlineGreen : muted).opacity(0.12), in: Capsule())
                    .padding(.top, 8)
            }
        }
    }
}

struct DashboardCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 13))
    }
}

struct DeviceIcon: View {
    let symbol: String
    var foreground = Color(red: 0.13, green: 0.31, blue: 0.59)
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.49, weight: .medium))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background(card, in: RoundedRectangle(cornerRadius: size * 0.23))
            .accessibilityHidden(true)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold)).foregroundStyle(ink).accessibilityHidden(true)
    }
}

struct TrailingIconStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.title; configuration.icon }
    }
}

struct EnvironmentCard<Footer: View>: View {
    var title: String?
    let temperature: String
    let humidity: String
    var currentLabels = false
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.subheadline.bold()) }
            HStack(spacing: 16) {
                metric(currentLabels ? "当前温度" : "温度", symbol: "thermometer.medium", text: temperature)
                Rectangle().fill(.white.opacity(0.32)).frame(width: 1, height: 62).accessibilityHidden(true)
                metric(currentLabels ? "当前湿度" : "湿度", symbol: "drop", text: humidity)
            }
            if Footer.self != EmptyView.self {
                Rectangle().fill(.white.opacity(0.28)).frame(height: 1).accessibilityHidden(true)
                footer()
            }
        }.padding(14).foregroundStyle(.white)
            .background(
                LinearGradient(colors: [blue, Color(red: 0.12, green: 0.30, blue: 0.65)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 13)
            )
    }

    private func metric(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.white.opacity(0.9))
            Text(text).font(.system(size: 37, weight: .bold)).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.6)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
