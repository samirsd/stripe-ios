# Carnyx Catalyst external authentication recovery

Upstream: Stripe iOS 26.12.0, commit `bc51b3323a06c029c561474547910bff0db82fc8`.
This normal Git checkout is a workspace override; do not modify Xcode's cached
checkout. The Carnyx release source kit records the patch commit and transports
this repository with the other overrides.

On Mac Catalyst, the SDK opens card authentication in the user's browser. Closing
that browser page and activating Carnyx does not reliably emit the iOS
`willEnterForeground` notification. An unresolved PaymentSheet could consequently
remain in Processing. This patch also observes UIKit `didBecomeActive` and the
real public AppKit `NSApplication.didBecomeActiveNotification` during that external
redirect, then invokes the SDK's existing canonical intent retrieval,
polling and cancellation policy. Returning to Carnyx with the challenge still open
uses that same policy; incomplete authentication can be canceled and safely retried.
No payment is granted from an activation or URL alone.

Only the Catalyst branch uses the helper. The original non-Catalyst open-completion
path and foreground observer remain unchanged. A redirect generation belongs to
one action. Activation before the system's open completion is buffered; callback,
foreground and activation signals compete for one reconciliation. Consumed state
persists until the action ends; action replacement, completion and deallocation
remove observers and the callback listener. A late open completion cannot rearm
an old action. Failed external opening preserves the existing browser fallback.

The app's native PaymentSheet integration adds an opaque per-presentation query
nonce to its registered return URL. Stripe's existing URL matcher requires that
query value, preventing a previous browser response from entering a later flow.
No callbacks are synthesized and no client secrets or callback URLs are logged by
this patch.

Lifecycle regression sources and runners live in `CarnyxTests`; actual handler
regressions live in `StripePayments/StripePaymentsTests`. Their local test
outputs and the app's runtime qualification are separate release artifacts. Tests
must run on the main queue, matching UIKit callback and notification delivery.
The new helper is compiled on plain macOS only to allow its Foundation state
machine tests; production SDK usage is guarded by `targetEnvironment(macCatalyst)`.

Reviewed upstream 26.12.1 (`9f0d5aa20e6a690ff4d78b35c307f0fb88d6f36c`) and master
(`82f6ebd5f4e63d7c0c8f6a83425ccbcc8b09fbaa`) retain the same foreground-only behavior.
Reassess this small patch when upgrading Stripe and remove it when upstream has a
compatible fix. Actual browser failure, abandonment and success still require
runtime qualification of the final signed Carnyx build.

A signed Catalyst runtime trace subsequently proved that native AppKit activation
can occur while UIKit stays active and only an unrelated private presentation scene
changes state. The AppKit notification is observed by its public raw name through
Foundation; no AppKit import, scene heuristics, or synthetic notifications are used.
Its exact name is checked against the installed public AppKit constant in tests.
All three real return signals use the same generation and one-shot arbitration.

Temporary read-only diagnostics are restricted to `com.s2.carnyx.billingqa` with
its signed `CarnyxBillingQA=true` marker. `billing-qa-stripe-lifecycle.jsonl` is
bounded to 256 KB and contains only fixed event codes, numeric state/counts,
Boolean-like 0/1 fields, process ID and timestamp. No event changes a payment,
notification, browser, window or lifecycle decision. UIKit/scene observation in
the handler is diagnostic only; it does not invoke recovery.

Recovery notification sources: 1 UIKit foreground, 2 UIKit active, 3 AppKit active.

Event codes: 1 begin, 2 recovery notification, 3 open result, 4 callback claim,
5 reset, 6 return attempt, 7 buffered return, 8 consume; 20 handler begin,
21 handler reset, 22 redirect entry, 23 external-open completion, 24 Safari
fallback, 25 Safari presentation completion, 26 web-auth fallback; 30 canonical
read start, 31 read result, 32 handling-state change, 33 action change, 34 action
completion; 40 scene activated, 41 scene deactivated, 42 application activated,
43 application resigned, 44 application foregrounded. Pending phases are 0 none,
1 opening, 2 opened, 3 consumed. Other status/state integers are the SDK/UIKit
enum raw values. The local generation counter is unrelated to account/intent IDs.
