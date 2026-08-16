import SwiftUI
import Charts

// MARK: - 統計タブ

struct StatsView: View {
    @ObservedObject var manager: CalendarManager
    // 親（ContentView）で保持する状態 = タブ切替後も値が残る
    @Binding var statsYear: Int
    @Binding var rangeStart: Int
    @Binding var rangeEnd: Int
    @Binding var monthlyStats: [MonthlyStat]
    // 一時的な表示状態はタブローカル
    @State private var loading = false
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if manager.isAuthorized, !manager.settings.selectedCalendarIDs.isEmpty {
                content
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(manager.settings.selectedCalendarIDs.isEmpty
                         ? "「設定」タブでバイトのカレンダリーを選択してください"
                         : "カレンダーへのアクセス許可が必要です")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { scheduleLoad() }
        .onChange(of: statsYear) { scheduleLoad() }
    }

    /// タブ再挿入トランザクション直後の状態書き換えを避けつつ、
    /// 連続呼び出しは直前のロードをキャンセルしてデバウンスする
    private func scheduleLoad() {
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await load(year: statsYear)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // ツールバー
            HStack(spacing: 8) {
                Picker("年", selection: $statsYear) {
                    ForEach(manager.yearOptions, id: \.self) { Text("\($0)年") }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Spacer()

                // 構造が変わらないようopacityで切替
                ProgressView()
                    .controlSize(.small)
                    .opacity(loading ? 1 : 0)

                Button {
                    scheduleLoad()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
                .help("再読み込み")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 常にScrollViewを表示（構造の入れ替えをしない）
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chartSection
                    yearTotalSection
                    periodSection
                }
                .padding(12)
            }
            .overlay {
                if loading && monthlyStats.isEmpty {
                    ProgressView("統計を計算中…")
                }
            }
        }
    }

    // MARK: グラフ

    private var chartSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if monthlyStats.isEmpty {
                    Text(loading ? " " : "\(statsYear)年のデータがありません")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    Chart(monthlyStats) { stat in
                        BarMark(
                            x: .value("月", stat.month),
                            y: .value("支給額", stat.summary.total)
                        )
                        .foregroundStyle(Color.pink.gradient)
                        .annotation(position: .top) {
                            if stat.summary.total > 0 {
                                Text(moneyText(stat.summary.total))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: Array(1...12)) { value in
                            AxisValueLabel {
                                if let m = value.as(Int.self) {
                                    Text("\(m)")
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("¥\(Int(v / 1000))k")
                                }
                            }
                        }
                    }
                    .frame(height: 200)
                    Text("月別の合計支給額（基本給＋時間帯別給与＋交通費）")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(4)
        } label: {
            Label("\(statsYear)年 月別給与グラフ", systemImage: "chart.bar.fill")
                .font(.headline)
        }
    }

    // MARK: 年間合計

    private var yearTotal: PayrollSummary {
        monthlyStats.reduce(PayrollSummary.empty) { $0 + $1.summary }
    }

    private var yearTotalSection: some View {
        GroupBox {
            HStack(spacing: 24) {
                bigStat("年間合計支給額", moneyText(yearTotal.total), color: .pink)
                Divider().frame(height: 40)
                bigStat("総実働時間", yearTotal.workedMinutes.hoursAndMinutesText, color: .primary)
                bigStat("総出勤日数", "\(yearTotal.workDays)日", color: .primary)
                bigStat("時間帯別給与", moneyText(yearTotal.nightPay), color: .indigo)
                bigStat("交通費", moneyText(yearTotal.transport), color: .secondary)
                Spacer()
            }
            .padding(8)
        } label: {
            Label("\(statsYear)年 年間合計", systemImage: "calendar.badge.clock")
                .font(.headline)
        }
    }

    // MARK: 期間指定統計

    private var periodStats: [MonthlyStat] {
        let lo = min(rangeStart, rangeEnd)
        let hi = max(rangeStart, rangeEnd)
        return monthlyStats.filter { $0.month >= lo && $0.month <= hi }
    }

    private var periodSummary: PayrollSummary {
        periodStats.reduce(PayrollSummary.empty) { $0 + $1.summary }
    }

    /// 期間内の平均週勤務日数（月の日数から週数を算出）
    private var avgWeeklyWorkDays: Double {
        guard !periodStats.isEmpty else { return 0 }
        var totalDays = 0
        var totalWeeks = 0.0
        let cal = Calendar.current
        for stat in periodStats {
            let (start, _) = CalendarManager.monthRange(year: stat.year, month: stat.month)
            let days = cal.range(of: .day, in: .month, for: start)?.count ?? 30
            totalDays += stat.summary.workDays
            totalWeeks += Double(days) / 7.0
        }
        guard totalWeeks > 0 else { return 0 }
        return Double(totalDays) / totalWeeks
    }

    private var periodSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("開始月", selection: $rangeStart) {
                        ForEach(1...12, id: \.self) { Text("\($0)月") }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Text("〜")

                    Picker("終了月", selection: $rangeEnd) {
                        ForEach(1...12, id: \.self) { Text("\($0)月") }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Text("（\(statsYear)年\(min(rangeStart, rangeEnd))〜\(max(rangeStart, rangeEnd))月・\(periodStats.count)ヶ月）")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                HStack(spacing: 24) {
                    bigStat("月平均給与", moneyText(monthlyAverage), color: .pink)
                    Divider().frame(height: 40)
                    bigStat("月平均実働", avgWorkMinutes.hoursAndMinutesText, color: .primary)
                    bigStat("平均週勤務", String(format: "%.1f 日/週", avgWeeklyWorkDays), color: .primary)
                    bigStat("月平均出勤", String(format: "%.1f 日", avgWorkDays), color: .secondary)
                    Spacer()
                }
            }
            .padding(8)
        } label: {
            Label("期間指定の統計", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    private var monthlyAverage: Double {
        guard !periodStats.isEmpty else { return 0 }
        return periodSummary.total / Double(periodStats.count)
    }

    private var avgWorkMinutes: Int {
        guard !periodStats.isEmpty else { return 0 }
        return periodSummary.workedMinutes / periodStats.count
    }

    private var avgWorkDays: Double {
        guard !periodStats.isEmpty else { return 0 }
        return Double(periodSummary.workDays) / Double(periodStats.count)
    }

    // MARK: 共通

    private func bigStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private func load(year: Int) async {
        loading = true
        let result = await manager.loadYearlyStats(year: year)
        // 値が実際に変わったときだけ状態を書き換える（再描画の連鎖を防ぐ）
        if result != monthlyStats {
            monthlyStats = result
        }
        loading = false
    }
}
