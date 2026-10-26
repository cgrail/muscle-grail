import Core
import SwiftUI

/// "Me and <partner>" or "Only me", asked before adding, removing, replacing or moving an exercise for both in a shared plan,
/// unless Settings → Training partner says always both. That choice is in iCloud's key-value store, so all of a person's
/// devices follow it.
enum ForWhom {
    static let alwaysBoth = "partnerAlwaysBoth"

    /// Runs `edit` for both right away, or asks first, through `pending`.
    static func edit(_ plan: Plan?, _ item: PlanItem? = nil, asking pending: Binding<PendingEdit?>, _ edit: @escaping (_ forBoth: Bool) -> Void) {
        guard let plan, PartnerStatus.shared.plans.contains(plan.id), (item?.ownedBy ?? .both) == .both,
              !NSUbiquitousKeyValueStore.default.bool(forKey: alwaysBoth) else { return edit(true) }
        pending.wrappedValue = PendingEdit(run: edit)
    }
}

/// An edit waiting for the answer.
struct PendingEdit {
    let run: (_ forBoth: Bool) -> Void
}

extension View {
    /// Asks for whom, while `pending` holds an edit.
    func forWhom(_ pending: Binding<PendingEdit?>) -> some View {
        let partner = PartnerStatus.shared.partner
        return confirmationDialog("For whom?", isPresented: Binding { pending.wrappedValue != nil } set: { if !$0 { pending.wrappedValue = nil } },
                                  titleVisibility: .visible, presenting: pending.wrappedValue) { edit in
            Button { edit.run(true) } label: {
                if let partner { Text("Me and \(partner)") } else { Text("Me and my training partner") }
            }
            Button("Only me") { edit.run(false) }
        }
    }
}

/// Whose own an exercise of a shared plan is: "Only you", or "Only <partner>" for theirs, which training skips here.
struct OwnerNote: View {
    let item: PlanItem

    var body: some View {
        switch item.ownedBy {
        case .both: EmptyView()
        case .me: Text("Only you").font(.caption).foregroundStyle(.secondary)
        case .partner:
            if let partner = PartnerStatus.shared.partner {
                Text("Only \(partner)").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Only my training partner").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Settings → Training partner: whether changes to shared exercises ask, or are always for both.
struct AlwaysBothPicker: View {
    @State private var alwaysBoth = NSUbiquitousKeyValueStore.default.bool(forKey: ForWhom.alwaysBoth)

    var body: some View {
        Picker("Changes to shared exercises", selection: $alwaysBoth) {
            Text("Ask each time").tag(false)
            Text("Always both").tag(true)
        }
        .onChange(of: alwaysBoth) { NSUbiquitousKeyValueStore.default.set(alwaysBoth, forKey: ForWhom.alwaysBoth) }
    }
}
