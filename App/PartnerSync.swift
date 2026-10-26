import CloudKit
import Core
import SwiftData

/// Syncs the `Partner` zone through `CKSyncEngine`, beside SwiftData (PLAN.md, Sharing plans with a training partner):
/// the owner's engine runs on the private database, scoped to the zone, the partner's on the shared one. It runs on the
/// iPhone and the Mac, off the main actor; the rules for what goes out and how what comes in applies are in Core (`Partner`).
actor PartnerSync: CKSyncEngineDelegate {
    /// The running sync, once the store opened.
    @MainActor static var current: PartnerSync?
    nonisolated static let file = URL.applicationSupportDirectory.appending(path: "Partner.json")

    private let container: ModelContainer
    private var state = PartnerState.load(from: PartnerSync.file)
    private var engine: CKSyncEngine?

    init(container: ModelContainer) {
        self.container = container
    }

    /// Starts syncing `container`'s shared plans, and looks for changes to send after every save.
    @MainActor static func start(_ container: ModelContainer) {
        let sync = PartnerSync(container: container)
        current = sync
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
            Task { await sync.queueOutgoing() }
        }
        Task { await sync.resume() }
    }

    /// The engine, if this device shares plans; then the held changes an update can read now, and what changed while it was off.
    func resume() {
        guard engine == nil, let zone = state.zone else { return }
        let cloud = CKContainer(identifier: Store.cloudKitContainer)
        let database = state.ownerName == nil ? cloud.privateCloudDatabase : cloud.sharedCloudDatabase
        engine = CKSyncEngine(CKSyncEngine.Configuration(database: database, stateSerialization: state.engine, delegate: self))
        if state.ownerName == nil { engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))]) }
        if state.lastSent == .distantPast { state.lastSent = .now } // what came before sharing went with the plan itself
        applyUnapplied()
        queueOutgoing()
    }

    /// Fetches and sends now: a background wake's chance to sync the zone too.
    func sync() async {
        guard let engine, let zone = state.zone else { return }
        try? await engine.fetchChanges(CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([zone])))
        try? await engine.sendChanges()
    }

    /// Queues this person's changes since the last queued; the engine sends them when it can. With all plans shared,
    /// a plan added here joins the zone too.
    func queueOutgoing() {
        guard let engine, let zone = state.zone else { return }
        let context = ModelContext(container)
        let since = state.lastSent
        let own = (try? context.fetch(FetchDescriptor<Action>(predicate: #Predicate { $0.date > since && $0.author == nil }))) ?? []
        guard let newest = own.map(\.date).max() else { return }
        if state.allPlans {
            for action in own {
                guard case let .addPlan(id, _, _)? = action.change, state.shared.insert(id).inserted else { continue }
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(PartnerRecords.plan(id, in: zone).recordID)])
            }
        }
        let changes = (try? PartnerChange.outgoing(container, after: since, shared: state.shared)) ?? []
        for change in changes { state.pending[change.id] = change }
        engine.state.add(pendingRecordZoneChanges: changes.map { .saveRecord(CKRecord.ID(recordName: $0.id.uuidString, zoneID: zone)) })
        state.lastSent = newest
        save()
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            state.engine = update.stateSerialization
        case .fetchedRecordZoneChanges(let fetched):
            receive(fetched.modifications.map(\.record), deleted: fetched.deletions.map(\.recordID))
        case .sentRecordZoneChanges(let sent):
            // A change another of this person's devices already sent is in the zone too.
            let done = sent.savedRecords.map(\.recordID) + sent.failedRecordSaves.filter { $0.error.code == .serverRecordChanged }.map(\.record.recordID)
            for id in done { if let change = UUID(uuidString: id.recordName) { state.pending[change] = nil } }
            let lost = sent.failedRecordSaves.filter { $0.error.code == .zoneNotFound }.map(\.record.recordID)
            if !lost.isEmpty, state.ownerName == nil, let zone = state.zone {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
                syncEngine.state.add(pendingRecordZoneChanges: lost.map { .saveRecord($0) })
            }
        case .fetchedDatabaseChanges(let fetched):
            if fetched.deletions.contains(where: { $0.zoneID == state.zone }) { // sharing stopped, or the partner left
                state = PartnerState()
                engine = nil
            }
        default:
            break
        }
        save()
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let (pending, allPlans) = (state.pending, state.allPlans)
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            if let change = UUID(uuidString: id.recordName).flatMap({ pending[$0] }) { return change.record(in: id.zoneID) }
            if let plan = PartnerRecords.planID(id) { return PartnerRecords.plan(plan, in: id.zoneID) }
            return id.recordName == "settings" ? PartnerRecords.settings(allPlans: allPlans, in: id.zoneID) : nil
        }
    }

    func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        var options = context.options
        if let zone = state.zone { options.scope = .zoneIDs([zone]) } // the private database also holds SwiftData's zones
        return options
    }

    // MARK: Receiving

    private func receive(_ records: [CKRecord], deleted: [CKRecord.ID]) {
        let context = ModelContext(container)
        var changes: [PartnerChange] = []
        for record in records {
            switch record.recordType {
            case PartnerRecords.planType:
                if let plan = PartnerRecords.planID(record.recordID) { state.shared.insert(plan) }
            case PartnerRecords.settingsType:
                state.allPlans = record["allPlans"] as? Int != 0
            case PartnerRecords.changeType where record.creatorUserRecordID?.recordName != CKCurrentUserDefaultName:
                if let change = PartnerChange(record: record) { changes.append(change) } else { hold(record, in: context) }
            default:
                break
            }
        }
        for id in deleted { if let plan = PartnerRecords.planID(id) { state.shared.remove(plan) } }
        context.receive(changes, from: state.partner ?? "")
        try? context.save()
    }

    /// A change from the partner's newer app version: in the log but unapplied, so plan editing waits for an update (`Action.newer`).
    private func hold(_ record: CKRecord, in context: ModelContext) {
        guard let id = UUID(uuidString: record.recordID.recordName), state.unapplied.insert(id).inserted else { return }
        let action = Action()
        (action.id, action.author) = (id, state.partner)
        action.version = record["version"] as? Int ?? Change.version + 1
        action.payload = record["payload"] as? Data ?? Data()
        action.date = record["date"] as? Date ?? .now
        context.insert(action)
    }

    /// After an update: applies the held changes this version can read now.
    private func applyUnapplied() {
        let context = ModelContext(container)
        for id in state.unapplied {
            guard let action = try? context.fetch(FetchDescriptor<Action>(predicate: #Predicate { $0.id == id })).first,
                  action.version <= Change.version, let change = action.change else { continue }
            context.apply(change, by: action.author)
            state.unapplied.remove(id)
        }
        try? context.save()
    }

    private func save() {
        try? state.save(to: Self.file)
    }
}
