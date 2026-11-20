import SwiftUI
import Charts

let ink = Color(red: 0.06, green: 0.12, blue: 0.19)
let green = Color(red: 0.18, green: 0.46, blue: 0.27)
let canvas = Color(red: 0.97, green: 0.96, blue: 0.94)
let card = Color(red: 0.94, green: 0.93, blue: 0.90)
let beijing = TimeZone(identifier: "Asia/Shanghai")!

func formatTime(_ date: Date, _ format: String = "MM月dd日 HH:mm") -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = beijing
    formatter.dateFormat = format
    return formatter.string(from: date)
}
func value(_ value: Double?, unit: String, decimals: Int) -> String {
    guard let value else { return "--" + unit }
    return String(format: "%.*f%@", decimals, value, unit)
}

struct MainView: View {
    @EnvironmentObject private var store: SensorStore
    @StateObject private var controlStore = ControlStore()
    @State private var selection = 0
    @Environment(\.scenePhase) private var scenePhase
    private var controlVisible: Bool { selection == 1 && scenePhase == .active }
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { HomeView(selection: $selection) }
                .tabItem { Label("首页", systemImage: "house.fill") }.tag(0)
            NavigationStack { DevicesView() }
                .tabItem { Label("设备", systemImage: "square.grid.2x2.fill") }.tag(1)
            NavigationStack { SensorDetailView() }
                .tabItem { Label("记录", systemImage: "chart.bar") }.tag(2)
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
        }
        .tint(green)
        .environmentObject(controlStore)
        .task(id: controlVisible) {
            guard controlVisible else { return }
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
    @Binding var selection: Int
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("我的家").font(.system(size: 34, weight: .bold)).foregroundStyle(ink)
                    HStack(spacing: 6) {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                        Text(statusText).font(.subheadline.bold()).foregroundStyle(statusColor)
                    }.padding(.horizontal, 12).padding(.vertical, 7)
                        .background(statusColor.opacity(0.10), in: Capsule())
                }
                NavigationLink { SensorDetailView() } label: { hero }.buttonStyle(.plain)
                if !store.error.isEmpty { ErrorNotice(message: store.error) }
                if !store.isConfigured {
                    Button("查看连接状态") { selection = 3 }.font(.subheadline.bold()).foregroundStyle(green)
                }
                Button {
                    selection = 1
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(green)
                        Text("设备控制").font(.headline).foregroundStyle(ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }.padding(18).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
        }.background(canvas).toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
    }
    private var statusText: String {
        if !store.isConfigured { return "未设置" }
        if !store.error.isEmpty { return "连接异常" }
        if store.latest == nil { return store.error.isEmpty ? "等待数据" : "连接异常" }
        return store.online ? "设备在线" : "数据未更新"
    }
    private var statusColor: Color { store.online ? green : .secondary }
    private var hero: some View {
        ZStack(alignment: .leading) {
            GeometryReader { geo in
                Image("HomeLandscape").resizable().scaledToFill().frame(width: geo.size.width, height: geo.size.height).clipped()
            }
            LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 0) {
                    heroMetric("温度", symbol: "thermometer.medium", text: value(store.latest?.temperature, unit: "°C", decimals: 1))
                    Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 62).padding(.horizontal, 18)
                    heroMetric("湿度", symbol: "drop", text: value(store.latest?.humidity, unit: "%", decimals: 0))
                }
                if let latest = store.latest {
                    Text("更新于 " + formatTime(latest.time)).font(.caption).foregroundStyle(.white.opacity(0.95))
                } else {
                    Text(store.isConfigured ? "等待设备上传" : "服务配置不可用")
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
            }.padding(24)
        }.frame(height: 180).clipShape(RoundedRectangle(cornerRadius: 22))
    }
    private func heroMetric(_ name: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(name, systemImage: symbol).font(.subheadline)
            Text(text).font(.system(size: 31, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.65)
        }.foregroundStyle(.white)
    }
}

private struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
