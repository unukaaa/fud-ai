import Foundation
import Testing
@testable import calorietracker

@Suite(.serialized)
@MainActor
struct WeightStoreGoalNotificationTests {
    @Test func chronologicalLossCrossingNotifies() throws {
        let count = try notificationCount(
            goal: .lose, target: 75,
            existing: [entry(day: 1, weight: 80)],
            added: entry(day: 2, weight: 74)
        )
        #expect(count == 1)
    }

    @Test func chronologicalLossWithoutCrossingDoesNotNotify() throws {
        let count = try notificationCount(
            goal: .lose, target: 75,
            existing: [entry(day: 1, weight: 80)],
            added: entry(day: 2, weight: 78)
        )
        #expect(count == 0)
    }

    @Test func backdatedLossCrossingDoesNotNotify() throws {
        let count = try notificationCount(
            goal: .lose, target: 75,
            existing: [entry(day: 2, weight: 80)],
            added: entry(day: 1, weight: 74)
        )
        #expect(count == 0)
    }

    @Test func historicalInsertionDoesNotReplaceLatestTransition() throws {
        let count = try notificationCount(
            goal: .lose, target: 75,
            existing: [entry(day: 1, weight: 80), entry(day: 3, weight: 74)],
            added: entry(day: 2, weight: 76)
        )
        #expect(count == 0)
    }

    @Test func chronologicalGainCrossingNotifies() throws {
        let count = try notificationCount(
            goal: .gain, target: 65,
            existing: [entry(day: 1, weight: 60)],
            added: entry(day: 2, weight: 66)
        )
        #expect(count == 1)
    }

    @Test func backdatedGainCrossingDoesNotNotify() throws {
        let count = try notificationCount(
            goal: .gain, target: 65,
            existing: [entry(day: 2, weight: 60)],
            added: entry(day: 1, weight: 66)
        )
        #expect(count == 0)
    }

    private func entry(day: TimeInterval, weight: Double) -> WeightEntry {
        WeightEntry(date: Date(timeIntervalSince1970: day * 86_400), weightKg: weight)
    }

    private func notificationCount(
        goal: WeightGoal,
        target: Double,
        existing: [WeightEntry],
        added: WeightEntry
    ) throws -> Int {
        let defaults = UserDefaults.standard
        let originalProfile = defaults.object(forKey: UserProfile.storageKey)
        defer {
            if let originalProfile {
                defaults.set(originalProfile, forKey: UserProfile.storageKey)
            } else {
                defaults.removeObject(forKey: UserProfile.storageKey)
            }
        }

        var profile = UserProfile.default
        profile.goal = goal
        profile.goalWeightKg = target
        defaults.set(try JSONEncoder().encode(profile), forKey: UserProfile.storageKey)

        let suiteName = "WeightStoreGoalNotificationTests.\(UUID().uuidString)"
        let storeDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { storeDefaults.removePersistentDomain(forName: suiteName) }
        let store = WeightStore(observesExternalChanges: false, defaults: storeDefaults)
        store.replaceAllEntries(existing)

        let counter = NotificationCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .weightGoalReached,
            object: nil,
            queue: nil
        ) { _ in counter.increment() }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.addEntry(added)
        return counter.value
    }
}

private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
