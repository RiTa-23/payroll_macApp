import Foundation
import EventKit
import AppKit
import UniformTypeIdentifiers

// MARK: - 設定

/// バイト（カレンダリー）ごとの給与条件
struct JobSetting: Codable, Equatable {
    var wage: Int = 1100
    var breakMinutes: Int = 60
    var transportPerDay: Int = 700
    var nightPremiumEnabled: Bool = true
    var nightPremiumRate: Double = 0.25
}

struct PayrollSettings: Codable, Equatable {
    /// キーはカレンダーID
    var jobs: [String: JobSetting] = [:]
    var selectedCalendarIDs: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case jobs, selectedCalendarIDs
        // 旧バージョン（全カレンダー共通）からの移行用
        case wage, breakMinutes, transportPerDay
    }

    init() {}

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jobs, forKey: .jobs)
        try c.encode(selectedCalendarIDs, forKey: .selectedCalendarIDs)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobs = try c.decodeIfPresent([String: JobSetting].self, forKey: .jobs) ?? [:]
        selectedCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs) ?? []
        // 旧形式（共通の給与条件）を各カレンダリーに展開して移行
        if jobs.isEmpty, !selectedCalendarIDs.isEmpty {
            let legacy = JobSetting(
                wage: try c.decodeIfPresent(Int.self, forKey: .wage) ?? 1100,
                breakMinutes: try c.decodeIfPresent(Int.self, forKey: .breakMinutes) ?? 60,
                transportPerDay: try c.decodeIfPresent(Int.self, forKey: .transportPerDay) ?? 700
            )
            for id in selectedCalendarIDs {
                jobs[id] = legacy
            }
        }
    }
}

// MARK: - 計算結果モデル

struct ShiftRow: Identifiable {
    let id: String
    let title: String
    let calendarID: String
    let calendarTitle: String
    let calendarColor: NSColor
    let start: Date
    let end: Date
    let breakMinutes: Int
    let workedMinutes: Int
    let nightMinutes: Int
    let basePay: Double
    let nightPremium: Double

    var totalPay: Double { basePay + nightPremium }
}

struct PayrollSummary: Equatable {
    var workDays = 0
    var workedMinutes = 0
    var nightMinutes = 0
    var basePay = 0.0
    var nightPremium = 0.0
    var transport = 0.0

    var total: Double { basePay + nightPremium + transport }
    static let empty = PayrollSummary()
}

// MARK: - カレンダー管理

@MainActor
final class CalendarManager: ObservableObject {
    let store = EKEventStore()

    @Published var authorization: EKAuthorizationStatus = .notDetermined
    @Published var allCalendars: [EKCalendar] = []
    @Published var rows: [ShiftRow] = []
    @Published var summary = PayrollSummary.empty

    @Published private(set) var year: Int
    @Published private(set) var month: Int
    @Published var settings: PayrollSettings {
        didSet { persist(); refetch() }
    }

    private let defaults = UserDefaults.standard
    private static let settingsKey = "payroll.settings"

    var yearOptions: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((y - 3)...(y + 1))
    }

    var isAuthorized: Bool {
        authorization == .fullAccess
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let s = try? JSONDecoder().decode(PayrollSettings.self, from: data) {
            settings = s
        } else {
            settings = PayrollSettings()
        }
        let now = Date()
        year = Calendar.current.component(.year, from: now)
        month = Calendar.current.component(.month, from: now)
        authorization = EKEventStore.authorizationStatus(for: .event)
    }

    func bootstrap() async {
        if authorization == .notDetermined {
            await requestAccess()
        }
        if isAuthorized {
            allCalendars = store.calendars(for: .event)
            refetch()
        }
    }

    private func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorization = granted ? .fullAccess : .denied
    }

    func setMonth(_ y: Int, _ m: Int) {
        year = y
        month = m
        refetch()
    }

    func refetch() {
        guard isAuthorized, !settings.selectedCalendarIDs.isEmpty else {
            rows = []
            summary = .empty
            return
        }
        let calendars = allCalendars.filter { settings.selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            rows = []
            summary = .empty
            return
        }
        let (rangeStart, rangeEnd) = Self.monthRange(year: year, month: month)
        let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: calendars)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > $0.startDate }
        rows = Self.computeRows(events: events, settings: settings)
        summary = Self.computeSummary(rows: rows, settings: settings)
    }

    // MARK: 給与計算

    static func computeRows(events: [EKEvent], settings: PayrollSettings) -> [ShiftRow] {
        events.map { event in
            let job = settings.jobs[event.calendar.calendarIdentifier] ?? JobSetting()
            let start = event.startDate ?? Date()
            let end = max(event.endDate ?? start, start)
            var worked = Int(end.timeIntervalSince(start) / 60) - job.breakMinutes
            worked = max(0, worked)
            var night = nightMinutes(between: start, and: end)
            night = min(night, worked)

            let basePay = Double(job.wage) * Double(worked) / 60.0
            let premium = job.nightPremiumEnabled
                ? Double(job.wage) * Double(night) / 60.0 * job.nightPremiumRate
                : 0

            return ShiftRow(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "（無題）",
                calendarID: event.calendar.calendarIdentifier,
                calendarTitle: event.calendar.title,
                calendarColor: event.calendar.color,
                start: start,
                end: end,
                breakMinutes: job.breakMinutes,
                workedMinutes: worked,
                nightMinutes: night,
                basePay: basePay,
                nightPremium: premium
            )
        }
        .sorted { $0.start < $1.start }
    }

    static func computeSummary(rows: [ShiftRow], settings: PayrollSettings) -> PayrollSummary {
        var s = PayrollSummary()
        var days = Set<Date>()
        var transportDays = Set<String>() // "calendarID|day" の重複排除用
        for row in rows {
            let day = Calendar.current.startOfDay(for: row.start)
            days.insert(day)
            if transportDays.insert("\(row.calendarID)|\(day.timeIntervalSince1970)").inserted {
                s.transport += Double((settings.jobs[row.calendarID] ?? JobSetting()).transportPerDay)
            }
        }
        s.workDays = days.count
        s.workedMinutes = rows.reduce(0) { $0 + $1.workedMinutes }
        s.nightMinutes = rows.reduce(0) { $0 + $1.nightMinutes }
        s.basePay = rows.reduce(0) { $0 + $1.basePay }
        s.nightPremium = rows.reduce(0) { $0 + $1.nightPremium }
        return s
    }

    /// 深夜帯（22:00〜翌5:00）との重複分数
    static func nightMinutes(between start: Date, and end: Date, calendar cal: Calendar = .current) -> Int {
        guard end > start else { return 0 }
        var total = 0
        var day = cal.startOfDay(for: start).addingTimeInterval(-86400)
        let lastDay = cal.startOfDay(for: end)
        while day <= lastDay {
            let nightStart = day.addingTimeInterval(22 * 3600)
            let nightEnd = day.addingTimeInterval(29 * 3600)
            let overlap = min(end, nightEnd).timeIntervalSince(max(start, nightStart))
            if overlap > 0 { total += Int(overlap / 60) }
            day.addTimeInterval(86400)
        }
        return total
    }

    static func monthRange(year: Int, month: Int, calendar cal: Calendar = .current) -> (Date, Date) {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        let start = cal.date(from: comps)!
        var next = comps
        next.month = month + 1
        let end = cal.date(from: next)!
        return (start, end)
    }

    // MARK: 永続化

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
    }

    // MARK: CSV 書き出し

    func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "給与明細_\(year)_\(String(format: "%02d", month)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines: [String] = []
        lines.append("日付,曜日,カレンダー,タイトル,開始,終了,休憩(分),実働(分),深夜(分),基本給,深夜割増,合計")
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "M/d"
        let wf = DateFormatter()
        wf.locale = Locale(identifier: "ja_JP")
        wf.dateFormat = "EEE"
        let tf = DateFormatter()
        tf.locale = Locale(identifier: "ja_JP")
        tf.dateFormat = "HH:mm"
        let esc = { (s: String) in "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
        for row in rows {
            lines.append([
                df.string(from: row.start),
                wf.string(from: row.start),
                esc(row.calendarTitle), esc(row.title),
                "\(tf.string(from: row.start))-\(tf.string(from: row.end))",
                String(row.breakMinutes), String(row.workedMinutes), String(row.nightMinutes),
                String(format: "%.0f", row.basePay),
                String(format: "%.0f", row.nightPremium),
                String(format: "%.0f", row.totalPay)
            ].joined(separator: ","))
        }
        lines.append("")
        lines.append("出勤日数,\(summary.workDays)")
        lines.append("総実働(分),\(summary.workedMinutes)")
        lines.append(String(format: "基本給,%.0f", summary.basePay))
        lines.append(String(format: "深夜割増,%.0f", summary.nightPremium))
        lines.append(String(format: "交通費,%.0f", summary.transport))
        lines.append(String(format: "合計支給額,%.0f", summary.total))

        let csv = "\u{FEFF}" + lines.joined(separator: "\n")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - フォーマット支援

extension Int {
    var hoursAndMinutesText: String {
        String(format: "%d時間%02d分", self / 60, self % 60)
    }
}

func moneyText(_ value: Double) -> String {
    "¥" + value.formatted(.number.precision(.fractionLength(0...0)))
}
