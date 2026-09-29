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

    init(center: NotificationCenter = .default, returnNotifications: [Notification.Name]) {
        self.center = center
        self.returnNotifications = returnNotifications
    }

    deinit { removeObservers() }

    func begin(action: AnyObject, isCurrent: @escaping () -> Bool, onReturn: @escaping () -> Void) -> UUID {
        reset()
        let token = UUID()
        pending = Pending(token: token, action: ObjectIdentifier(action), isCurrent: isCurrent, onReturn: onReturn)
        // Observe before open so a fast return preceding its completion is not lost.
        observers = returnNotifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.returned(token: token)
            }
        }
        return token
    }

    func opened(_ success: Bool, token: UUID, action: AnyObject) -> OpenResult {
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
        guard let state = pending else { return .unmanaged }
        guard state.action == ObjectIdentifier(action), state.isCurrent(), !state.consumed else { return .alreadyConsumed }
        consume()
        return .claimed
    }

    func reset() {
        removeObservers()
        pending = nil
    }

    private func returned(token: UUID) {
        guard var state = pending, state.token == token, state.isCurrent(), !state.consumed else { return }
        guard state.opened else {
            state.returnedWhileOpening = true
            pending = state
            return
        }
        consume()
        state.onReturn()
    }

    private func consume() {
        pending?.consumed = true
        // Retain the consumed generation until reset, rejecting queued callbacks.
        removeObservers()
    }

    private func removeObservers() {
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
    }
}
#endif
