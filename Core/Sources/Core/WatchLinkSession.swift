#if os(iOS) || os(watchOS)
import CoreData
import Foundation
import SwiftData
import WatchConnectivity

/// Hands training changes between the iPhone and the watch through `WCSession`, over Bluetooth or the Wi-Fi between
/// them, with no internet. `transferUserInfo` queues them in order and delivers them once the other app runs, also after
/// either was killed. iCloud still carries everything; this only gets there first. A thin wrapper, like `Health`: what goes
/// out, how it applies and how the copies go are in `WatchLink.swift`, with tests. It all runs in order on a queue of its own.
public final class WatchLinkSession: NSObject, WCSessionDelegate, Sendable {
    /// The running link, once the store opened: the session holds its delegate weakly.
    @MainActor public private(set) static var current: WatchLinkSession?
    private let container: ModelContainer
    private let queue = DispatchQueue(label: "WatchLinkSession")

    private init(container: ModelContainer) {
        self.container = container
    }

    /// Starts handing over `container`'s training changes, on an iPhone or a watch. After each save it sends what's new,
    /// and after each iCloud import it drops the copies whose originals came.
    @MainActor public static func start(_ container: ModelContainer) {
        guard current == nil, WCSession.isSupported() else { return }
        let link = WatchLinkSession(container: container)
        current = link
        if UserDefaults.standard.object(forKey: "linkSent") == nil {
            UserDefaults.standard.set(Date.now, forKey: "linkSent") // what came before goes through iCloud
        }
        WCSession.default.delegate = link
        WCSession.default.activate()
        _ = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { _ in
            link.queue.async { link.send() }
        }
        _ = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil, event.succeeded else { return }
            link.queue.async { link.dropCopies() }
        }
        link.queue.async { link.dropCopies() }
    }

    /// Holds a background wake open until what the other device sent is in the store: the watch's `.watchConnectivity` task.
    public func settle() async {
        let deadline = ContinuousClock.now + .seconds(10)
        while WCSession.default.activationState != .activated || WCSession.default.hasContentPending, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        await withCheckedContinuation { done in queue.async { done.resume() } }
    }

    // MARK: WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        queue.async { self.send() } // what was saved before the session was up
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let changes = (userInfo["changes"] as? [Data] ?? []).compactMap { try? JSONDecoder().decode(LinkedChange.self, from: $0) }
        queue.async { self.receive(changes) }
    }

    #if os(iOS)
    public func sessionDidBecomeInactive(_ session: WCSession) {}

    /// After the user switched to another watch: the session starts again, for that one.
    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    // MARK: On the queue

    /// Sends the training changes recorded here since the last send. Without the other app installed they go through iCloud only.
    private func send() {
        let session = WCSession.default
        guard session.activationState == .activated, let since = UserDefaults.standard.object(forKey: "linkSent") as? Date else { return }
        let skipping = Set(copies.filter { $0.kind == .action }.map(\.id))
        guard let changes = try? ModelContext(container).linkOutgoing(after: since, skipping: skipping), let newest = changes.last else { return }
        if session.hasCounterpart {
            session.transferUserInfo(["changes": changes.compactMap { try? JSONEncoder().encode($0) }])
        }
        UserDefaults.standard.set(newest.date, forKey: "linkSent")
    }

    private func receive(_ changes: [LinkedChange]) {
        guard let made = try? ModelContext(container).receiveLinked(changes), !made.isEmpty else { return }
        copies += made
    }

    private func dropCopies() {
        guard !copies.isEmpty, let waiting = try? ModelContext(container).dropCopies(copies) else { return }
        copies = waiting
    }

    /// The copies the link made here that wait for their originals. Outlasts a relaunch, since the originals come later through iCloud.
    private var copies: [LinkCopy] {
        get { UserDefaults.standard.data(forKey: "linkCopies").flatMap { try? JSONDecoder().decode([LinkCopy].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "linkCopies") }
    }
}

private extension WCSession {
    /// Whether the other app is there to receive: the watch app on a paired watch, or the iPhone app.
    var hasCounterpart: Bool {
        #if os(iOS)
        return isPaired && isWatchAppInstalled
        #else
        return isCompanionAppInstalled
        #endif
    }
}
#endif
