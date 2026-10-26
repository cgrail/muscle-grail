import CloudKit
import Core
import SwiftUI

/// Settings → Training partner: share plans with one invite, all of them or the chosen ones, and stop sharing or leave.
struct PartnerSettings: View {
    @State private var allPlans = true
    @State private var stopping = false
    @State private var failure: String?

    var body: some View {
        let status = PartnerStatus.shared
        Section("Training partner") {
            if status.sharing {
                LabeledContent("Shared with", value: status.partner ?? String(localized: "Waiting for them to accept"))
                Toggle("Share all plans", isOn: Binding { status.allPlans } set: { on in Task { await PartnerSync.current?.setAllPlans(on) } })
                Button(status.owner ? "Stop sharing" : "Leave", role: .destructive) { stopping = true }
            } else {
                Picker("Share", selection: $allPlans) {
                    Text("All plans").tag(true)
                    Text("Chosen plans").tag(false)
                }
                ShareLink(item: PlanInvite(allPlans: allPlans), preview: SharePreview("Muscle Grail plans")) {
                    Label("Invite your training partner", systemImage: "person.badge.plus")
                }
            }
            if let failure { Text(verbatim: failure).foregroundStyle(.red) }
        }
        .confirmationDialog("Stop sharing plans?", isPresented: $stopping, titleVisibility: .visible) {
            Button(status.owner ? "Stop sharing" : "Leave", role: .destructive) {
                Task {
                    do { try await PartnerSync.current?.stop() } catch { failure = error.localizedDescription }
                }
            }
        } message: {
            Text("Both of you keep your plans as they are. They just stop changing together.")
        }
    }
}

/// The invite: one zone-wide share, made when the share sheet sends it.
nonisolated struct PlanInvite: Transferable {
    let allPlans: Bool

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invite in
            .prepareShare(container: CKContainer(identifier: Store.cloudKitContainer)) {
                guard let sync = await PartnerSync.current else { throw CKError(.notAuthenticated) }
                return try await sync.share(allPlans: invite.allPlans)
            }
        }
    }
}

/// "Share with <partner>" or "Stop sharing", in a plan's menu while sharing.
struct PlanSharing: View {
    let plan: Plan

    var body: some View {
        let (status, id) = (PartnerStatus.shared, plan.id)
        if status.sharing {
            if status.plans.contains(id) {
                Button("Stop sharing", systemImage: "person.2.slash") { Task { await PartnerSync.current?.unshare(id) } }
            } else {
                Button("Share with \(status.partner ?? String(localized: "your training partner"))", systemImage: "person.2") {
                    Task { await PartnerSync.current?.share([id]) }
                }
            }
        }
    }
}

/// Marks a shared plan.
struct SharedBadge: View {
    let plan: Plan

    var body: some View {
        if PartnerStatus.shared.plans.contains(plan.id) {
            Image(systemName: "person.2.fill").foregroundStyle(.secondary).accessibilityLabel("Shared")
        }
    }
}
