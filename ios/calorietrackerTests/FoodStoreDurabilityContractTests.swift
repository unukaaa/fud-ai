import Foundation
import Testing
@testable import calorietracker

/// Accepted ADD durability behavior. EDIT/REPLACE desired-contract tests are
/// retained outside this test target until their separate image transaction task.
@MainActor
struct FoodStoreDurabilityContractTests {
    @Test func validAddIsVisibleAfterReload() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let entry = makeEntry(name: "Original")
            var changes = 0
            var additions = 0
            store.onEntriesChanged = { changes += 1 }
            store.onEntryAdded = { _ in additions += 1 }

            #expect(store.addEntry(entry))
            #expect(store.entries.map(\.id) == [entry.id])
            #expect(reloaded(defaults).entries.map(\.id) == [entry.id])
            #expect(changes == 1)
            #expect(additions == 1)
        }
    }

    @Test func failedPrewriteAddMustRemoveOnlyItsNewPhoto() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("old photo".utf8)
            #expect(store.addEntry(original))
            let oldFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: oldFilename) }
            let photosBefore = Set(FoodImageStore.shared.filenames())

            var rejected = original
            rejected.imageFilename = nil
            rejected.imageData = Data("new photo".utf8)
            rejected.protein = .nan
            #expect(!store.addEntry(rejected))

            #expect(store.entries.map(\.id) == [original.id])
            #expect(reloaded(defaults).entries.map(\.id) == [original.id])
            #expect(FoodImageStore.shared.load(filename: oldFilename) == Data("old photo".utf8))
            #expect(Set(FoodImageStore.shared.filenames()) == photosBefore)
        }
    }

    @Test func failedPrewriteAddMustNotReportSuccessOrPublishCallbacks() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let original = makeEntry(name: "Original")
            #expect(store.addEntry(original))

            var changes = 0
            var additions = 0
            store.onEntriesChanged = { changes += 1 }
            store.onEntryAdded = { _ in additions += 1 }
            let unencodable = makeEntry(name: "Unencodable", protein: .nan)
            #expect((try? JSONEncoder().encode([unencodable])) == nil)

            #expect(!store.addEntry(unencodable))
            #expect(store.entries.map(\.id) == [original.id])
            #expect(reloaded(defaults).entries.map(\.id) == [original.id])
            #expect(changes == 0)
            #expect(additions == 0)
        }
    }

    @Test func postwriteSynchronizationFailureStillLeavesNewLocalValue() throws {
        let suite = "FoodStoreDurabilityContractTests.\(UUID().uuidString)"
        let defaults = try #require(SynchronizationFailingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FoodStore(observesExternalChanges: false, defaults: defaults)
        let entry = makeEntry(name: "Locally set")
        var changes = 0
        var additions = 0
        store.onEntriesChanged = { changes += 1 }
        store.onEntryAdded = { _ in additions += 1 }

        #expect(!defaults.synchronize())
        #expect(store.addEntry(entry))
        #expect(store.entries.map(\.id) == [entry.id])
        #expect(reloaded(defaults).entries.map(\.id) == [entry.id])
        #expect(changes == 1)
        #expect(additions == 1)
        // This same-process reload proves local visibility, not a durable disk write.
    }

    private func makeEntry(name: String, protein: Double = 1) -> FoodEntry {
        FoodEntry(name: name, calories: 100, protein: protein, carbs: 10, fat: 2, source: .manual)
    }

    private func reloaded(_ defaults: UserDefaults) -> FoodStore {
        FoodStore(observesExternalChanges: false, defaults: defaults)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "FoodStoreDurabilityContractTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

private final class SynchronizationFailingDefaults: UserDefaults {
    override func synchronize() -> Bool { false }
}
