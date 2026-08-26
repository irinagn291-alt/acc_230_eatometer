import Foundation
import OrderedCollections

/// Role: derived reading board. Day totals are computed, never stored.
enum ReadingSelector {
    static func board(from state: AppState, dayKey: String, eaten: Bool) -> DayBoard {
        let rows = state.readings.filter { $0.dayKey == dayKey && $0.isEaten == eaten }
        return assemble(rows)
    }

    static func horizon(from state: AppState, today: String, days: Int = 14) -> [GaugeReading] {
        let end = DayKey.shift(today, days: days + 1)
        return state.readings
            .filter { !$0.isEaten && $0.dayKey > today && $0.dayKey < end }
            .sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    static func assemble(_ rows: [GaugeReading]) -> DayBoard {
        var bySlot: [DialSlot: [GaugeReading]] = [:]
        var slotEnergy: [DialSlot: Double] = [:]
        for slot in DialSlot.allCases {
            bySlot[slot] = []
            slotEnergy[slot] = 0
        }
        for row in rows {
            bySlot[row.slot, default: []].append(row)
            slotEnergy[row.slot, default: 0] += GaugeMaths.energy(of: row)
        }
        for slot in DialSlot.allCases {
            bySlot[slot]?.sort { $0.createdAt < $1.createdAt }
        }
        return DayBoard(
            energy: rows.reduce(0) { $0 + GaugeMaths.energy(of: $1) },
            protein: GaugeMaths.sumMacro(rows.map { GaugeMaths.protein(of: $0) }),
            carbs: GaugeMaths.sumMacro(rows.map { GaugeMaths.carbs(of: $0) }),
            fat: GaugeMaths.sumMacro(rows.map { GaugeMaths.fat(of: $0) }),
            bySlot: bySlot,
            slotEnergy: slotEnergy
        )
    }

    static func remainingEnergy(board: DayBoard, calibration: DialCalibration) -> Double {
        calibration.kcal - board.energy
    }

    static func sectionOrder() -> OrderedSet<DialSlot> {
        OrderedSet(DialSlot.allCases)
    }
}
