import Foundation

/// Role: canonical day identity. ISO8601 date-only strings, derived from Calendar.startOfDay.
enum DayKey {
    static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let year = parts.year ?? 1970
        let month = parts.month ?? 1
        let dayValue = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, dayValue)
    }

    static func today(calendar: Calendar = .current, now: Date = Date()) -> String {
        make(now, calendar: calendar)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let bits = key.split(separator: "-")
        guard bits.count == 3,
              let year = Int(bits[0]),
              let month = Int(bits[1]),
              let day = Int(bits[2])
        else { return nil }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
    }

    static func shift(_ key: String, days: Int, calendar: Calendar = .current) -> String {
        guard let base = date(from: key, calendar: calendar),
              let moved = calendar.date(byAdding: .day, value: days, to: base)
        else { return key }
        return make(moved, calendar: calendar)
    }

    static func weekdayIndex(_ key: String, calendar: Calendar = .current) -> Int? {
        guard let date = date(from: key, calendar: calendar) else { return nil }
        return calendar.component(.weekday, from: date)
    }
}
