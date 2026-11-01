import CloudKit
import Core
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Settings → Training partner: share plans with one invite, all of them or the chosen ones, sync them now, and stop sharing or leave.
struct PartnerSettings: View {
    @State private var allPlans = true
    @State private var stopping = false
    @State private var syncing = false
    @State private var inviting = false
    @State private var failure: String?

    var body: some View {
        let status = PartnerStatus.shared
        Section("Training partner") {
            if status.sharing {
                LabeledContent("Shared with", value: status.partner ?? String(localized: "Waiting for them to accept"))
                if status.owner, status.partner == nil { invite } // sends the invite again, after the share sheet was closed
                Toggle("Share all plans", isOn: Binding { status.allPlans } set: { on in Task { await PartnerSync.current?.setAllPlans(on) } })
                AlwaysBothPicker()
                Button("Sync now", systemImage: "arrow.triangle.2.circlepath") {
                    syncing = true
                    Task {
                        await PartnerSync.current?.sync()
                        syncing = false
                    }
                }
                .disabled(syncing)
                Button(status.owner ? "Stop sharing" : "Leave", role: .destructive) { stopping = true }
            } else {
                Picker("Share", selection: $allPlans) {
                    Text("All plans").tag(true)
                    Text("Chosen plans").tag(false)
                }
                invite
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

    /// Makes the share first, so a failure shows here, then opens the share sheet with it.
    private var invite: some View {
        Button("Invite your training partner", systemImage: "person.badge.plus") {
            inviting = true
            Task {
                do {
                    guard let sync = PartnerSync.current else { throw CKError(.notAuthenticated) }
                    PlanInvite.present(try await sync.share(allPlans: allPlans))
                    failure = nil
                } catch {
                    failure = error.localizedDescription
                }
                inviting = false
            }
        }
        .disabled(inviting)
    }
}

/// The invite to the zone-wide share, in the system's share sheet. UIKit and AppKit present it, not a `ShareLink`: the
/// settings switch to "Waiting for them to accept" once the share exists, and that must not close the sheet.
enum PlanInvite {
    #if os(macOS)
    private static var picker: NSSharingServicePicker?
    #endif

    static func present(_ share: CKShare) {
        let invite = NSItemProvider()
        invite.registerCKShare(share, container: CKContainer(identifier: Store.cloudKitContainer))
        #if os(iOS)
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        guard var top = window?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [invite]))
        if let popover = sheet.popoverPresentationController { // iPad
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
        #else
        guard let view = NSApp.keyWindow?.contentView else { return }
        picker = NSSharingServicePicker(items: [invite])
        picker?.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
        #endif
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
