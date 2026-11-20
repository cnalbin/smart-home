import SwiftUI
import Charts

struct SensorDetailView: View {
    @EnvironmentObject private var store: SensorStore
    @State private var showTemperature = true
    @State private var visibleHistoryCount = 3
    var fromHome = false

    var body: some View {
        DashboardPage {
            DashboardHeading(title: "温湿度记录", subtitle: formatTime(Date(), "MM月dd日") + " · 客厅")
            EnvironmentCard(
                title: nil,
                temperature: value(store.latest?.temperature, unit: "°C", decimals: 1),
                humidity: value(store.latest?.humidity, unit: "%", decimals: 0),
                currentLabels: true
            ) { EmptyView() }
            if !store.error.isEmpty {
                Label(store.error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(muted)
            } else if let latest = store.latest, !store.online {
                Label("数据未更新 · 最后接收 \(formatTime(latest.receivedAt))", systemImage: "clock")
                    .font(.caption).foregroundStyle(muted)
            }
            DashboardCard {
                VStack(spacing: 9) {
                    segmented(["温度", "湿度"], selected: showTemperature ? 0 : 1) { showTemperature = $0 == 0 }
                    segmented(Period.allCases.map(\.rawValue), selected: Period.allCases.firstIndex(of: store.period) ?? 0) {
                        store.period = Period.allCases[$0]
                    }
                    chart
                }.padding(12)
            }
            DashboardCard {
                VStack(alignment: .leading, spacing: 2) {
                    Text("历史记录").font(.headline).foregroundStyle(ink)
                        .padding(.horizontal, 14).padding(.top, 12)
                    history
                }
            }
        }
        .navigationTitle(fromHome ? "" : "记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(fromHome ? .visible : .hidden, for: .navigationBar)
        .refreshable { await store.refresh() }
        .onChange(of: store.period) { _ in visibleHistoryCount = 3 }
    }
    private func segmented(_ labels: [String], selected: Int, select: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(labels.indices, id: \.self) { index in
                Button { select(index) } label: {
                    Text(labels[index]).font(.subheadline.weight(.medium))
                        .foregroundStyle(index == selected ? Color.white : ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(index == selected ? blue : Color.clear, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(index == selected ? .isSelected : [])
            }
        }.padding(3).background(canvas, in: Capsule())
    }
    private var chartRange: ClosedRange<Double> {
        let readings = store.points.map { showTemperature ? $0.temperature : $0.humidity }
        let lowest = readings.min() ?? 0
        let highest = readings.max() ?? 0
        let margin = max(showTemperature ? 1 : 2, (highest - lowest) * 0.16)
        return (lowest - margin)...(highest + margin)
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showTemperature ? "°C" : "%").font(.caption).foregroundStyle(.secondary)
            if store.points.isEmpty {
                VStack(spacing: 8) {
                    if store.loading { ProgressView() }
                    else { Image(systemName: "chart.xyaxis.line"); Text("该时间范围暂无数据") }
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 180)
            } else {
                let yRange = chartRange
                Chart(store.points) { point in
                    let number = showTemperature ? point.temperature : point.humidity
                    AreaMark(x: .value("时间", point.time), yStart: .value("下界", yRange.lowerBound),
                             yEnd: .value("数值", number))
                        .foregroundStyle(LinearGradient(colors: [blue.opacity(0.24), blue.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("时间", point.time), y: .value("数值", number))
                        .foregroundStyle(blue).interpolationMethod(.monotone)
                    if point.id == store.points.last?.id {
                        PointMark(x: .value("时间", point.time), y: .value("数值", number))
                            .foregroundStyle(blue).symbolSize(28)
                            .annotation(position: .top, spacing: 4) {
                                Text(value(number, unit: showTemperature ? "°C" : "%", decimals: 0))
                                    .font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(4).background(blue, in: RoundedRectangle(cornerRadius: 5))
                            }
                    }
                }
                .chartXScale(domain: store.period.range.0...store.period.range.1)
                .chartYScale(domain: yRange)
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
        LazyVStack(spacing: 0) {
            if store.history.isEmpty {
                Text(store.loading ? "正在加载…" : "暂无历史记录").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(20)
            } else {
                let visible = store.history.prefix(visibleHistoryCount)
                ForEach(visible) { reading in
                    HStack(spacing: 8) {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatTime(reading.time, store.period == .day ? "HH:mm" : "MM月dd日 HH:mm")).lineLimit(1)
                            if reading.measuredAt == nil { Text("接收时间").font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 4)
                        Text(value(reading.temperature, unit: "°C", decimals: 1)).monospacedDigit()
                        Text(value(reading.humidity, unit: "%", decimals: 0)).monospacedDigit()
                    }.font(.subheadline).foregroundStyle(ink).padding(.horizontal, 14).padding(.vertical, 9)
                    if reading.id != visible.last?.id { Divider().padding(.leading, 38) }
                }
                if visibleHistoryCount < store.history.count || store.nextBeforeId > 0 {
                    Button {
                        Task {
                            if visibleHistoryCount >= store.history.count { await store.loadMore() }
                            visibleHistoryCount += 12
                        }
                    } label: {
                        if store.loadingMore { ProgressView() } else { Text("加载更多") }
                    }.font(.subheadline).foregroundStyle(blue).padding(11).disabled(store.loadingMore || store.loading)
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SensorStore
    @EnvironmentObject private var control: ControlStore
    @State private var reconnecting = false

    var body: some View {
        DashboardPage {
            DashboardHeading(title: "设置")
                .padding(.bottom, 8)
            Label("设备连接", systemImage: "server.rack").font(.headline).foregroundStyle(ink)
            DashboardCard {
                VStack(alignment: .leading, spacing: 0) {
                    row("温湿度采集", symbol: "thermometer.medium", detail: sensorStatus)
                    separator
                    row("ESP32 控制板", symbol: "cpu", detail: boardStatus,
                        detailColor: control.online ? onlineGreen : muted)
                    separator
                    row("采集设备编号", symbol: "number", detail: store.deviceId.isEmpty ? "—" : store.deviceId)
                    separator
                    Button {
                        Task { await reconnect() }
                    } label: {
                        row(reconnecting ? "正在重新连接…" : "重新连接", symbol: "arrow.clockwise", tint: blue)
                    }.buttonStyle(.plain).disabled(reconnecting || control.pendingTarget != nil)
                    Text("温湿度约每 30 秒刷新")
                        .font(.caption).foregroundStyle(muted).padding(.horizontal, 14).padding(.bottom, 11)
                }
            }
            if !store.error.isEmpty { Text(store.error).font(.footnote).foregroundStyle(muted) }
            if let message = control.connectionMessage { Text(message).font(.footnote).foregroundStyle(muted) }
            Label("账号", systemImage: "person").font(.headline).foregroundStyle(ink).padding(.top, 8)
            DashboardCard {
                VStack(spacing: 0) {
                    row("控制权限", symbol: "person", detail: permission)
                    separator
                    Button(role: .destructive) {
                        Task { await store.logout() }
                    } label: {
                        row("退出登录", symbol: "rectangle.portrait.and.arrow.right", tint: .red)
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("设置")
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sensorStatus: String {
        if !store.isConfigured { return "配置不可用" }
        if !store.error.isEmpty { return "连接异常" }
        if store.online { return "数据正常" }
        return store.latest == nil ? "等待数据" : "数据未更新"
    }

    private var boardStatus: String {
        if control.online { return "● 在线" }
        return control.snapshot == nil ? "未连接" : "离线"
    }

    private var permission: String {
        guard let allowed = control.snapshot?.canControl else { return "未知" }
        return allowed ? "操作员" : "仅查看"
    }

    private var separator: some View { Divider().padding(.leading, 57) }

    private func row(_ title: String, symbol: String, detail: String? = nil, tint: Color = ink,
                     detailColor: Color = muted) -> some View {
        HStack(spacing: 11) {
            DeviceIcon(symbol: symbol, foreground: tint == ink ? blue : tint, size: 35)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            Spacer(minLength: 4)
            if let detail { Text(detail).font(.footnote).foregroundStyle(detailColor).multilineTextAlignment(.trailing) }
        }.padding(.vertical, 8).padding(.horizontal, 12).contentShape(Rectangle())
    }

    private func reconnect() async {
        guard !reconnecting else { return }
        reconnecting = true
        defer { reconnecting = false }
        async let readings: Void = store.refresh()
        async let controls: Void = control.refresh(using: store)
        _ = await (readings, controls)
    }
}
