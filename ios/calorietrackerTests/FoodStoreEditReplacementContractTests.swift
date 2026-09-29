import Foundation
import Testing
@testable import calorietracker

/// EDIT/REPLACE durability and image ownership contracts.
@MainActor
struct FoodStoreEditReplacementContractTests {
    @Test func failedPrewriteReplacementMustPreserveOldEntryAndPhotoAndRemoveNewPhoto() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("old photo".utf8)
            #expect(store.addEntry(original))
            let oldFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: oldFilename) }
            #expect(FoodImageStore.shared.load(filename: oldFilename) == Data("old photo".utf8))

            var replacement = makeEntry(name: "Unencodable replacement", protein: .nan)
            replacement.imageData = Data("new photo".utf8)
            let newFilename = "\(replacement.id.uuidString).jpg"
            #expect(newFilename != oldFilename)
            #expect(FoodImageStore.shared.load(filename: newFilename) == nil)
            defer { FoodImageStore.shared.delete(filename: newFilename) }
            var changes = 0
            store.onEntriesChanged = { changes += 1 }
            #expect((try? JSONEncoder().encode([replacement])) == nil)
            #expect(store.replaceAllEntries([replacement]) == .rejectedBeforeWrite)

            #expect(store.entries.map(\.id) == [original.id])
            #expect(reloaded(defaults).entries.map(\.id) == [original.id])
            #expect(FoodImageStore.shared.load(filename: oldFilename) == Data("old photo".utf8))
            #expect(FoodImageStore.shared.load(filename: newFilename) == nil)
            #expect(changes == 0)
        }
    }

    @Test func failedPrewriteEditMustNotPublishUpdateOrOrphanNewPhoto() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let original = makeEntry(name: "Original")
            #expect(store.addEntry(original))

            var updates = 0
            store.onEntryUpdated = { _ in updates += 1 }
            var edited = original
            edited.protein = .nan
            edited.imageData = Data("new photo".utf8)
            let newFilename = "\(original.id.uuidString).jpg"
            #expect(FoodImageStore.shared.load(filename: newFilename) == nil)
            defer { FoodImageStore.shared.delete(filename: newFilename) }
            #expect((try? JSONEncoder().encode([edited])) == nil)
            #expect(store.updateEntry(edited) == .rejectedBeforeWrite)

            #expect(store.entries.first?.protein == original.protein)
            #expect(store.entries.first?.allImageFilenames.isEmpty == true)
            #expect(reloaded(defaults).entries.first?.protein == original.protein)
            #expect(FoodImageStore.shared.load(filename: newFilename) == nil)
            #expect(updates == 0)
        }
    }

    @Test func successfulEditReplacesPhotoOnlyAfterAcceptance() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("old photo".utf8)
            #expect(store.addEntry(original))
            let oldFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: oldFilename) }
            var edited = original
            edited.name = "Edited"
            edited.imageFilename = nil
            edited.imageData = Data("new photo".utf8)
            var changes = 0
            var updates = 0
            store.onEntriesChanged = { changes += 1 }
            store.onEntryUpdated = { _ in updates += 1 }

            #expect(store.updateEntry(edited) == .acceptedLocally)

            let newFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: newFilename) }
            #expect(newFilename != oldFilename)
            #expect(reloaded(defaults).entries.first?.name == "Edited")
            #expect(FoodImageStore.shared.load(filename: newFilename) == Data("new photo".utf8))
            #expect(FoodImageStore.shared.load(filename: oldFilename) == nil)
            #expect(changes == 1)
            #expect(updates == 1)
        }
    }

    @Test func postwriteSynchronizationFailureStillAcceptsEdit() throws {
        try withDefaults(SynchronizationFailingDefaults.self) { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let original = makeEntry(name: "Original")
            #expect(store.addEntry(original))
            var edited = original
            edited.name = "Edited"
            var updates = 0
            store.onEntryUpdated = { _ in updates += 1 }

            #expect(store.updateEntry(edited) == .acceptedLocally)

            #expect(store.entries.first?.name == "Edited")
            #expect(reloaded(defaults).entries.first?.name == "Edited")
            #expect(updates == 1)
        }
    }

    @Test func postwriteSynchronizationFailureStillReconcilesEditedPhotos() throws {
        try withDefaults(SynchronizationFailingDefaults.self) { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("old photo".utf8)
            #expect(store.addEntry(original))
            let oldFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: oldFilename) }
            var edited = store.entries[0]
            edited.imageFilename = nil
            edited.imageData = Data("new photo".utf8)

            #expect(store.updateEntry(edited) == .acceptedLocally)

            let newFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: newFilename) }
            #expect(newFilename != oldFilename)
            #expect(FoodImageStore.shared.load(filename: oldFilename) == nil)
            #expect(FoodImageStore.shared.load(filename: newFilename) == Data("new photo".utf8))
            #expect(reloaded(defaults).entries.first?.imageFilename == newFilename)
        }
    }

    @Test func successfulReplacementKeepsNewPhotoAndRemovesObsoleteOldPhoto() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("old photo".utf8)
            #expect(store.addEntry(original))
            let oldFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: oldFilename) }
            var replacement = makeEntry(name: "Replacement")
            replacement.imageData = Data("new photo".utf8)
            var changes = 0
            store.onEntriesChanged = { changes += 1 }

            #expect(store.replaceAllEntries([replacement]) == .acceptedLocally)

            let newFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: newFilename) }
            #expect(store.entries.map(\.id) == [replacement.id])
            #expect(reloaded(defaults).entries.map(\.id) == [replacement.id])
            #expect(FoodImageStore.shared.load(filename: oldFilename) == nil)
            #expect(FoodImageStore.shared.load(filename: newFilename) == Data("new photo".utf8))
            #expect(changes == 1)
        }
    }

    @Test func postwriteSynchronizationFailureStillAcceptsReplacement() throws {
        try withDefaults(SynchronizationFailingDefaults.self) { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let original = makeEntry(name: "Original")
            #expect(store.addEntry(original))
            let replacement = makeEntry(name: "Replacement")
            var changes = 0
            store.onEntriesChanged = { changes += 1 }

            #expect(store.replaceAllEntries([replacement]) == .acceptedLocally)

            #expect(store.entries.map(\.id) == [replacement.id])
            #expect(reloaded(defaults).entries.map(\.id) == [replacement.id])
            #expect(changes == 1)
        }
    }

    @Test func replacementDoesNotDeletePhotoSharedWithSurvivingEntry() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("shared photo".utf8)
            #expect(store.addEntry(original))
            let filename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: filename) }
            var survivor = makeEntry(name: "Survivor")
            survivor.imageFilename = filename
            #expect(store.addEntry(survivor))

            #expect(store.replaceAllEntries([survivor]) == .acceptedLocally)

            #expect(FoodImageStore.shared.load(filename: filename) == Data("shared photo".utf8))
            #expect(reloaded(defaults).entries.first?.imageFilename == filename)
        }
    }

    @Test func replacementDoesNotDeletePhotoSharedWithFavorite() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("favorite photo".utf8)
            #expect(store.addEntry(original))
            let filename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: filename) }
            store.toggleFavorite(store.entries[0])

            #expect(store.replaceAllEntries([]) == .acceptedLocally)

            #expect(FoodImageStore.shared.load(filename: filename) == Data("favorite photo".utf8))
            #expect(store.favorites.first?.imageFilename == filename)
        }
    }

    @Test func rejectedImportSuppressesAllSuccessCallbacks() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let original = makeEntry(name: "Original")
            #expect(store.addEntry(original))
            var changes = 0
            var added = 0
            var updated = 0
            var deleted = 0
            store.onEntriesChanged = { changes += 1 }
            store.onEntryAdded = { _ in added += 1 }
            store.onEntryUpdated = { _ in updated += 1 }
            store.onEntryDeleted = { _ in deleted += 1 }
            var invalid = makeEntry(name: "Invalid", protein: .nan)
            invalid.imageData = Data("new photo".utf8)
            let newFilename = "\(invalid.id.uuidString).jpg"
            defer { FoodImageStore.shared.delete(filename: newFilename) }

            #expect(store.replaceEntriesFromImport([invalid]) == .rejectedBeforeWrite)

            #expect(store.entries.map(\.id) == [original.id])
            #expect(reloaded(defaults).entries.map(\.id) == [original.id])
            #expect(FoodImageStore.shared.load(filename: newFilename) == nil)
            #expect(changes == 0 && added == 0 && updated == 0 && deleted == 0)
        }
    }

    @Test func acceptedImportPublishesOnlyAcceptedChanges() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let original = makeEntry(name: "Original")
            #expect(store.addEntry(original))
            let replacement = makeEntry(name: "Replacement")
            var changes = 0
            var added = 0
            var deleted = 0
            store.onEntriesChanged = { changes += 1 }
            store.onEntryAdded = { _ in added += 1 }
            store.onEntryDeleted = { _ in deleted += 1 }

            #expect(store.replaceEntriesFromImport([replacement]) == .acceptedLocally)

            #expect(store.entries.map(\.id) == [replacement.id])
            #expect(changes == 1 && added == 1 && deleted == 1)
        }
    }

    @Test func postwriteSynchronizationFailureStillPublishesImportCallbacks() throws {
        try withDefaults(SynchronizationFailingDefaults.self) { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            let original = makeEntry(name: "Original")
            #expect(store.addEntry(original))
            let replacement = makeEntry(name: "Replacement")
            var changes = 0
            var added = 0
            var deleted = 0
            store.onEntriesChanged = { changes += 1 }
            store.onEntryAdded = { _ in added += 1 }
            store.onEntryDeleted = { _ in deleted += 1 }

            #expect(store.replaceEntriesFromImport([replacement]) == .acceptedLocally)

            #expect(reloaded(defaults).entries.map(\.id) == [replacement.id])
            #expect(changes == 1 && added == 1 && deleted == 1)
        }
    }

    @Test func rejectedEditPreservesFavoritePhotoAndCleansOnlyUnreferencedNewPhoto() throws {
        try withDefaults { defaults in
            let store = FoodStore(observesExternalChanges: false, defaults: defaults)
            var original = makeEntry(name: "Original")
            original.imageData = Data("old photo".utf8)
            #expect(store.addEntry(original))
            let oldFilename = try #require(store.entries.first?.imageFilename)
            defer { FoodImageStore.shared.delete(filename: oldFilename) }
            store.toggleFavorite(store.entries[0])
            let photosBefore = Set(FoodImageStore.shared.filenames())
            var edited = store.entries[0]
            edited.protein = .nan
            edited.imageFilename = nil
            edited.imageData = Data("new photo".utf8)

            #expect(store.updateEntry(edited) == .rejectedBeforeWrite)

            #expect(store.entries.first?.imageFilename == oldFilename)
            #expect(store.favorites.first?.imageFilename == oldFilename)
            #expect(FoodImageStore.shared.load(filename: oldFilename) == Data("old photo".utf8))
            #expect(Set(FoodImageStore.shared.filenames()) == photosBefore)
        }
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

    private func withDefaults(_ type: SynchronizationFailingDefaults.Type, _ body: (UserDefaults) throws -> Void) throws {
        let suite = "FoodStoreDurabilityContractTests.\(UUID().uuidString)"
        let defaults = try #require(SynchronizationFailingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

private final class SynchronizationFailingDefaults: UserDefaults {
    override func synchronize() -> Bool { false }
}
