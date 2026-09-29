#if targetEnvironment(macCatalyst)
import Foundation
import UIKit
import XCTest
@testable @_spi(STP) import StripePayments
@_spi(STP) import StripeCore

/// Integration tests call the patched handler seams and its real canonical
/// retrieval/status path. All Stripe API reads are supplied by the mock below.
final class STPPaymentHandlerCatalystRedirectTests: XCTestCase {
    private let callback = URL(string: "carnyx-billingqa://stripe-return?test_request=one")!

    private func onMain(_ body: () throws -> Void) rethrows {
        if Thread.isMainThread { try body() }
        else { try DispatchQueue.main.sync(execute: body) }
    }

    func testActivationAndRealCallbackRaceStartsOneCanonicalRead() throws {
        try onMain {
            let context = try Context(callback: callback)
            defer { context.finish() }
            let token = context.begin()
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(true, token: token, action: context.action), .opened)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertEqual(context.api.retrieveCount, 1)
            XCTAssertFalse(context.handler.handleURLCallback(callback))
            NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
            XCTAssertEqual(context.api.retrieveCount, 1)
            XCTAssertTrue(context.statuses.isEmpty)
            context.api.reply(try Self.intent(status: "succeeded"))
            XCTAssertEqual(context.statuses, [.succeeded])
            XCTAssertNil(context.handler.currentAction)
            XCTAssertFalse(context.handler.isHandlingAction)
        }
    }

    func testRealURLRouterFirstThenDelayedOpenCannotRearm() throws {
        try onMain {
            let context = try Context(callback: callback)
            defer { context.finish() }
            let token = context.begin()
            STPURLCallbackHandler.shared().register(context.handler, for: callback)
            XCTAssertTrue(STPURLCallbackHandler.shared().handleURLCallback(callback))
            XCTAssertEqual(context.api.retrieveCount, 1)
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(true, token: token, action: context.action), .stale)
            context.handler._reconcileBufferedCatalystReturn(token: token)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertEqual(context.api.retrieveCount, 1)
            XCTAssertFalse(STPURLCallbackHandler.shared().handleURLCallback(callback))
            context.api.reply(try Self.intent(status: "canceled"))
            XCTAssertEqual(context.statuses, [.canceled])
        }
    }

    func testActivationBeforeOpenCompletionIsReconciledAfterSuccess() throws {
        try onMain {
            let context = try Context(callback: callback)
            defer { context.finish() }
            let token = context.begin()
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertEqual(context.api.retrieveCount, 0)
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(true, token: token, action: context.action), .opened)
            context.handler._reconcileBufferedCatalystReturn(token: token)
            context.handler._reconcileBufferedCatalystReturn(token: token)
            XCTAssertEqual(context.api.retrieveCount, 1)
            context.api.reply(try Self.intent(status: "requires_payment_method"))
            XCTAssertEqual(context.statuses, [.failed])
        }
    }

    func testFailedOpenKeepsFallbackURLCallbackWorking() throws {
        try onMain {
            let context = try Context(callback: callback)
            defer { context.finish() }
            let token = context.begin()
            STPURLCallbackHandler.shared().register(context.handler, for: callback)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(false, token: token, action: context.action), .fallback)
            context.handler._reconcileBufferedCatalystReturn(token: token)
            XCTAssertEqual(context.api.retrieveCount, 0)
            XCTAssertTrue(STPURLCallbackHandler.shared().handleURLCallback(callback))
            XCTAssertEqual(context.api.retrieveCount, 1)
            context.api.reply(try Self.intent(status: "succeeded"))
            XCTAssertEqual(context.statuses, [.succeeded])
        }
    }

    func testActionReplacementRejectsOldOpenAndRemovesOldURLListener() throws {
        try onMain {
            let context = try Context(callback: callback)
            defer { context.finish() }
            let token = context.begin()
            STPURLCallbackHandler.shared().register(context.handler, for: callback)
            let replacement = try context.makeAction(id: "seti_replacement")
            context.handler.currentAction = replacement
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(true, token: token, action: context.action), .stale)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertFalse(STPURLCallbackHandler.shared().handleURLCallback(callback))
            XCTAssertEqual(context.api.retrieveCount, 0)
            XCTAssertTrue(context.handler.currentAction === replacement)
        }
    }

    func testFinishedActionCannotRespondToActivationOrOldCallback() throws {
        try onMain {
            let context = try Context(callback: callback)
            defer { context.finish() }
            let token = context.begin()
            STPURLCallbackHandler.shared().register(context.handler, for: callback)
            context.handler.isHandlingAction = false
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(true, token: token, action: context.action), .stale)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertFalse(STPURLCallbackHandler.shared().handleURLCallback(callback))
            XCTAssertEqual(context.api.retrieveCount, 0)
        }
    }

    func testOldReturnNonceDoesNotConsumeCurrentReturn() throws {
        try onMain {
            let context = try Context(callback: callback)
            defer { context.finish() }
            let token = context.begin()
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(true, token: token, action: context.action), .opened)
            STPURLCallbackHandler.shared().register(context.handler, for: callback)
            let wrong = URL(string: "carnyx-billingqa://stripe-return?test_request=old")!
            XCTAssertFalse(STPURLCallbackHandler.shared().handleURLCallback(wrong))
            XCTAssertEqual(context.api.retrieveCount, 0)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertEqual(context.api.retrieveCount, 1)
            context.api.reply(try Self.intent(status: "canceled"))
            XCTAssertEqual(context.statuses, [.canceled])
        }
    }

    func testUnfinishedCard3DSUsesExistingPollingThenCancels() throws {
        let done = expectation(description: "Existing unresolved 3DS cancellation")
        var context: Context!
        try onMain {
            context = try Context(callback: callback)
            context.onCompletion = { done.fulfill() }
            context.api.automaticReply = try Self.intent(status: "requires_action")
            let token = context.begin()
            XCTAssertEqual(context.handler._completeCatalystRedirectOpen(true, token: token, action: context.action), .opened)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            XCTAssertEqual(context.api.retrieveCount, 1)
            XCTAssertTrue(context.statuses.isEmpty)
        }
        wait(for: [done], timeout: 25)
        onMain {
            XCTAssertEqual(context.statuses, [.canceled])
            XCTAssertGreaterThan(context.api.retrieveCount, 1)
            XCTAssertLessThanOrEqual(context.api.retrieveCount, 18)
            XCTAssertNil(context.handler.currentAction)
            XCTAssertFalse(context.handler.isHandlingAction)
            context.finish()
        }
    }

    private static func intent(id: String = "seti_carnyxTest", status: String) throws -> STPSetupIntent {
        let object: [AnyHashable: Any] = [
            "id": id, "client_secret": id + "_secret_fixture", "status": status,
            "created": 1_750_000_000, "livemode": false, "payment_method_types": ["card"],
            "payment_method": ["id": "pm_fixture", "object": "payment_method", "created": 1_750_000_000,
                "livemode": false, "type": "card", "card": ["brand": "visa", "last4": "3155", "exp_month": 12, "exp_year": 2040]],
            "next_action": ["type": "use_stripe_sdk", "use_stripe_sdk": [
                "type": "three_d_secure_redirect", "stripe_js": "https://example.invalid/challenge"]],
        ]
        let intent = try XCTUnwrap(STPSetupIntent.decodedObject(fromAPIResponse: object))
        XCTAssertEqual(intent.paymentMethod?.type, .card)
        XCTAssertEqual(intent.nextAction?.type, .useStripeSDK)
        return intent
    }

    private final class Context {
        let api = HoldingAPIClient(publishableKey: "pk_test_carnyx_offline_fixture")
        let handler: STPPaymentHandler
        let callback: URL
        var statuses: [STPPaymentHandlerActionStatus] = []
        var onCompletion: (() -> Void)?
        var action: STPPaymentHandlerSetupIntentActionParams!

        init(callback: URL) throws {
            self.callback = callback
            handler = STPPaymentHandler(apiClient: api)
            action = try makeAction(id: "seti_carnyxTest")
            handler.currentAction = action
            handler.isHandlingAction = true
        }

        func makeAction(id: String) throws -> STPPaymentHandlerSetupIntentActionParams {
            STPPaymentHandlerSetupIntentActionParams(apiClient: api,
                authenticationContext: TestAuthenticationContext(),
                threeDSCustomizationSettings: STPThreeDSCustomizationSettings(),
                setupIntent: try STPPaymentHandlerCatalystRedirectTests.intent(id: id, status: "requires_action"),
                returnURL: callback.absoluteString) { [weak self] status, _, _ in
                    guard let self else { return }
                    self.statuses.append(status)
                    self.handler.currentAction = nil
                    self.handler.isHandlingAction = false
                    self.onCompletion?()
                }
        }

        func begin() -> UUID { handler._beginCatalystRedirect(for: action) }
        func finish() {
            handler.currentAction = nil
            handler.isHandlingAction = false
            api.held.removeAll()
        }
    }
}

private final class TestAuthenticationContext: NSObject, STPAuthenticationContext {
    private let controller = UIViewController()
    func authenticationPresentingViewController() -> UIViewController { controller }
}

private final class HoldingAPIClient: STPAPIClient {
    var retrieveCount = 0
    var held: [STPSetupIntentCompletionBlock] = []
    var automaticReply: STPSetupIntent?

    override func retrieveSetupIntent(withClientSecret secret: String, expand: [String]?, timeout: NSNumber?, completion: @escaping STPSetupIntentCompletionBlock) {
        retrieveCount += 1
        if let automaticReply { completion(automaticReply, nil) }
        else { held.append(completion) }
    }

    func reply(_ intent: STPSetupIntent) {
        XCTAssertEqual(held.count, 1)
        guard !held.isEmpty else { return }
        held.removeFirst()(intent, nil)
    }
}
#endif
