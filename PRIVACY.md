# Privacy

This document describes the data flows in the unmodified SafeWalk source. A
person or organization that distributes the iOS app or hosts the backend is the
operator of that deployment and must publish a notice that matches its actual
configuration and practices.

## Data sent from the iOS app

- Route and transit requests include start and destination coordinates, the
  selected city, route parameters, and optional departure time.
- Map and navigation features use Mapbox SDKs and APIs under the operator's
  Mapbox account.
- SafeWalk adds no project-operated general analytics service. The linked
  Mapbox Maps and Navigation SDKs include telemetry/event components; Mapbox
  states that they send limited de-identified location and usage data by
  default under its terms. The included map keeps Mapbox's attribution and
  telemetry-control UI visible. Operators must verify the behavior and
  controls of the exact linked SDKs they distribute.
- Place search can use Apple's MapKit services under Apple's platform terms.
- Production API requests use Apple App Attest. The backend stores the
  attested public key, receipt, and assertion counter in Redis.
- Starting Share My Walk sends the selected route and destination label.
  During navigation, the app sends the current coordinates approximately every
  five seconds.

SafeWalk has no user-account database.

## Backend storage

- Route and transit results may be cached in Redis. Cache keys are hashes and
  do not contain plaintext coordinates, but cached values contain route
  geometry. The included defaults retain raw SafeWalk routes for five minutes,
  Mapbox fallback routes for one hour, matched route/matching results for up to
  30 days, and transit results for five minutes. Operators can lower the
  configurable route, matching, and transit TTLs.
- A Share My Walk route, viewer token, and writer-token hash expire after 50
  minutes. The latest live location has the same maximum lifetime. Ending a
  session reduces both lifetimes to a 30-second grace period.
- Anyone with the high-entropy watch URL can view the shared route and live
  location until expiration. The distinct writer token is held only by the
  sharing device and authorizes updates or termination.
- App Attest credentials expire from Redis after 90 days and are refreshed as
  successful assertions renew that TTL. If the backend reports the exact
  missing-credential recovery code, the iOS client clears its stale identifier,
  performs one new attestation, and retries the request once. Any failure in
  that sequence remains fail-closed.

The included server disables automatic request logging. SafeWalk-owned
application log statements do not emit route coordinates, live locations,
share capabilities, cache keys, or upstream response bodies. Sensitive API,
share, token, and App Attest responses use `Cache-Control: private, no-store`.
Operators must separately review proxy, platform, observability, crash, and
third-party SDK diagnostics.

## Data stored on the device

- Saved locations, favorite routes, route history, lifetime statistics,
  trusted contacts, selected city, tutorial state, and preferences use local
  `UserDefaults` or the configured App Group.
- Temporary Mapbox tokens and the App Attest key identifier use the Keychain
  with device-only accessibility.
- The app does not upload contacts; trusted-contact details remain local unless
  the user shares a link through an iOS share destination.

Users can remove local data by deleting saved items in the app or uninstalling
the app. Keychain records can survive an uninstall; the app clears a stale App
Attest identifier when it detects a fresh installation.

## Operator checklist

Before making a deployment available to other people:

1. Publish deployment-specific privacy and retention notices and support
   contact details.
2. Use HTTPS and keep Redis private and authenticated.
3. Confirm infrastructure logs, proxies, observability tools, backups, and
   third-party services do not retain location data beyond the stated policy.
4. Configure unique Apple bundle IDs, App Group, App Attest App ID, and Mapbox
   account credentials.
5. Review App Store privacy disclosures and the bundled
   `PrivacyInfo.xcprivacy` files against the final binary and linked SDK
   privacy manifests. The source manifests are not a generated or aggregated
   final-binary privacy report.
6. Document how users can request deletion of any data the operator adds.

Public incident data and generated model artifacts are not user data, but they
remain subject to the source-specific terms in `DATA_SOURCES.md`.
