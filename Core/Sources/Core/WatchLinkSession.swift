#if os(iOS) || os(watchOS)
import CoreData
import Foundation
import SwiftData
import WatchConnectivity

/// Hands training changes between the iPhone and the watch through `WCSession`, over Bluetooth or the Wi-Fi between
/// them, with no internet. `transferUserInfo` queues them in order and delivers them once the other app runs, also after
/// either was killed. A watch without plans asks the iPhone for what it needs to train with `sendMessage`, which wakes the
/// iPhone app. iCloud still carries everything; this only gets there first. A thin wrapper, like `Health`: what goes
/// out, how it applies and how the copies go are in `WatchLink.swift`, with tests. It all runs in order on a queue of its own.
public final class WatchLinkSession: NSObject, WCSessionDelegate, Sendable {
    /// The running link, once the store opened: the session holds its delegate weakly.
    @MainActor public private(set) static var current: WatchLinkSession?
    /// Whether the watch shows a plan, which its app says. A plan's copy stays until then: a view can't lose its plan.
    @MainActor public static var planOpen = false {
        didSet { if !planOpen { current?.drop() } }
    }

    /// The stores whose last iCloud import finished, with none running: only then is what it brought whole.
    @MainActor private static var imported: Set<String> = []
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
        _ = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import else { return }
            let (store, done) = (event.storeIdentifier, event.endDate != nil && event.succeeded)
            MainActor.assumeIsolated {
                if done { Self.imported.insert(store) } else { Self.imported.remove(store) }
                if done { link.drop() }
            }
        }
        link.drop()
    }

    /// Drops the copies whose originals came. The plans' wait for their store's import, and while a plan is open.
    @MainActor private func drop() {
        let imported = Self.planOpen ? [] : Self.imported
        // shortcut: a plan opened in the instant its copy goes still loses it; delete on the main context if that ever shows.
        queue.async { self.dropCopies(plansOf: imported) }
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
        queue.async {
            self.send() // what was saved before the session was up
            self.askForStart()
        }
    }

    /// The iPhone came into reach: a watch still without plans asks again.
    public func sessionReachabilityDidChange(_ session: WCSession) {
        queue.async { self.askForStart() }
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let changes = (userInfo["changes"] as? [Data] ?? []).compactMap { try? JSONDecoder().decode(LinkedChange.self, from: $0) }
        queue.async { self.receive(changes) }
    }

    #if os(iOS)
    /// A watch without plans asks for what it needs to train (`askForStart`). Packed, to stay under a message's size limit.
    public func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let reply = replyHandler // WatchConnectivity allows calling it from any thread
        queue.async {
            let start = try? JSONEncoder().encode(ModelContext(self.container).linkedStart())
            reply(["start": start.flatMap { try? ($0 as NSData).compressed(using: .zlib) as Data } ?? Data()])
        }
    }

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

    /// A watch without plans asks the iPhone for what it needs to train (`linkedStart`): iCloud brings everything in its
    /// own order and takes minutes on a new watch. Out of reach, or with too much to fit a message, iCloud brings it all the same.
    private func askForStart() {
        #if os(watchOS)
        guard WCSession.default.isReachable, (try? ModelContext(container).fetchCount(FetchDescriptor<Plan>())) == 0 else { return }
        // shortcut: one message, whose size WatchConnectivity caps (reportedly 64 KB): packed, dozens of plans fit; hand over a file past that.
        WCSession.default.sendMessage(["start": true], replyHandler: { reply in
            guard let packed = reply["start"] as? Data, let data = try? (packed as NSData).decompressed(using: .zlib) as Data,
                  let changes = try? JSONDecoder().decode([Change].self, from: data) else { return }
            self.queue.async {
                guard let made = try? ModelContext(self.container).receiveStart(changes), !made.isEmpty else { return }
                self.copies += made
            }
        }, errorHandler: nil)
        #endif
    }

    private func dropCopies(plansOf imported: Set<String>) {
        guard !copies.isEmpty, let waiting = try? ModelContext(container).dropCopies(copies, plansOf: imported) else { return }
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
