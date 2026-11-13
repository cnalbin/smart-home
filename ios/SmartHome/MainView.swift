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
    @State private var selection = 0
    @Environment(\.scenePhase) private var scenePhase
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
        .task(id: store.period) { await store.refresh() }
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
                    Button("设置服务器连接") { selection = 3 }.font(.subheadline.bold()).foregroundStyle(green)
                }
                sectionTitle("环境监测", note: "规划中")
                HStack(spacing: 10) {
                    PlaceholderTile(title: "气体检测", symbol: "wind")
                    PlaceholderTile(title: "雨水检测", symbol: "cloud.rain")
                    PlaceholderTile(title: "人体感应", symbol: "figure.wave")
                }
                Divider()
                sectionTitle("设备控制", note: "规划中")
                HStack(spacing: 10) {
                    PlaceholderTile(title: "灯光", symbol: "lightbulb")
                    PlaceholderTile(title: "风扇", symbol: "fan")
                    PlaceholderTile(title: "门窗", symbol: "door.left.hand.closed")
                }
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
                } else { Text("等待设备上传").font(.caption).foregroundStyle(.white.opacity(0.9)) }
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

private func sectionTitle(_ title: String, note: String) -> some View {
    HStack { Text(title).font(.headline).foregroundStyle(ink); Text("（\(note)）").font(.subheadline).foregroundStyle(.secondary); Spacer() }
}
private struct PlaceholderTile: View {
    let title: String
    let symbol: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 25)).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            Text("待接入").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 4)
                .background(.black.opacity(0.05), in: Capsule())
        }.frame(maxWidth: .infinity).frame(height: 112).background(card, in: RoundedRectangle(cornerRadius: 15))
            .accessibilityElement(children: .combine)
    }
}
private struct ErrorNotice: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DevicesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("设备").font(.system(size: 34, weight: .bold)).foregroundStyle(ink)
                group("环境监测", symbol: "leaf", items: [("气体", "wind"), ("雨水", "cloud.rain"), ("人体", "figure.wave")])
                group("设备控制", symbol: "slider.horizontal.3", items: [("灯光", "lightbulb"), ("风扇", "fan"), ("门窗", "door.left.hand.closed")])
                group("安防与识别", symbol: "shield", items: [("RFID（门禁识别）", "creditcard"), ("语音（语音控制）", "mic")])
            }.padding(20)
        }.background(canvas).toolbar(.hidden, for: .navigationBar)
    }
    private func group(_ title: String, symbol: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.title3.bold()).foregroundStyle(ink).symbolRenderingMode(.hierarchical)
            VStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(spacing: 14) {
                        Image(systemName: items[index].1).font(.title3).foregroundStyle(.secondary)
                            .frame(width: 43, height: 43).background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                        Text(items[index].0).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                        Spacer()
                        Text("待接入").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.black.opacity(0.05), in: Capsule())
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                    if index < items.count - 1 { Divider().padding(.leading, 70) }
                }
            }.background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}
