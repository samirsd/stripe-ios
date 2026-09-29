import Foundation
import AppKit
import XCTest
@testable import CatalystRedirectLifecycle

final class STPCatalystRedirectLifecycleTests: XCTestCase {
    private let active = Notification.Name("test.didBecomeActive")
    private let foreground = Notification.Name("test.willEnterForeground")
    private let nativeActive = STPCatalystRedirectLifecycle.nativeApplicationDidBecomeActive

    private func onMain(_ body: () throws -> Void) rethrows {
        if Thread.isMainThread { try body() }
        else { try DispatchQueue.main.sync(execute: body) }
    }

    private func make(_ center: NotificationCenter) -> STPCatalystRedirectLifecycle {
        STPCatalystRedirectLifecycle(center: center, returnNotifications: [active, foreground, nativeActive])
    }


    func testNativeNotificationNameMatchesPublicAppKitConstant() {
        XCTAssertEqual(nativeActive, NSApplication.didBecomeActiveNotification)
    }

    func testNativeActivationRecoversWhileUIKitRemainsActive() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .opened)
            // No UIKit app or scene notification is required for a native return.
            center.post(name: nativeActive, object: NSObject())
            XCTAssertEqual(returns, 1)
            XCTAssertEqual(center.liveCount, 0)
            XCTAssertEqual(lifecycle.claimCallback(action: action), .alreadyConsumed)
        }
    }

    func testAllThreeNotificationOrdersReconcileExactlyOnce() throws {
        try onMain {
            let orders = [[nativeActive, active, foreground], [nativeActive, foreground, active],
                          [active, nativeActive, foreground], [foreground, nativeActive, active],
                          [active, foreground, nativeActive], [foreground, active, nativeActive]]
            for names in orders {
                let center = TrackingNotificationCenter(), action = NSObject()
                let lifecycle = make(center)
                var returns = 0
                let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
                XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .opened)
                names.forEach { center.post(name: $0, object: nil) }
                XCTAssertEqual(returns, 1)
                XCTAssertEqual(center.liveCount, 0)
            }
        }
    }

    func testNativeActivationBeforeOpenIsBufferedAndCallbackCannotRearm() throws {
        try onMain {
            for callbackWins in [false, true] {
                let center = TrackingNotificationCenter(), action = NSObject()
                let lifecycle = make(center)
                var returns = 0
                let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
                center.post(name: nativeActive, object: nil)
                XCTAssertEqual(returns, 0)
                if callbackWins { XCTAssertEqual(lifecycle.claimCallback(action: action), .claimed) }
                XCTAssertEqual(lifecycle.opened(true, token: token, action: action), callbackWins ? .stale : .opened)
                lifecycle.reconcileBufferedReturn(token: token)
                center.post(name: nativeActive, object: nil)
                center.post(name: active, object: nil)
                XCTAssertEqual(returns, callbackWins ? 0 : 1)
                XCTAssertEqual(center.liveCount, 0)
            }
        }
    }

    func testNativeActivationAfterFailedOpenOrResetDoesNotRetrieve() throws {
        try onMain {
            for failsOpen in [false, true] {
                let center = TrackingNotificationCenter(), action = NSObject()
                let lifecycle = make(center)
                var returns = 0
                let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
                if failsOpen { XCTAssertEqual(lifecycle.opened(false, token: token, action: action), .fallback) }
                else { lifecycle.reset() }
                center.post(name: nativeActive, object: nil)
                XCTAssertEqual(returns, 0)
                XCTAssertEqual(center.liveCount, 0)
                XCTAssertEqual(lifecycle.claimCallback(action: action), .unmanaged)
            }
        }
    }

    func testActivationAfterOpenClaimsOneReturn() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .opened)
            center.post(name: active, object: nil)
            center.post(name: active, object: nil)
            center.post(name: foreground, object: nil)
            XCTAssertEqual(returns, 1)
            XCTAssertEqual(center.liveCount, 0)
            XCTAssertEqual(lifecycle.claimCallback(action: action), .alreadyConsumed)
        }
    }

    func testBothNotificationOrdersAreOneShot() throws {
        try onMain {
            for names in [[active, foreground], [foreground, active]] {
                let center = TrackingNotificationCenter(), action = NSObject()
                let lifecycle = make(center)
                var returns = 0
                let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
                XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .opened)
                names.forEach { center.post(name: $0, object: nil) }
                XCTAssertEqual(returns, 1)
                XCTAssertEqual(center.liveCount, 0)
            }
        }
    }

    func testEarlyActivationWaitsForSuccessfulOpen() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            center.post(name: active, object: nil)
            center.post(name: foreground, object: nil)
            XCTAssertEqual(returns, 0)
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .opened)
            XCTAssertEqual(returns, 0, "Presentation completion must precede buffered retrieval")
            lifecycle.reconcileBufferedReturn(token: token)
            lifecycle.reconcileBufferedReturn(token: token)
            XCTAssertEqual(returns, 1)
            XCTAssertEqual(center.liveCount, 0)
        }
    }

    func testCallbackBeforeOpenResultPreventsRearm() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            center.post(name: active, object: nil)
            XCTAssertEqual(lifecycle.claimCallback(action: action), .claimed)
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .stale)
            lifecycle.reconcileBufferedReturn(token: token)
            center.post(name: foreground, object: nil)
            XCTAssertEqual(returns, 0, "Real callback owns canonical retrieval")
            XCTAssertEqual(center.liveCount, 0)
            XCTAssertEqual(lifecycle.claimCallback(action: action), .alreadyConsumed)
        }
    }

    func testCallbackAfterOpenWinsBeforeNotifications() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .opened)
            XCTAssertEqual(lifecycle.claimCallback(action: action), .claimed)
            center.post(name: active, object: nil)
            center.post(name: foreground, object: nil)
            XCTAssertEqual(returns, 0)
            XCTAssertEqual(center.liveCount, 0)
        }
    }

    func testReentrantReturnAndCallbackCannotStartSecondRetrieval() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: {
                returns += 1
                XCTAssertEqual(lifecycle.claimCallback(action: action), .alreadyConsumed)
                center.post(name: self.foreground, object: nil)
                center.post(name: self.active, object: nil)
            })
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .opened)
            center.post(name: active, object: nil)
            XCTAssertEqual(returns, 1)
            lifecycle.reset()
        }
    }

    func testFailedOpenDisarmsEvenAfterBufferedActivationAndAllowsFallback() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            center.post(name: active, object: nil)
            XCTAssertEqual(lifecycle.opened(false, token: token, action: action), .fallback)
            lifecycle.reconcileBufferedReturn(token: token)
            center.post(name: active, object: nil)
            XCTAssertEqual(returns, 0)
            XCTAssertEqual(center.liveCount, 0)
            XCTAssertEqual(lifecycle.claimCallback(action: action), .unmanaged)
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .stale)
        }
    }

    func testResetInvalidatesDelayedOpenAndRemovesObservers() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            lifecycle.reset()
            lifecycle.reset()
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .stale)
            center.post(name: active, object: nil)
            XCTAssertEqual(returns, 0)
            XCTAssertEqual(center.liveCount, 0)
        }
    }

    func testNewActionRejectsOldOpenAndOldActionClaim() throws {
        try onMain {
            let center = TrackingNotificationCenter(), oldAction = NSObject(), newAction = NSObject()
            let lifecycle = make(center)
            var oldReturns = 0, newReturns = 0
            let oldToken = lifecycle.begin(action: oldAction, isCurrent: { true }, onReturn: { oldReturns += 1 })
            let newToken = lifecycle.begin(action: newAction, isCurrent: { true }, onReturn: { newReturns += 1 })
            XCTAssertEqual(center.liveCount, 3)
            XCTAssertEqual(lifecycle.opened(true, token: oldToken, action: oldAction), .stale)
            XCTAssertEqual(lifecycle.claimCallback(action: oldAction), .alreadyConsumed)
            XCTAssertEqual(lifecycle.opened(true, token: newToken, action: newAction), .opened)
            center.post(name: active, object: nil)
            XCTAssertEqual(oldReturns, 0)
            XCTAssertEqual(newReturns, 1)
            XCTAssertEqual(center.liveCount, 0)
        }
    }

    func testSameActionNewGenerationRejectsOldOpen() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var returns = 0
            let old = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { XCTFail("Old generation") })
            let current = lifecycle.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            XCTAssertEqual(lifecycle.opened(true, token: old, action: action), .stale)
            lifecycle.reconcileBufferedReturn(token: old)
            XCTAssertEqual(lifecycle.opened(true, token: current, action: action), .opened)
            center.post(name: active, object: nil)
            XCTAssertEqual(returns, 1)
        }
    }

    func testNoLongerCurrentActionCannotBeClaimed() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            let lifecycle = make(center)
            var isCurrent = true, returns = 0
            let token = lifecycle.begin(action: action, isCurrent: { isCurrent }, onReturn: { returns += 1 })
            isCurrent = false
            XCTAssertEqual(lifecycle.opened(true, token: token, action: action), .stale)
            XCTAssertEqual(lifecycle.claimCallback(action: action), .alreadyConsumed)
            center.post(name: active, object: nil)
            XCTAssertEqual(returns, 0)
            lifecycle.reset()
            XCTAssertEqual(center.liveCount, 0)
        }
    }

    func testDeinitializationRemovesObserversAndDoesNotRetainOwner() throws {
        try onMain {
            let center = TrackingNotificationCenter(), action = NSObject()
            var lifecycle: STPCatalystRedirectLifecycle? = make(center)
            weak var weakLifecycle = lifecycle
            var returns = 0
            _ = lifecycle?.begin(action: action, isCurrent: { true }, onReturn: { returns += 1 })
            XCTAssertEqual(center.liveCount, 3)
            lifecycle = nil
            XCTAssertNil(weakLifecycle)
            XCTAssertEqual(center.liveCount, 0)
            center.post(name: active, object: nil)
            XCTAssertEqual(returns, 0)
        }
    }
}

private final class TrackingNotificationCenter: NotificationCenter, @unchecked Sendable {
    private var liveObservers = Set<ObjectIdentifier>()
    var liveCount: Int { liveObservers.count }

    override func addObserver(forName name: NSNotification.Name?, object obj: Any?, queue: OperationQueue?, using block: @Sendable @escaping (Notification) -> Void) -> any NSObjectProtocol {
        let observer = super.addObserver(forName: name, object: obj, queue: queue, using: block)
        liveObservers.insert(ObjectIdentifier(observer))
        return observer
    }

    override func removeObserver(_ observer: Any) {
        liveObservers.remove(ObjectIdentifier(observer as AnyObject))
        super.removeObserver(observer)
    }
}
