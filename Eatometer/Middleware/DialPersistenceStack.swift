import CoreData
import Foundation

/// Role: Core Data composition root. Programmatic model, FRC-ready view context, value types at the seam.
@MainActor
final class DialPersistenceStack {
    let container: NSPersistentContainer
    private(set) var recoverNotice: String?

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        let model = Self.makeModel()
        let container = NSPersistentContainer(name: "Eatometer", managedObjectModel: model)
        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
            description.type = NSSQLiteStoreType
        } else if let storeURL {
            description.url = storeURL
        }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if loadError != nil {
            Self.destroyStores(description)
            var second: Error?
            container.loadPersistentStores { _, error in
                second = error
            }
            if second == nil {
                recoverNotice = "The instrument ledger was rebuilt after a store fault."
            } else {
                recoverNotice = "The instrument ledger could not be opened. Readings stay in memory until the next launch."
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        self.container = container
    }

    func snapshot(today: String) -> PersistenceSnapshot {
        let context = container.viewContext
        let start = DayKey.shift(today, days: -400)
        let end = DayKey.shift(today, days: 15)
        let readingRequest = ReadingEntity.fetchRequest()
        readingRequest.fetchBatchSize = 20
        readingRequest.predicate = NSPredicate(format: "dayKey >= %@ AND dayKey < %@", start, end)
        readingRequest.sortDescriptors = [
            NSSortDescriptor(key: "dayKey", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        let readings = ((try? context.fetch(readingRequest)) ?? []).compactMap(EntityMap.reading)

        let specimenRequest = SpecimenEntity.fetchRequest()
        specimenRequest.fetchBatchSize = 20
        specimenRequest.sortDescriptors = [
            NSSortDescriptor(key: "barcode", ascending: true)
        ]
        let specimens = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(specimenRequest)) ?? []).map {
                let record = EntityMap.specimen($0)
                return (record.barcode, record)
            }
        )

        let wishRequest = WatchlistEntity.fetchRequest()
        wishRequest.fetchBatchSize = 20
        wishRequest.sortDescriptors = [
            NSSortDescriptor(key: "addedAt", ascending: false),
            NSSortDescriptor(key: "barcode", ascending: true)
        ]
        let watchlist = ((try? context.fetch(wishRequest)) ?? []).compactMap(EntityMap.watch)

        let calRequest = CalibrationEntity.fetchRequest()
        calRequest.fetchLimit = 1
        let calibration = ((try? context.fetch(calRequest)) ?? []).first.map(EntityMap.calibration) ?? .factory

        return PersistenceSnapshot(
            calibration: calibration,
            specimens: specimens,
            readings: readings,
            watchlist: watchlist,
            notice: recoverNotice
        )
    }

    func makeReadingsController(today: String) -> NSFetchedResultsController<ReadingEntity> {
        let start = DayKey.shift(today, days: -400)
        let end = DayKey.shift(today, days: 15)
        let request = ReadingEntity.fetchRequest()
        request.fetchBatchSize = 20
        request.predicate = NSPredicate(format: "dayKey >= %@ AND dayKey < %@", start, end)
        request.sortDescriptors = [
            NSSortDescriptor(key: "dayKey", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "id", ascending: true)
        ]
        return NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: container.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
    }

    func makeWatchController() -> NSFetchedResultsController<WatchlistEntity> {
        let request = WatchlistEntity.fetchRequest()
        request.fetchBatchSize = 20
        request.sortDescriptors = [
            NSSortDescriptor(key: "addedAt", ascending: false),
            NSSortDescriptor(key: "barcode", ascending: true)
        ]
        return NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: container.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
    }

    func write(_ block: @escaping @Sendable (NSManagedObjectContext) throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
                do {
                    try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func upsertSpecimen(_ record: SpecimenRecord, in context: NSManagedObjectContext) throws -> SpecimenEntity {
        try LedgerWriter.upsertSpecimen(record, in: context)
    }

    func writeCalibration(_ calibration: DialCalibration, in context: NSManagedObjectContext) throws {
        try LedgerWriter.writeCalibration(calibration, in: context)
    }

    func resetAllData() async throws {
        try await write { context in
            for name in ["ReadingEntity", "WatchlistEntity", "CalibrationEntity", "SpecimenEntity"] {
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: name)
                let delete = NSBatchDeleteRequest(fetchRequest: request)
                delete.resultType = .resultTypeObjectIDs
                let result = try context.execute(delete) as? NSBatchDeleteResult
                if let ids = result?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: ids],
                        into: [context]
                    )
                }
            }
        }
    }

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["etm.schema.1"]

        let specimen = NSEntityDescription()
        specimen.name = "SpecimenEntity"
        specimen.managedObjectClassName = "SpecimenEntity"

        let reading = NSEntityDescription()
        reading.name = "ReadingEntity"
        reading.managedObjectClassName = "ReadingEntity"

        let watch = NSEntityDescription()
        watch.name = "WatchlistEntity"
        watch.managedObjectClassName = "WatchlistEntity"

        let calibration = NSEntityDescription()
        calibration.name = "CalibrationEntity"
        calibration.managedObjectClassName = "CalibrationEntity"

        specimen.properties = [
            attribute("barcode", .stringAttributeType, optional: false),
            attribute("name", .stringAttributeType, optional: false),
            attribute("brand", .stringAttributeType, optional: false, defaultValue: ""),
            attribute("kcal100", .doubleAttributeType, optional: true),
            attribute("protein100", .doubleAttributeType, optional: true),
            attribute("carbs100", .doubleAttributeType, optional: true),
            attribute("fat100", .doubleAttributeType, optional: true),
            attribute("imageURL", .stringAttributeType, optional: true),
            attribute("shelfAsset", .stringAttributeType, optional: true),
            attribute("refreshedAt", .dateAttributeType, optional: false)
        ]
        reading.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("grams", .doubleAttributeType, optional: false),
            attribute("slotRaw", .stringAttributeType, optional: false),
            attribute("dayKey", .stringAttributeType, optional: false),
            attribute("isEaten", .booleanAttributeType, optional: false, defaultValue: true),
            attribute("createdAt", .dateAttributeType, optional: false)
        ]
        watch.properties = [
            attribute("barcode", .stringAttributeType, optional: false),
            attribute("addedAt", .dateAttributeType, optional: false)
        ]
        calibration.properties = [
            attribute("id", .stringAttributeType, optional: false),
            attribute("kcal", .doubleAttributeType, optional: false, defaultValue: 2200),
            attribute("protein", .doubleAttributeType, optional: true),
            attribute("carbs", .doubleAttributeType, optional: true),
            attribute("fat", .doubleAttributeType, optional: true)
        ]

        let specimenReadings = NSRelationshipDescription()
        specimenReadings.name = "readings"
        specimenReadings.destinationEntity = reading
        specimenReadings.minCount = 0
        specimenReadings.maxCount = 0
        specimenReadings.deleteRule = .cascadeDeleteRule

        let readingSpecimen = NSRelationshipDescription()
        readingSpecimen.name = "specimen"
        readingSpecimen.destinationEntity = specimen
        readingSpecimen.minCount = 0
        readingSpecimen.maxCount = 1
        readingSpecimen.deleteRule = .nullifyDeleteRule
        readingSpecimen.isOptional = true

        specimenReadings.inverseRelationship = readingSpecimen
        readingSpecimen.inverseRelationship = specimenReadings

        let specimenWatch = NSRelationshipDescription()
        specimenWatch.name = "watchMarks"
        specimenWatch.destinationEntity = watch
        specimenWatch.minCount = 0
        specimenWatch.maxCount = 0
        specimenWatch.deleteRule = .cascadeDeleteRule

        let watchSpecimen = NSRelationshipDescription()
        watchSpecimen.name = "specimen"
        watchSpecimen.destinationEntity = specimen
        watchSpecimen.minCount = 0
        watchSpecimen.maxCount = 1
        watchSpecimen.deleteRule = .nullifyDeleteRule
        watchSpecimen.isOptional = true

        specimenWatch.inverseRelationship = watchSpecimen
        watchSpecimen.inverseRelationship = specimenWatch

        specimen.properties.append(contentsOf: [specimenReadings, specimenWatch])
        reading.properties.append(readingSpecimen)
        watch.properties.append(watchSpecimen)

        specimen.uniquenessConstraints = [["barcode"]]
        watch.uniquenessConstraints = [["barcode"]]

        model.entities = [specimen, reading, watch, calibration]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let item = NSAttributeDescription()
        item.name = name
        item.attributeType = type
        item.isOptional = optional
        if let defaultValue {
            item.defaultValue = defaultValue
        }
        return item
    }

    private static func destroyStores(_ description: NSPersistentStoreDescription) {
        guard let url = description.url, url.path != "/dev/null" else { return }
        let extras = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal")
        ]
        for item in extras {
            try? FileManager.default.removeItem(at: item)
        }
    }
}

extension SpecimenEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SpecimenEntity> {
        NSFetchRequest<SpecimenEntity>(entityName: "SpecimenEntity")
    }
}

extension ReadingEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<ReadingEntity> {
        NSFetchRequest<ReadingEntity>(entityName: "ReadingEntity")
    }
}

extension WatchlistEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<WatchlistEntity> {
        NSFetchRequest<WatchlistEntity>(entityName: "WatchlistEntity")
    }
}

extension CalibrationEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CalibrationEntity> {
        NSFetchRequest<CalibrationEntity>(entityName: "CalibrationEntity")
    }
}
