import Foundation
import Algorithms

/// Role: analytics ledger. Windowed weekly aggregates come from swift-algorithms.
enum AnalyticsSelector {
    static func ledger(
        from state: AppState,
        days: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsLedger {
        let today = DayKey.make(now, calendar: calendar)
        let start = DayKey.shift(today, days: -(days - 1), calendar: calendar)
        var points: [DayPoint] = []
        var cursor = start
        while cursor <= today {
            let rows = state.readings.filter { $0.dayKey == cursor && $0.isEaten }
            points.append(
                DayPoint(
                    dayKey: cursor,
                    kcal: rows.reduce(0) { $0 + GaugeMaths.energy(of: $1) },
                    protein: GaugeMaths.sumMacro(rows.map { GaugeMaths.protein(of: $0) }) ?? 0,
                    carbs: GaugeMaths.sumMacro(rows.map { GaugeMaths.carbs(of: $0) }) ?? 0,
                    fat: GaugeMaths.sumMacro(rows.map { GaugeMaths.fat(of: $0) }) ?? 0
                )
            )
            cursor = DayKey.shift(cursor, days: 1, calendar: calendar)
            if points.count > days { break }
        }

        let weekly: [Double]
        if points.count >= 7 {
            let slices = Array(points.windows(ofCount: 7))
            weekly = slices.map { window -> Double in
                let total = window.reduce(0.0) { partial, point in
                    partial + point.kcal
                }
                return total / Double(window.count)
            }
        } else {
            weekly = []
        }

        var weekdaySums = Array(repeating: 0.0, count: 7)
        var weekdayCounts = Array(repeating: 0, count: 7)
        for point in points {
            guard let weekday = DayKey.weekdayIndex(point.dayKey, calendar: calendar) else { continue }
            let index = weekday - 1
            guard (0..<7).contains(index) else { continue }
            weekdaySums[index] += point.kcal
            weekdayCounts[index] += 1
        }
        let weekdayAverages = zip(weekdaySums, weekdayCounts).map { sum, count in
            count == 0 ? 0 : sum / Double(count)
        }

        let active = points.filter { $0.kcal > 0 }
        let target = state.calibration.kcal
        let adherent = active.filter { point in
            guard target > 0 else { return false }
            let ratio = point.kcal / target
            return ratio >= 0.8 && ratio <= 1.1
        }
        let adherence = active.isEmpty ? 0 : (Double(adherent.count) / Double(active.count)) * 100

        return AnalyticsLedger(
            windowDays: days,
            daily: points,
            weeklyWindows: weekly,
            weekdayAverages: weekdayAverages,
            proteinTotal: points.map(\.protein).reduce(0, +),
            carbsTotal: points.map(\.carbs).reduce(0, +),
            fatTotal: points.map(\.fat).reduce(0, +),
            adherencePercent: adherence,
            bestDay: active.max(by: { $0.kcal < $1.kcal }),
            worstDay: active.min(by: { $0.kcal < $1.kcal })
        )
    }
}
