import CoreData
import Foundation

@objc(SpecimenEntity)
final class SpecimenEntity: NSManagedObject {
    @NSManaged var barcode: String
    @NSManaged var name: String
    @NSManaged var brand: String
    @NSManaged var kcal100: NSNumber?
    @NSManaged var protein100: NSNumber?
    @NSManaged var carbs100: NSNumber?
    @NSManaged var fat100: NSNumber?
    @NSManaged var imageURL: String?
    @NSManaged var shelfAsset: String?
    @NSManaged var refreshedAt: Date
    @NSManaged var readings: NSSet?
    @NSManaged var watchMarks: NSSet?
}

@objc(ReadingEntity)
final class ReadingEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var grams: Double
    @NSManaged var slotRaw: String
    @NSManaged var dayKey: String
    @NSManaged var isEaten: Bool
    @NSManaged var createdAt: Date
    @NSManaged var specimen: SpecimenEntity?
}

@objc(WatchlistEntity)
final class WatchlistEntity: NSManagedObject {
    @NSManaged var barcode: String
    @NSManaged var addedAt: Date
    @NSManaged var specimen: SpecimenEntity?
}

@objc(CalibrationEntity)
final class CalibrationEntity: NSManagedObject {
    @NSManaged var id: String
    @NSManaged var kcal: Double
    @NSManaged var protein: NSNumber?
    @NSManaged var carbs: NSNumber?
    @NSManaged var fat: NSNumber?
}

enum LedgerWriter {
    static func upsertSpecimen(_ record: SpecimenRecord, in context: NSManagedObjectContext) throws -> SpecimenEntity {
        let request = SpecimenEntity.fetchRequest()
        request.predicate = NSPredicate(format: "barcode == %@", record.barcode)
        request.fetchLimit = 1
        let entity = try context.fetch(request).first ?? SpecimenEntity(context: context)
        entity.barcode = record.barcode
        entity.name = record.name
        entity.brand = record.brand
        entity.kcal100 = record.kcal100.map { NSNumber(value: $0) }
        entity.protein100 = record.protein100.map { NSNumber(value: $0) }
        entity.carbs100 = record.carbs100.map { NSNumber(value: $0) }
        entity.fat100 = record.fat100.map { NSNumber(value: $0) }
        entity.imageURL = record.imageURL
        entity.shelfAsset = record.shelfAsset
        entity.refreshedAt = record.refreshedAt
        return entity
    }

    static func writeCalibration(_ calibration: DialCalibration, in context: NSManagedObjectContext) throws {
        let request = CalibrationEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", "dial")
        request.fetchLimit = 1
        let entity = try context.fetch(request).first ?? CalibrationEntity(context: context)
        entity.id = "dial"
        entity.kcal = calibration.kcal
        entity.protein = calibration.protein.map { NSNumber(value: $0) }
        entity.carbs = calibration.carbs.map { NSNumber(value: $0) }
        entity.fat = calibration.fat.map { NSNumber(value: $0) }
    }
}

enum EntityMap {
    static func specimen(_ entity: SpecimenEntity) -> SpecimenRecord {
        SpecimenRecord(
            barcode: entity.barcode,
            name: entity.name,
            brand: entity.brand,
            kcal100: entity.kcal100?.doubleValue,
            protein100: entity.protein100?.doubleValue,
            carbs100: entity.carbs100?.doubleValue,
            fat100: entity.fat100?.doubleValue,
            imageURL: entity.imageURL,
            shelfAsset: entity.shelfAsset,
            refreshedAt: entity.refreshedAt
        )
    }

    static func reading(_ entity: ReadingEntity) -> GaugeReading? {
        guard let specimen = entity.specimen,
              let slot = DialSlot(rawValue: entity.slotRaw)
        else { return nil }
        return GaugeReading(
            id: entity.id,
            barcode: specimen.barcode,
            specimenName: specimen.name,
            brand: specimen.brand,
            grams: entity.grams,
            slot: slot,
            dayKey: entity.dayKey,
            isEaten: entity.isEaten,
            createdAt: entity.createdAt,
            kcal100: specimen.kcal100?.doubleValue,
            protein100: specimen.protein100?.doubleValue,
            carbs100: specimen.carbs100?.doubleValue,
            fat100: specimen.fat100?.doubleValue,
            imageURL: specimen.imageURL,
            shelfAsset: specimen.shelfAsset
        )
    }

    static func watch(_ entity: WatchlistEntity) -> WatchlistMark? {
        guard let specimen = entity.specimen else { return nil }
        return WatchlistMark(
            barcode: entity.barcode,
            name: specimen.name,
            brand: specimen.brand,
            addedAt: entity.addedAt,
            kcal100: specimen.kcal100?.doubleValue,
            imageURL: specimen.imageURL,
            shelfAsset: specimen.shelfAsset
        )
    }

    static func calibration(_ entity: CalibrationEntity) -> DialCalibration {
        DialCalibration(
            kcal: entity.kcal,
            protein: entity.protein?.doubleValue,
            carbs: entity.carbs?.doubleValue,
            fat: entity.fat?.doubleValue
        )
    }
}
