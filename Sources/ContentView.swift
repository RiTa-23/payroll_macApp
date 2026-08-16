import SwiftUI
import EventKit

struct ContentView: View {
    @StateObject private var manager = CalendarManager()
    @State private var tab: Int = 0

    var body: some View {
        TabView(selection: $tab) {
            PayrollView(manager: manager, tab: $tab)
                .tabItem { Label("給与計算", systemImage: "yensign.circle.fill") }
                .tag(0)
            SettingsView(manager: manager)
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(1)
        }
        .frame(minWidth: 1020, minHeight: 660)
        .task { await manager.bootstrap() }
    }
}

// MARK: - 給与計算タブ

struct PayrollView: View {
    @ObservedObject var manager: CalendarManager
    @Binding var tab: Int

    var body: some View {
        Group {
            switch manager.authorization {
            case .fullAccess:
                content
            case .notDetermined:
                ProgressView("カレンダーへのアクセス許可を確認中…")
            default:
                deniedView
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("年", selection: Binding(
                    get: { manager.year },
                    set: { manager.setMonth($0, manager.month) }
                )) {
                    ForEach(manager.yearOptions, id: \.self) { Text("\($0)年") }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Picker("月", selection: Binding(
                    get: { manager.month },
                    set: { manager.setMonth(manager.year, $0) }
                )) {
                    ForEach(1...12, id: \.self) { Text("\($0)月") }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Spacer()

                Button {
                    manager.refetch()
                } label: {
                    Label("再読み込み", systemImage: "arrow.clockwise")
                }

                Button {
                    manager.exportCSV()
                } label: {
                    Label("CSV書き出し", systemImage: "square.and.arrow.down")
                }
                .disabled(manager.rows.isEmpty)
            }
            .padding(12)

            Divider()

            if manager.settings.selectedCalendarIDs.isEmpty {
                emptyState
            } else if manager.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("\(manager.year)年\(manager.month)月のシフトはありません")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                shiftList
            }

            Divider()
            summaryBar
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("まず「設定」タブでバイトのカレンダーを選択してください")
                .foregroundStyle(.secondary)
            Button("設定を開く") { tab = 1 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shiftList: some View {
        List(manager.rows) { row in
            ShiftRowView(row: row)
        }
        .listStyle(.inset)
    }

    private var summaryBar: some View {
        HStack(spacing: 28) {
            stat("出勤日数", "\(manager.summary.workDays)日")
            stat("総実働時間", manager.summary.workedMinutes.hoursAndMinutesText)
            stat("基本給", moneyText(manager.summary.basePay))
            if manager.summary.nightPremium > 0 {
                stat("深夜割増", moneyText(manager.summary.nightPremium))
            }
            stat("交通費", moneyText(manager.summary.transport))
            Divider().frame(height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("合計支給額").font(.caption).foregroundStyle(.secondary)
                Text(moneyText(manager.summary.total))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.pink)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
    }

    private var deniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("カレンダーへのアクセスが許可されていません")
                .font(.title3.weight(.semibold))
            Text("システム設定の「プライバシーとセキュリティ」＞「カレンダー」で\nこのアプリに許可を与えてください。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("システム設定を開く") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - シフト行

struct ShiftRowView: View {
    let row: ShiftRow
    static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(row.calendarColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                Text(row.calendarTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 190, alignment: .leading)

            dateText.frame(width: 100, alignment: .leading)

            timeText.frame(width: 115, alignment: .leading)

            Text("休憩 \(row.breakMinutes)分")
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            if row.nightMinutes > 0 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.workedMinutes.hoursAndMinutesText)
                    Text("深夜 \(row.nightMinutes / 60)時間\(String(format: "%02d", row.nightMinutes % 60))分")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
                .frame(width: 120, alignment: .leading)
            } else {
                Text(row.workedMinutes.hoursAndMinutesText)
                    .frame(width: 120, alignment: .leading)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(moneyText(row.totalPay)).bold().monospacedDigit()
                if row.nightPremium > 0 {
                    Text("割増 +\(moneyText(row.nightPremium))")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var dateText: some View {
        Text(Self.df.string(from: row.start, format: "M/d (EEE)"))
    }

    private var timeText: some View {
        let s = Self.df.string(from: row.start, format: "HH:mm")
        let e = Self.df.string(from: row.end, format: "HH:mm")
        return Text("\(s)〜\(e)")
    }
}

extension DateFormatter {
    func string(from date: Date, format: String) -> String {
        let old = self.dateFormat
        self.dateFormat = format
        defer { self.dateFormat = old }
        return self.string(from: date)
    }
}

// MARK: - 設定タブ

struct SettingsView: View {
    @ObservedObject var manager: CalendarManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                calendarSection
                if enabledCalendars.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text("カレンダリーを選択すると、そのバイトごとの給与条件を設定できます")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                }
                ForEach(enabledCalendars, id: \.calendarIdentifier) { cal in
                    jobSection(cal)
                }
                Text("※ 実働時間はカレンダーイベントの開始〜終了から休憩時間を差し引いて計算します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var enabledCalendars: [EKCalendar] {
        manager.allCalendars
            .filter { manager.settings.selectedCalendarIDs.contains($0.calendarIdentifier) }
            .sorted { $0.title < $1.title }
    }

    private var calendarSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if manager.allCalendars.isEmpty {
                    Text(manager.isAuthorized
                         ? "カレンダーが見つかりませんでした"
                         : "カレンダーへのアクセス許可を待っています…")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(manager.allCalendars, id: \.calendarIdentifier) { cal in
                        Toggle(isOn: calendarBinding(cal.calendarIdentifier)) {
                            HStack(spacing: 8) {
                                Circle().fill(Color(cal.color)).frame(width: 10, height: 10)
                                Text(cal.title)
                            }
                        }
                    }
                }
            }
            .padding(4)
        } label: {
            Label("バイトのカレンダー（複数選択可）", systemImage: "calendar.badge.checkmark")
                .font(.headline)
        }
    }

    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { manager.settings.selectedCalendarIDs.contains(id) },
            set: { on in
                if on {
                    manager.settings.selectedCalendarIDs.insert(id)
                    if manager.settings.jobs[id] == nil {
                        manager.settings.jobs[id] = JobSetting()
                    }
                } else {
                    manager.settings.selectedCalendarIDs.remove(id)
                }
            }
        )
    }

    private func jobSetting(_ id: String) -> Binding<JobSetting> {
        Binding(
            get: { manager.settings.jobs[id] ?? JobSetting() },
            set: { manager.settings.jobs[id] = $0 }
        )
    }

    private func jobSection(_ cal: EKCalendar) -> some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    settingLabel("時給")
                    TextField("1100", value: jobSetting(cal.calendarIdentifier).wage, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("円").foregroundStyle(.secondary)
                }
                GridRow {
                    settingLabel("休憩時間（1シフトあたり）")
                    TextField("60", value: jobSetting(cal.calendarIdentifier).breakMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("分").foregroundStyle(.secondary)
                }
                GridRow {
                    settingLabel("交通費（1出勤日あたり）")
                    TextField("700", value: jobSetting(cal.calendarIdentifier).transportPerDay, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("円").foregroundStyle(.secondary)
                }
                GridRow {
                    settingLabel("深夜割増（22:00〜翌5:00）")
                    Toggle("", isOn: jobSetting(cal.calendarIdentifier).nightPremiumEnabled)
                        .labelsHidden()
                    Picker("", selection: jobSetting(cal.calendarIdentifier).nightPremiumRate) {
                        Text("25%").tag(0.25)
                        Text("30%").tag(0.30)
                        Text("35%").tag(0.35)
                        Text("50%").tag(0.50)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .disabled(!jobSetting(cal.calendarIdentifier).nightPremiumEnabled.wrappedValue)
                }
            }
            .padding(4)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(cal.color)).frame(width: 10, height: 10)
                Text(cal.title)
            }
            .font(.headline)
        }
    }

    private func settingLabel(_ s: String) -> some View {
        Text(s).frame(width: 220, alignment: .leading)
    }
}
