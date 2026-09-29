# Carnyx Catalyst external authentication recovery

Upstream: Stripe iOS 26.12.0, commit `bc51b3323a06c029c561474547910bff0db82fc8`.
This normal Git checkout is a workspace override; do not modify Xcode's cached
checkout. The Carnyx release source kit records the patch commit and transports
this repository with the other overrides.

On Mac Catalyst, the SDK opens card authentication in the user's browser. Closing
that browser page and activating Carnyx does not reliably emit the iOS
`willEnterForeground` notification. An unresolved PaymentSheet could consequently
remain in Processing. This patch also observes `didBecomeActive` during that
external redirect, then invokes the SDK's existing canonical intent retrieval,
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
