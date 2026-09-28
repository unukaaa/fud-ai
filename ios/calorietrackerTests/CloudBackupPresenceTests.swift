import Foundation
import Testing
@testable import calorietracker

@MainActor
struct CloudBackupPresenceTests {
    @Test func confirmedPresenceRemainsPresent() async throws {
        let backup = CloudBackupService()
        try await backup.refreshCloudPresence(using: { true })
        #expect(backup.hasCloudBackup)
    }

    @Test func confirmedAbsenceRemainsAbsent() async throws {
        let backup = CloudBackupService()
        backup.hasCloudBackup = true
        try await backup.refreshCloudPresence(using: { false })
        #expect(!backup.hasCloudBackup)
    }

    @Test func failedLookupDoesNotBecomeConfirmedAbsence() async {
        let backup = CloudBackupService()
        backup.hasCloudBackup = true
        var receivedFailure = false
        do {
            try await backup.refreshCloudPresence(using: { throw LookupFailure.failed })
        } catch {
            receivedFailure = true
        }
        #expect(receivedFailure)
        #expect(backup.hasCloudBackup)
    }

    private enum LookupFailure: Error { case failed }
}
