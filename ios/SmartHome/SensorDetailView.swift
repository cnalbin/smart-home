import SwiftUI
import Charts

struct SensorDetailView: View {
    @EnvironmentObject private var store: SensorStore
    @State private var showTemperature = true
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    metric("当前温度", symbol: "thermometer.medium", number: value(store.latest?.temperature, unit: "°C", decimals: 1), color: green.opacity(0.12))
                    metric("当前湿度", symbol: "drop", number: value(store.latest?.humidity, unit: "%", decimals: 0), color: Color.cyan.opacity(0.10))
                }
                if !store.error.isEmpty {
                    Label(store.error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                } else if let latest = store.latest, !store.online {
                    Label("数据未更新 · 最后接收 \(formatTime(latest.receivedAt))", systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                }
                segmented(["温度", "湿度"], selected: showTemperature ? 0 : 1) { showTemperature = $0 == 0 }
                segmented(Period.allCases.map(\.rawValue), selected: Period.allCases.firstIndex(of: store.period) ?? 0) {
                    store.period = Period.allCases[$0]
                }
                chart
                HStack {
                    Text("历史记录").font(.title3.bold()).foregroundStyle(ink)
                    Spacer()
                    Text(periodLabel).font(.subheadline).foregroundStyle(.secondary)
                }
                history
            }.padding(.horizontal, 20).padding(.bottom, 28)
        }
        .background(canvas)
        .navigationTitle("温湿度")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
    }
    private var periodLabel: String {
        switch store.period { case .day: return "今天"; case .week: return "近7天"; case .month: return "近30天" }
    }
    private func segmented(_ labels: [String], selected: Int, select: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(labels.indices, id: \.self) { index in
                Button { select(index) } label: {
                    Text(labels[index]).font(.subheadline.weight(.medium))
                        .foregroundStyle(index == selected ? Color.white : ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(index == selected ? green : Color.clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(index == selected ? .isSelected : [])
            }
        }.padding(3).background(card, in: Capsule())
    }
    private func metric(_ name: String, symbol: String, number: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(name, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(ink)
            Text(number).font(.system(size: 29, weight: .bold, design: .rounded)).foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, minHeight: 105, alignment: .leading).padding(.horizontal, 15)
            .background(color, in: RoundedRectangle(cornerRadius: 16))
    }
    @ViewBuilder private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showTemperature ? "°C" : "%").font(.caption).foregroundStyle(.secondary)
            if store.points.isEmpty {
                VStack(spacing: 8) {
                    if store.loading { ProgressView() }
                    else { Image(systemName: "chart.xyaxis.line"); Text("该时间范围暂无数据") }
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 180)
            } else {
                Chart(store.points) { point in
                    let number = showTemperature ? point.temperature : point.humidity
                    LineMark(x: .value("时间", point.time), y: .value("数值", number))
                        .foregroundStyle(green).interpolationMethod(.monotone)
                    AreaMark(x: .value("时间", point.time), y: .value("数值", number))
                        .foregroundStyle(LinearGradient(colors: [green.opacity(0.24), green.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("时间", point.time), y: .value("数值", number))
                        .foregroundStyle(green).symbolSize(store.points.count == 1 ? 28 : 0)
                }
                .chartXScale(domain: store.period.range.0...store.period.range.1)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(.gray.opacity(0.15))
                        AxisValueLabel(format: store.period == .day ? .dateTime.hour().minute() : .dateTime.month().day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .environment(\.timeZone, beijing)
                .frame(height: 185)
            }
        }.padding(.top, 6)
    }
    private var history: some View {
        VStack(spacing: 0) {
            if store.history.isEmpty {
                Text(store.loading ? "正在加载…" : "暂无历史记录").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(20)
            } else {
                ForEach(store.history) { reading in
                    HStack(spacing: 8) {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatTime(reading.time)).lineLimit(1)
                            if reading.measuredAt == nil { Text("接收时间").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 4)
                        Text(value(reading.temperature, unit: "°C", decimals: 1)).monospacedDigit()
                        Text(value(reading.humidity, unit: "%", decimals: 0)).monospacedDigit()
                    }.font(.caption).foregroundStyle(ink).padding(.horizontal, 14).padding(.vertical, 12)
                    if reading.id != store.history.last?.id { Divider().padding(.leading, 38) }
                }
                if store.nextBeforeId > 0 {
                    Button { Task { await store.loadMore() } } label: {
                        if store.loadingMore { ProgressView() } else { Text("加载更多") }
                    }.font(.subheadline).foregroundStyle(green).padding(14).disabled(store.loadingMore)
                }
            }
        }.background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SensorStore
    @State private var url = ""
    @State private var device = ""
    @State private var token = ""
    @State private var message = ""
    var body: some View {
        Form {
            Section("服务器连接") {
                TextField("HTTPS 服务器地址", text: $url).textInputAutocapitalization(.never)
                    .keyboardType(.URL).autocorrectionDisabled()
                TextField("设备编号", text: $device).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("API 访问密钥", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("服务器和设备编号已预填。请填写后端 API 密钥（不是 Wi-Fi 或 RabbitMQ 密码）；密钥仅保存在本机钥匙串。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !message.isEmpty { Section { Text(message).font(.caption).foregroundStyle(.orange) } }
            Section {
                Button("保存并连接") {
                    do {
                        try store.saveSettings(url: url, id: device, secret: token)
                        message = "已保存，正在连接。"
                        Task { await store.refresh() }
                    } catch { message = error.localizedDescription }
                }.foregroundStyle(green)
            }
            Section("说明") {
                Text("温湿度数据约每 30 秒刷新。其他传感器和控制设备将在后续接入。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(canvas)
        .navigationTitle("设置")
        .onAppear { url = store.serverURL; device = store.deviceId; token = store.token }
    }
}
