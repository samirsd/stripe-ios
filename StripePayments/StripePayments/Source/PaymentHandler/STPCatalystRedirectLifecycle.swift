// Carnyx Catalyst patch to Stripe iOS 26.12.0. See CARNYX_CATALYST_PATCH.md.
#if targetEnvironment(macCatalyst) || os(macOS)
import Foundation

/// Owns one external redirect's notification lifetime. All calls and observer
/// deliveries are on the main queue; the SDK's intent retrieval remains authoritative.
final class STPCatalystRedirectLifecycle {
    enum OpenResult { case opened, fallback, stale }
    enum CallbackClaim { case claimed, alreadyConsumed, unmanaged }
    private struct Pending {
        let token: UUID
        let action: ObjectIdentifier
        let isCurrent: () -> Bool
        let onReturn: () -> Void
        var opened = false
        var returnedWhileOpening = false
        var consumed = false
    }
    private let center: NotificationCenter
    private let returnNotifications: [Notification.Name]
    private var observers: [NSObjectProtocol] = []
    private var pending: Pending?
    private var traceGeneration = 0

    init(center: NotificationCenter = .default, returnNotifications: [Notification.Name]) {
        self.center = center
        self.returnNotifications = returnNotifications
    }

    deinit { removeObservers() }

    func begin(action: AnyObject, isCurrent: @escaping () -> Bool, onReturn: @escaping () -> Void) -> UUID {
        reset()
        let token = UUID()
        traceGeneration &+= 1
        pending = Pending(token: token, action: ObjectIdentifier(action), isCurrent: isCurrent, onReturn: onReturn)
        trace(.begin)
        // Observe before open so a fast return preceding its completion is not lost.
        observers = returnNotifications.enumerated().map { index, name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.trace(.notification, values: ["source": index + 1])
                self?.returned(token: token)
            }
        }
        return token
    }

    func opened(_ success: Bool, token: UUID, action: AnyObject) -> OpenResult {
        trace(.openResult, values: ["success": success ? 1 : 0,
            "tokenMatches": pending?.token == token ? 1 : 0,
            "actionMatches": pending?.action == ObjectIdentifier(action) ? 1 : 0])
        guard var state = pending, state.token == token,
              state.action == ObjectIdentifier(action), state.isCurrent(), !state.consumed else { return .stale }
        guard success else { reset(); return .fallback }
        state.opened = true
        pending = state
        return .opened
    }

    /// Call after the SDK records successful open/presentation completion.
    func reconcileBufferedReturn(token: UUID) {
        guard let state = pending, state.token == token, state.returnedWhileOpening else { return }
        returned(token: token)
    }

    func claimCallback(action: AnyObject) -> CallbackClaim {
        trace(.callbackClaim, values: ["actionMatches": pending?.action == ObjectIdentifier(action) ? 1 : 0])
        guard let state = pending else { return .unmanaged }
        guard state.action == ObjectIdentifier(action), state.isCurrent(), !state.consumed else { return .alreadyConsumed }
        consume()
        return .claimed
    }

    func reset() {
        trace(.reset)
        removeObservers()
        pending = nil
    }

    private func returned(token: UUID) {
        trace(.returnAttempt, values: ["tokenMatches": pending?.token == token ? 1 : 0])
        guard var state = pending, state.token == token, state.isCurrent(), !state.consumed else { return }
        guard state.opened else {
            trace(.bufferedReturn)
            state.returnedWhileOpening = true
            pending = state
            return
        }
        consume()
        state.onReturn()
    }

    private func consume() {
        trace(.consumed)
        pending?.consumed = true
        // Retain the consumed generation until reset, rejecting queued callbacks.
        removeObservers()
    }

    private func trace(_ event: STPCatalystRedirectTrace.Event, values: [String: Int] = [:]) {
        guard STPCatalystRedirectTrace.enabled else { return }
        var values = values
        values["generation"] = traceGeneration
        values["phase"] = pending.map { $0.consumed ? 3 : ($0.opened ? 2 : 1) } ?? 0
        values["current"] = pending?.isCurrent() == true ? 1 : 0
        values["observerCount"] = observers.count
        STPCatalystRedirectTrace.record(event, values: values)
    }

    private func removeObservers() {
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
}
/// Temporary exact-QA diagnostics: typed numeric fields only, no URLs, intent IDs,
/// account details, client secrets or arbitrary error text. Never changes a decision.
enum STPCatalystRedirectTrace {
    enum Event: Int {
        case begin = 1, notification, openResult, callbackClaim, reset, returnAttempt, bufferedReturn, consumed
        case handlerBegin = 20, handlerReset, redirectEntered, externalOpenCompleted, safariFallback, safariPresented, webAuthFallback
        case canonicalReadStarted = 30, canonicalReadResult, handlingChanged, actionChanged, canonicalCompletion
        case sceneActivated = 40, sceneDeactivated, appActivated, appResigned, appForegrounded
    }
    static var enabled: Bool {
        Bundle.main.bundleIdentifier == "com.s2.carnyx.billingqa" &&
            Bundle.main.object(forInfoDictionaryKey: "CarnyxBillingQA") as? Bool == true
    }
    private static let lock = NSLock()

    static func record(_ event: Event, values: [String: Int] = [:]) {
        guard enabled else { return }
        var sample: [String: Any] = values
        sample["event"] = event.rawValue
        sample["time"] = Date().timeIntervalSince1970
        sample["process"] = ProcessInfo.processInfo.processIdentifier
        sample["mainThread"] = Thread.isMainThread
        guard var line = try? JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys]),
              let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        line.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        let fileURL = directory.appendingPathComponent("billing-qa-stripe-lifecycle.jsonl")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let file = try FileHandle(forWritingTo: fileURL)
            defer { try? file.close() }
            guard try file.seekToEnd() < 256_000 else { return }
            try file.write(contentsOf: line)
        } catch { /* QA observation must not affect authentication. */ }
    }
}
#endif
