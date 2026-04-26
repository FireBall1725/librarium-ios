# Security policy

## Reporting a vulnerability

**Please report security issues privately**, not via public issues.

Use GitHub's private vulnerability reporting on this repo:

→ https://github.com/fireball1725/librarium-ios/security/advisories/new

That keeps the report visible only to maintainers until a fix is ready, and gives us a paper trail to coordinate disclosure on.

## What's in scope

Anything that lets an attacker:

- Read or modify another user's data when signed in
- Bypass auth, biometric unlock, or the multi-server account boundary
- Extract credentials from Keychain or sidestep Keychain entirely
- Smuggle data through scanned barcodes or ISBN lookups
- Impersonate a server or strip TLS in flight

For server-side issues that the API is responsible for, file on [librarium-api](https://github.com/fireball1725/librarium-api/security/advisories/new) instead.

## Out of scope

- Issues only reproducible on jailbroken devices
- Findings from automated scanners that aren't reproducible against a real device or simulator
- Crashes that don't have a security implication — file those as a normal bug

## Response

This is a small, self-hosted project run by a single maintainer. Best-effort response targets:

- **Acknowledgement**: within 1 week
- **Initial triage**: within 2 weeks
- **Fix or mitigation plan**: within 4 weeks for high-severity issues; TestFlight build + App Store submission to follow

We'll credit you in the release notes when the fix ships, unless you'd prefer to stay anonymous.
