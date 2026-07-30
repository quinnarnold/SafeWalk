# Security policy

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability involving
authentication, location sharing, token minting, credential exposure, or
deployment infrastructure.

Use the repository's private GitHub Security Advisory reporting flow. Include
the affected component, reproduction steps, impact, and any suggested
mitigation. Avoid including real user locations, live tokens, or other secrets.
If private reporting is unavailable, email
[qarnold005@gmail.com](mailto:qarnold005@gmail.com) rather than disclosing
the issue in a public ticket.

Maintainers should acknowledge a report promptly, reproduce it privately,
rotate affected credentials when necessary, and coordinate disclosure after a
fix is available.

## Supported code

Security fixes target the latest revision of the default branch. Operators are
responsible for updating deployments and for their own cloud, Redis, Mapbox,
Apple, TLS, and logging configuration.

## Deployment requirements

- Never run `AUTH_MODE=disabled` in production.
- Keep Redis private and password protected.
- Use HTTPS for all public endpoints.
- Protect Mapbox, Apple, CI, and cloud credentials.
- Treat share URLs as bearer secrets and preserve their expiration.
- Send private routes, tokens, App Attest responses, and share data with
  `Cache-Control: private, no-store`.
- Do not log precise route or live-location payloads.
- Set `TRUST_PROXY=true` only behind a trusted proxy that overwrites forwarded
  client-IP headers.
