import XCTest
@testable import Eatometer

final class PortionMathsTests: XCTestCase {
    func testDirectKilocalories() {
        XCTAssertEqual(GaugeMaths.kilocaloriesPerHundredGrams(kcal100: 144, energyKj100: 600), 144)
        XCTAssertEqual(GaugeMaths.scale(144, grams: 150), 216)
    }

    func testKilojouleFallback() {
        let kcal = GaugeMaths.kilocaloriesPerHundredGrams(kcal100: nil, energyKj100: 418.4)
        XCTAssertEqual(kcal ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(GaugeMaths.scale(kcal, grams: 50) ?? 0, 50, accuracy: 0.001)
    }
}

final class BarcodeNormalizerTests: XCTestCase {
    func testEAN8() {
        XCTAssertEqual(DialBarcode.candidates(from: "12345678").first, "12345678")
    }

    func testEAN13() {
        XCTAssertEqual(DialBarcode.candidates(from: "0018627103257").first, "0018627103257")
    }

    func testUPCAPadding() {
        XCTAssertEqual(DialBarcode.candidates(from: "012345678905").first, "0012345678905")
    }

    func testURLInput() {
        let url = "https://world.openfoodfacts.org/product/0025484000107/tofu"
        XCTAssertEqual(DialBarcode.primary(from: url), "0025484000107")
    }

    func testNoValidRun() {
        XCTAssertTrue(DialBarcode.candidates(from: "abc-12-xyz").isEmpty)
    }
}

final class MissingMacroTests: XCTestCase {
    func testUnknownStaysUnknown() {
        XCTAssertNil(GaugeMaths.scale(nil, grams: 80))
        XCTAssertNil(GaugeMaths.sumMacro([nil, nil]))
        let reading = GaugeReading(
            id: UUID(),
            barcode: "1",
            specimenName: "Blank",
            brand: "",
            grams: 100,
            slot: .readingI,
            dayKey: "2026-08-25",
            isEaten: true,
            createdAt: Date(),
            kcal100: 10,
            protein100: nil,
            carbs100: nil,
            fat100: nil,
            imageURL: nil,
            shelfAsset: nil
        )
        XCTAssertNil(GaugeMaths.protein(of: reading))
        XCTAssertEqual(GaugeMaths.energy(of: reading), 10)
    }
}

final class DayTotalTests: XCTestCase {
    func testAggregationAcrossSlots() {
        func row(_ slot: DialSlot, grams: Double) -> GaugeReading {
            GaugeReading(
                id: UUID(),
                barcode: "x",
                specimenName: "Tofu Firm",
                brand: "",
                grams: grams,
                slot: slot,
                dayKey: "2026-08-25",
                isEaten: true,
                createdAt: Date(),
                kcal100: 100,
                protein100: 10,
                carbs100: 20,
                fat100: 5,
                imageURL: nil,
                shelfAsset: nil
            )
        }
        let board = ReadingSelector.assemble([
            row(.readingI, grams: 100),
            row(.readingII, grams: 50),
            row(.readingIII, grams: 25),
            row(.spotCheck, grams: 25)
        ])
        XCTAssertEqual(board.energy, 200)
        XCTAssertEqual(board.protein, 20)
        XCTAssertEqual(board.slotEnergy[.readingI], 100)
        XCTAssertEqual(board.bySlot.values.compactMap { $0.first }.count, 4)
    }
}

final class WatchlistUniquenessTests: XCTestCase {
    func testDuplicateUpdatesExisting() {
        let first = WatchlistMark(barcode: "0025484000107", name: "A", brand: "", addedAt: Date(timeIntervalSince1970: 1), kcal100: 1, imageURL: nil, shelfAsset: nil)
        let second = WatchlistMark(barcode: "0025484000107", name: "B", brand: "", addedAt: Date(timeIntervalSince1970: 2), kcal100: 2, imageURL: nil, shelfAsset: nil)
        let merged = WatchlistPolicy.integrating(existing: [first], incoming: second)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.name, "B")
        XCTAssertTrue(WatchlistPolicy.contains(merged, barcode: "0025484000107"))
    }
}

final class DayBoundaryTests: XCTestCase {
    func testDaylightSavingSpringForward() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        var comps = DateComponents()
        comps.year = 2024
        comps.month = 3
        comps.day = 10
        comps.hour = 1
        comps.minute = 30
        let before = calendar.date(from: comps) ?? Date()
        comps.hour = 3
        let after = calendar.date(from: comps) ?? Date()
        XCTAssertEqual(DayKey.make(before, calendar: calendar), "2024-03-10")
        XCTAssertEqual(DayKey.make(after, calendar: calendar), "2024-03-10")
        XCTAssertEqual(DayKey.shift("2024-03-10", days: -1, calendar: calendar), "2024-03-09")
        XCTAssertEqual(DayKey.shift("2024-03-10", days: 1, calendar: calendar), "2024-03-11")
    }
}

final class CatalogDecodingTests: XCTestCase {
    func testMissingAndStringNutriments() throws {
        let json = """
        {
          "status": 1,
          "product": {
            "code": "12345678",
            "product_name": "Stringed Tofu",
            "brands": "Drum",
            "nutriments": {
              "energy-kcal_100g": "144",
              "proteins_100g": "15.8",
              "carbohydrates_100g": null
            }
          }
        }
        """.data(using: .utf8) ?? Data()
        let record = try SpecimenMapper.decodeProduct(json)
        XCTAssertEqual(record.name, "Stringed Tofu")
        XCTAssertEqual(record.kcal100, 144)
        XCTAssertEqual(record.protein100, 15.8)
        XCTAssertNil(record.carbs100)
        XCTAssertNil(record.fat100)
    }

    func testStatusZeroIsUnknown() {
        let json = """
        { "status": 0, "product": {} }
        """.data(using: .utf8) ?? Data()
        XCTAssertThrowsError(try SpecimenMapper.decodeProduct(json)) { error in
            XCTAssertEqual(error as? CatalogFault, .unknownSpecimen)
        }
    }
}

final class AnalyticsSelectorTests: XCTestCase {
    func testWindowedWeeklyAndExtremes() {
        var state = AppState.launch()
        state.calibration = DialCalibration(kcal: 100, protein: 10, carbs: 10, fat: 10)
        let calendar = Calendar(identifier: .gregorian)
        let start = DayKey.make(Date(), calendar: calendar)
        for offset in 0..<10 {
            let key = DayKey.shift(start, days: -offset, calendar: calendar)
            state.readings.append(
                GaugeReading(
                    id: UUID(),
                    barcode: "x",
                    specimenName: "Granola",
                    brand: "",
                    grams: offset == 0 ? 200 : (offset == 1 ? 90 : 50),
                    slot: .readingI,
                    dayKey: key,
                    isEaten: true,
                    createdAt: Date(),
                    kcal100: 100,
                    protein100: 10,
                    carbs100: 10,
                    fat100: 10,
                    imageURL: nil,
                    shelfAsset: nil
                )
            )
        }
        let ledger = AnalyticsSelector.ledger(from: state, days: 7, calendar: calendar)
        XCTAssertEqual(ledger.daily.count, 7)
        XCTAssertFalse(ledger.weeklyWindows.isEmpty)
        XCTAssertEqual(ledger.bestDay?.kcal, 200)
        XCTAssertEqual(ledger.worstDay?.kcal, 50)
        XCTAssertGreaterThan(ledger.adherencePercent, 0)
    }
}

final class ReducerArchitectureTests: XCTestCase {
    func testRejectsZeroKilocalorieCalibration() {
        var state = AppState.launch()
        let next = meterReducer(state: state, action: .calibration(.write(DialCalibration(kcal: 0, protein: 10, carbs: 10, fat: 10))))
        XCTAssertEqual(next.calibration.kcal, state.calibration.kcal)
    }

    func testSpotCheckRemapsOnFutureDate() {
        var state = AppState.launch()
        let specimen = SpecimenShelf.bundled[0]
        state.measurement = MeasurementDraft(
            specimen: specimen,
            gramsText: "100",
            slot: .spotCheck,
            dayKey: state.clockDayKey,
            eatenToday: true,
            isCommitting: false,
            remappedNote: nil
        )
        state = meterReducer(state: state, action: .catalog(.eatenToggled(false)))
        XCTAssertEqual(state.measurement?.slot, .readingI)
        XCTAssertEqual(DialSlotPolicy.resolved(slot: .spotCheck, dayKey: DayKey.shift(state.clockDayKey, days: 2), today: state.clockDayKey), .readingI)
    }
}

@MainActor
final class PersistenceRoundTripTests: XCTestCase {
    func testWriteReload() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("etm-roundtrip-\(UUID().uuidString).sqlite")
        let first = DialPersistenceStack(storeURL: url)
        let specimen = SpecimenShelf.bundled[0]
        try await first.write { context in
            let entity = ReadingEntity(context: context)
            entity.id = UUID()
            entity.grams = 150
            entity.slotRaw = DialSlot.readingI.rawValue
            entity.dayKey = "2026-08-25"
            entity.isEaten = true
            entity.createdAt = Date()
            entity.specimen = try LedgerWriter.upsertSpecimen(specimen, in: context)
        }
        let second = DialPersistenceStack(storeURL: url)
        let snap = second.snapshot(today: "2026-08-25")
        XCTAssertTrue(snap.readings.contains { $0.barcode == specimen.barcode && $0.grams == 150 })
        try? FileManager.default.removeItem(at: url)
    }
}
