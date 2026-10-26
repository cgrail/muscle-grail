import CloudKit
import Foundation
import Testing
@testable import Core

struct PartnerRecordsTests {
    let zone = CKRecordZone.ID(zoneName: PartnerRecords.zoneName, ownerName: CKCurrentUserDefaultName)
    let change = PartnerChange(id: UUID(), date: Date(timeIntervalSinceReferenceDate: 800_000_000), change: .renamePlan(id: UUID(), name: "Push"),
                               batch: UUID(), sets: 4, reps: 8, name: "Cable Fly")

    @Test func aChangeSurvivesItsRecord() {
        #expect(PartnerChange(record: change.record(in: zone)) == change)
    }

    @Test func aChangeFromANewerVersionWaits() {
        let record = change.record(in: zone)
        record["version"] = Change.version + 1
        #expect(PartnerChange(record: record) == nil)
    }

    @Test func aSharedPlansRecordNamesItsPlan() {
        let plan = UUID()
        #expect(PartnerRecords.planID(PartnerRecords.plan(plan, in: zone).recordID) == plan)
    }

    @Test func theSettingsSayWhetherAllPlansAreShared() {
        #expect(PartnerRecords.settings(allPlans: false, in: zone)["allPlans"] as? Int == 0)
    }

    @Test func theStateSurvivesItsFile() throws {
        let file = URL.temporaryDirectory.appending(path: "\(UUID())/Partner.json")
        var state = PartnerState()
        (state.zoneName, state.shared, state.pending) = (PartnerRecords.zoneName, [UUID()], [change.id: change])
        try state.save(to: file)
        let loaded = PartnerState.load(from: file)
        #expect(loaded.zone == zone && loaded.shared == state.shared && loaded.pending == state.pending)
    }

    @Test func withoutAFileNothingIsShared() {
        #expect(PartnerState.load(from: URL.temporaryDirectory.appending(path: "\(UUID()).json")).zone == nil)
    }
}
