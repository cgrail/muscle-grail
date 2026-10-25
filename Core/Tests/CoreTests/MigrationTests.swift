import Foundation
import SwiftData
import Testing
@testable import Core

/// What a schema version writes before it migrates: a plan with an exercise, a workout with a set, an action and a catalog entry.
/// Every version in `MigrationPlan` gets one, frozen with it.
protocol Seeded: VersionedSchema {
    @MainActor static func seed(_ context: ModelContext)
}

extension SchemaV1: Seeded {
    @MainActor static func seed(_ context: ModelContext) {
        let plan = Plan(name: "Push", order: 0), item = PlanItem(exerciseID: "Bench", order: 0)
        let workout = Workout(), set = LoggedSet(exerciseID: "Bench", reps: 8, weightKg: 60)
        context.insert(plan)
        context.insert(item)
        context.insert(workout)
        context.insert(set)
        context.insert(Action())
        context.insert(CatalogEntry(id: "Bench"))
        item.plan = plan
        workout.plan = plan
        set.workout = workout
    }
}

/// Every entity's fields and their types.
func fields(_ schema: Schema) -> [String: [String: String]] {
    Dictionary(uniqueKeysWithValues: schema.entities.map { entity in
        let properties: [any SchemaProperty] = Array(entity.attributes) + Array(entity.relationships)
        return (entity.name, Dictionary(uniqueKeysWithValues: properties.map { ($0.name, String(describing: $0.valueType)) }))
    })
}

@MainActor struct MigrationTests {
    @Test(arguments: MigrationPlan.schemas.indices)
    func everyVersionMigratesToTheNewest(version: Int) throws {
        let old = MigrationPlan.schemas[version]
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "store")
        do {
            let layout = try #require(old as? any StoreLayout.Type)
            let container = try ModelContainer(for: Schema(versionedSchema: old), configurations: Store.configurations(layout, url: url))
            try #require(old as? Seeded.Type, "\(old) needs a seed").seed(container.mainContext)
            try container.mainContext.save()
        }

        let newest = try Store.makeContainer(url: url)
        let workout = try #require(newest.mainContext.fetch(FetchDescriptor<Workout>()).first)
        #expect(workout.plan?.sortedItems.map(\.exerciseID) == ["Bench"])
        #expect(workout.sets(of: "Bench").map(\.reps) == [8])
        #expect(try newest.mainContext.fetchCount(FetchDescriptor<Action>()) == 1)
        #expect(try newest.mainContext.fetchCount(FetchDescriptor<CatalogEntry>()) == 1)
    }

    /// Older app versions keep reading what newer ones sync, and CloudKit can't rename or delete a field.
    @Test func everyVersionKeepsEveryFieldOfTheOneBefore() {
        let versions = MigrationPlan.schemas.map { fields(Schema(versionedSchema: $0)) }
        for (old, new) in zip(versions, versions.dropFirst()) {
            for (entity, fields) in old {
                for (field, type) in fields {
                    #expect(new[entity]?[field] == type, "\(entity).\(field) must stay a \(type)")
                }
            }
        }
    }

    /// Records from older versions lack the newer fields.
    @Test func everyFieldMayBeMissing() {
        for version in MigrationPlan.schemas {
            for entity in Schema(versionedSchema: version).entities {
                for attribute in entity.attributes {
                    #expect(attribute.isOptional || attribute.defaultValue != nil, "\(version): \(entity.name).\(attribute.name) needs a default")
                }
                for relationship in entity.relationships {
                    #expect(relationship.isOptional, "\(version): \(entity.name).\(relationship.name) must be optional")
                }
            }
        }
    }

    @Test func appRunsTheNewestVersion() throws {
        let newest = try #require(MigrationPlan.schemas.last)
        #expect(fields(try Store.makeContainer(inMemory: true).schema) == fields(Schema(versionedSchema: newest)))
    }
}
