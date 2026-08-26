import Foundation

/// Role: portion arithmetic. Round only at display; stored values keep full precision.
enum GaugeMaths {
    static let kilojoulePerKilocalorie = 4.184

    static func kilocaloriesPerHundredGrams(kcal100: Double?, energyKj100: Double?) -> Double? {
        if let kcal100 { return kcal100 }
        if let energyKj100 { return energyKj100 / kilojoulePerKilocalorie }
        return nil
    }

    static func scale(_ perHundred: Double?, grams: Double) -> Double? {
        guard let perHundred else { return nil }
        return perHundred * grams / 100
    }

    static func parseGrams(_ raw: String, locale: Locale = .current) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        if let number = formatter.number(from: trimmed) {
            return number.doubleValue
        }
        let fallback = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(fallback)
    }

    static func sumMacro(_ values: [Double?]) -> Double? {
        let known = values.compactMap { $0 }
        if known.isEmpty { return nil }
        return known.reduce(0, +)
    }

    static func energy(of reading: GaugeReading) -> Double {
        scale(reading.kcal100, grams: reading.grams) ?? 0
    }

    static func protein(of reading: GaugeReading) -> Double? {
        scale(reading.protein100, grams: reading.grams)
    }

    static func carbs(of reading: GaugeReading) -> Double? {
        scale(reading.carbs100, grams: reading.grams)
    }

    static func fat(of reading: GaugeReading) -> Double? {
        scale(reading.fat100, grams: reading.grams)
    }
}
