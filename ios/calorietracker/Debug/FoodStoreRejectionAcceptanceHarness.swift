#if DEBUG
import Foundation
import SwiftUI

/// Isolated runtime fixture for rejected Edit Food / Import Diary UI acceptance.
/// Activated only by the UI test launch argument; no app diary defaults are used.
@MainActor
@Observable
private final class FoodStoreRejectionFixture {
    let defaults: EphemeralFoodStoreDefaults
    let foodStore: FoodStore
    let waterStore: WaterStore
    let originalEntry: FoodEntry
    var changeCallbacks = 0
    var successCallbacks = 0

    init() {
        let defaults = EphemeralFoodStoreDefaults(suiteName: "FoodStoreRejectionAcceptance.\(UUID())")!
        let original = FoodEntry(
            name: "Accepted old diary",
            calories: 100,
            protein: 2,
            carbs: 10,
            fat: 2,
            source: .manual
        )
        defaults.set(try! JSONEncoder().encode([original]), forKey: FoodStore.storageKey)
        defaults.set(
            try! JSONEncoder().encode([WaterEntry(milliliters: 250)]),
            forKey: WaterSettings.entriesKey
        )
        self.defaults = defaults
        self.originalEntry = original
        self.foodStore = FoodStore(observesExternalChanges: false, defaults: defaults)
        self.waterStore = WaterStore(defaults: defaults)
        foodStore.onEntriesChanged = { [weak self] in self?.changeCallbacks += 1 }
        foodStore.onEntryAdded = { [weak self] _ in self?.successCallbacks += 1 }
        foodStore.onEntryUpdated = { [weak self] _ in self?.successCallbacks += 1 }
        foodStore.onEntryDeleted = { [weak self] _ in self?.successCallbacks += 1 }
    }

    var persistedFoodName: String {
        guard let data = defaults.object(forKey: FoodStore.storageKey) as? Data,
              let entries = try? JSONDecoder().decode([FoodEntry].self, from: data)
        else { return "missing" }
        return entries.first?.name ?? "empty"
    }

    var persistedWaterCount: Int {
        guard let data = defaults.object(forKey: WaterSettings.entriesKey) as? Data,
              let entries = try? JSONDecoder().decode([WaterEntry].self, from: data)
        else { return -1 }
        return entries.count
    }

    var importPreview: DiaryImportPreview {
        var preview = DiaryImportPreview(
            entries: [FoodEntry(name: "Rejected import food", calories: 200, protein: 3, carbs: 20, fat: 3, source: .manual)],
            startDate: .now,
            endDate: .now
        )
        preview.waterEntries = [WaterEntry(milliliters: 500)]
        preview.includesWater = true
        return preview
    }
}

/// `PersistedBlobGuard` sees normal in-memory UserDefaults semantics without
/// writing test fixtures to either the app's real defaults or a persistent suite.
private final class EphemeralFoodStoreDefaults: UserDefaults {
    private var values: [String: Any] = [:]

    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
    override func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    override func synchronize() -> Bool { true }
}

struct FoodStoreRejectionAcceptanceHarness: View {
    private enum Sheet: String, Identifiable {
        case edit
        case importDiary
        var id: String { rawValue }
    }

    @State private var fixture = FoodStoreRejectionFixture()
    @State private var profileStore = ProfileStore()
    @State private var activeSheet: Sheet?

    var body: some View {
        VStack(spacing: 16) {
            Text("FoodStore rejection acceptance")
                .font(.headline)
            Text(fixture.foodStore.entries.first?.name ?? "missing")
                .accessibilityIdentifier("foodStoreAcceptance.memoryFood")
            Text(fixture.persistedFoodName)
                .accessibilityIdentifier("foodStoreAcceptance.persistedFood")
            Text("\(fixture.waterStore.entries.count)")
                .accessibilityIdentifier("foodStoreAcceptance.waterCount")
            Text("\(fixture.persistedWaterCount)")
                .accessibilityIdentifier("foodStoreAcceptance.persistedWaterCount")
            Text("\(fixture.changeCallbacks)")
                .accessibilityIdentifier("foodStoreAcceptance.changeCallbacks")
            Text("\(fixture.successCallbacks)")
                .accessibilityIdentifier("foodStoreAcceptance.successCallbacks")
            Button("Open Edit Food") {
                fixture.foodStore.rejectNextEditOrReplacementWriteForUITesting = true
                activeSheet = .edit
            }
            .accessibilityIdentifier("foodStoreAcceptance.openEdit")
            Button("Open Import Diary") {
                fixture.foodStore.rejectNextEditOrReplacementWriteForUITesting = true
                activeSheet = .importDiary
            }
            .accessibilityIdentifier("foodStoreAcceptance.openImport")
        }
        .padding(24)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .edit:
                EditFoodEntryView(entry: fixture.originalEntry)
                    .environment(fixture.foodStore)
                    .environment(profileStore)
            case .importDiary:
                ImportDiaryView(testingPreview: fixture.importPreview)
                    .environment(fixture.foodStore)
                    .environment(fixture.waterStore)
            }
        }
    }
}
#endif
