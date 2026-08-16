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
        .frame(minWidth: 560, minHeight: 380)
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
            HStack(spacing: 8) {
                Picker("年", selection: Binding(
                    get: { manager.year },
                    set: { manager.setMonth($0, manager.month) }
                )) {
                    ForEach(manager.yearOptions, id: \.self) { Text("\($0)年") }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                HStack(spacing: 2) {
                    Button {
                        moveMonth(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.borderless)
                    .help("前の月")

                    Picker("月", selection: Binding(
                        get: { manager.month },
                        set: { manager.setMonth(manager.year, $0) }
                    )) {
                        ForEach(1...12, id: \.self) { Text("\($0)月") }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Button {
                        moveMonth(1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.borderless)
                    .help("次の月")
                }
                .fixedSize()

                Spacer()

                Button {
                    manager.refetch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("再読み込み")

                Button {
                    manager.exportCSV()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(manager.rows.isEmpty)
                .help("CSV書き出し")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

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

    private func moveMonth(_ delta: Int) {
        var y = manager.year
        var m = manager.month + delta
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        manager.setMonth(y, m)
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
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("バイト").font(.caption2).foregroundStyle(.secondary)
                Text("日付").font(.caption2).foregroundStyle(.secondary).frame(width: 38 + 26 + 8, alignment: .leading)
                Text("時間").font(.caption2).foregroundStyle(.secondary).frame(width: 108, alignment: .leading)
                Text("実働").font(.caption2).foregroundStyle(.secondary).frame(width: 88, alignment: .leading)
                if manager.rows.contains(where: { $0.nightMinutes > 0 }) {
                    Text("時間帯").font(.caption2).foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
                }
                Spacer(minLength: 4)
                Text("支給額").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            Divider()
            List(manager.rows) { row in
                ShiftRowView(row: row)
            }
            .listStyle(.plain)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 20) {
            stat("出勤", "\(manager.summary.workDays)日")
            stat("実働", manager.summary.workedMinutes.hoursAndMinutesText)
            stat("基本給", moneyText(manager.summary.basePay))
            if manager.summary.nightPay > 0 {
                stat("時間帯別", moneyText(manager.summary.nightPay))
            }
            stat("交通費", moneyText(manager.summary.transport))
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("合計").font(.caption).foregroundStyle(.secondary)
                Text(moneyText(manager.summary.total))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.pink)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
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

// MARK: - シフト行（コンパクト表示）

struct ShiftRowView: View {
    let row: ShiftRow
    static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(row.calendarColor))
                    .frame(width: 6, height: 6)
                Text(row.calendarTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(Self.df.string(from: row.start, format: "M/d"))
                .monospacedDigit()
                .frame(width: 38, alignment: .leading)

            Text(Self.df.string(from: row.start, format: "EEE"))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            Text(timeText)
                .monospacedDigit()
                .frame(width: 108, alignment: .leading)

            Text(row.workedMinutes.hoursAndMinutesText)
                .monospacedDigit()
                .frame(width: 88, alignment: .leading)

            if row.nightMinutes > 0 {
                Text("🌙\(row.nightMinutes / 60):\(String(format: "%02d", row.nightMinutes % 60))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.indigo)
                    .frame(width: 54, alignment: .leading)
                    .help("時間帯別時給の適用時間")
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 0) {
                Text(moneyText(row.totalPay))
                    .bold()
                    .monospacedDigit()
                if row.nightPay > 0 {
                    Text("時間帯別 \(moneyText(row.nightPay))")
                        .font(.caption2)
                        .foregroundStyle(.indigo)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 1)
        .help(helpText)
    }

    private var timeText: String {
        let s = Self.df.string(from: row.start, format: "HH:mm")
        let e = Self.df.string(from: row.end, format: "HH:mm")
        return "\(s)〜\(e)"
    }

    private var helpText: String {
        var lines = ["\(row.calendarTitle)「\(row.title)」",
                     "休憩 \(row.breakMinutes)分 | 実働 \(row.workedMinutes.hoursAndMinutesText)"]
        if row.nightMinutes > 0 {
            lines.append("時間帯別 \(row.nightMinutes / 60)時間\(String(format: "%02d", row.nightMinutes % 60))分 = \(moneyText(row.nightPay))")
            lines.append("通常分 = \(moneyText(row.basePay))")
        }
        return lines.joined(separator: "\n")
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
                        Text("カレンダーを選択すると、そのバイトごとの給与条件を設定できます")
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

    /// カレンダー一覧を5項目ごとに列分割したチャンク
    private var calendarColumns: [[EKCalendar]] {
        let perColumn = 5
        let calendars = manager.allCalendars
        return stride(from: 0, to: calendars.count, by: perColumn).map {
            Array(calendars[$0..<min($0 + perColumn, calendars.count)])
        }
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
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(calendarColumns.indices, id: \.self) { col in
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(calendarColumns[col], id: \.calendarIdentifier) { cal in
                                    Toggle(isOn: calendarBinding(cal.calendarIdentifier)) {
                                        HStack(spacing: 8) {
                                            Circle().fill(Color(cal.color)).frame(width: 10, height: 10)
                                            Text(cal.title)
                                        }
                                    }
                                }
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

    // MARK: 時間帯別時給エディタ

    private func bandEditor(job: Binding<JobSetting>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("開始").font(.caption).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                Color.clear.frame(width: 12)
                Text("終了").font(.caption).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                Color.clear.frame(width: 12)
                Text("時給").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            }
            .help("終了が開始時刻以下なら翌日跨ぎとして計算します（例: 22:00〜5:00）")
            ForEach(job.wageBands) { $band in
                HStack(spacing: 10) {
                    DatePicker("", selection: startTimeBinding($band), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 84)
                    Text("〜")
                    DatePicker("", selection: endTimeBinding($band), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 84)
                    Text("は")
                    TextField("1375", value: $band.wage, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Text("円")
                    Button {
                        job.wrappedValue.wageBands.removeAll { $0.id == band.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                job.wrappedValue.wageBands.append(
                    WageBand(wage: Int((Double(job.wrappedValue.wage) * 1.25).rounded()))
                )
            } label: {
                Label("時間帯を追加", systemImage: "plus.circle")
            }
        }
        .padding(4)
    }

    private func startTimeBinding(_ band: Binding<WageBand>) -> Binding<Date> {
        Binding(
            get: { timeDate(band.wrappedValue.startMinutes) },
            set: { d in
                let newStart = dateToMinutes(d)
                band.wrappedValue.startMinutes = newStart
                var e = band.wrappedValue.endMinutes % 1440
                if e <= newStart { e += 1440 }
                band.wrappedValue.endMinutes = e
            }
        )
    }

    private func endTimeBinding(_ band: Binding<WageBand>) -> Binding<Date> {
        Binding(
            get: { timeDate(band.wrappedValue.endMinutes) },
            set: { d in
                var m = dateToMinutes(d)
                if m <= band.wrappedValue.startMinutes { m += 1440 }
                band.wrappedValue.endMinutes = m
            }
        )
    }

    private func timeDate(_ minutes: Int) -> Date {
        let m = ((minutes % 1440) + 1440) % 1440
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }

    private func dateToMinutes(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
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
            VStack(alignment: .leading, spacing: 12) {
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
                        settingLabel("時間帯別の時給")
                        Toggle("", isOn: jobSetting(cal.calendarIdentifier).nightPremiumEnabled)
                            .labelsHidden()
                    }
                }
                if jobSetting(cal.calendarIdentifier).nightPremiumEnabled.wrappedValue {
                    Divider()
                    bandEditor(job: jobSetting(cal.calendarIdentifier))
                }
            }
            .frame(width: 410, alignment: .leading)
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
