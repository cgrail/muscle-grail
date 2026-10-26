import CloudKit
import Foundation

/// The shared zone's records (PLAN.md, Sharing plans with a training partner): one per change, one per shared plan, and the settings.
public enum PartnerRecords {
    public static let zoneName = "Partner"
    public static let changeType = "SharedChange", planType = "SharedPlan", settingsType = "PartnerSettings"

    /// A shared plan's record, named by the plan's id.
    public static func plan(_ id: UUID, in zone: CKRecordZone.ID) -> CKRecord {
        CKRecord(recordType: planType, recordID: CKRecord.ID(recordName: "plan-\(id.uuidString)", zoneID: zone))
    }

    /// The plan a shared plan's record is for.
    public static func planID(_ id: CKRecord.ID) -> UUID? {
        id.recordName.hasPrefix("plan-") ? UUID(uuidString: String(id.recordName.dropFirst(5))) : nil
    }

    /// The settings: all plans, or the chosen ones.
    public static func settings(allPlans: Bool, in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: settingsType, recordID: CKRecord.ID(recordName: "settings", zoneID: zone))
        record["allPlans"] = allPlans ? 1 : 0
        return record
    }
}

public extension PartnerChange {
    /// The change as a record of `zone`, named by its id.
    func record(in zone: CKRecordZone.ID) -> CKRecord {
        let record = CKRecord(recordType: PartnerRecords.changeType, recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zone))
        record["payload"] = (try? JSONEncoder().encode(change)) ?? Data()
        record["version"] = Change.version
        record["date"] = date
        record["batch"] = batch?.uuidString
        record["sets"] = sets
        record["reps"] = reps
        record["name"] = name
        return record
    }

    /// The change a record holds. Nil for another kind of record, or one from a newer app version: it waits for an update.
    init?(record: CKRecord) {
        guard record.recordType == PartnerRecords.changeType, (record["version"] as? Int ?? 1) <= Change.version,
              let id = UUID(uuidString: record.recordID.recordName), let date = record["date"] as? Date,
              let payload = record["payload"] as? Data, let change = try? JSONDecoder().decode(Change.self, from: payload) else { return nil }
        self.init(id: id, date: date, change: change, batch: (record["batch"] as? String).flatMap(UUID.init(uuidString:)),
                  sets: record["sets"] as? Int, reps: record["reps"] as? Int, name: record["name"] as? String)
    }
}

/// What a device knows of sharing, in a file: so the question works offline, and the engine goes on where it stopped.
public struct PartnerState: Codable {
    /// Nil while this device shares nothing.
    public var zoneName: String?
    /// The zone's owner, the partner's user record name; nil for this person's own zone.
    public var ownerName: String?
    public var allPlans = true
    public var shared: Set<UUID> = []
    /// The partner's name, from the share.
    public var partner: String?
    /// The date of the newest change of this person's that was queued, and the queued ones the zone doesn't have yet.
    public var lastSent = Date.distantPast
    public var pending: [UUID: PartnerChange] = [:]
    /// Changes from the partner's newer app version: in the log, unapplied, until an update can read them.
    public var unapplied: Set<UUID> = []
    public var engine: CKSyncEngine.State.Serialization?

    public init() {}

    public var zone: CKRecordZone.ID? {
        zoneName.map { CKRecordZone.ID(zoneName: $0, ownerName: ownerName ?? CKCurrentUserDefaultName) }
    }

    /// The state saved in `file`; a missing or unreadable one shares nothing.
    public static func load(from file: URL) -> PartnerState {
        (try? JSONDecoder().decode(PartnerState.self, from: Data(contentsOf: file))) ?? PartnerState()
    }

    public func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
}
