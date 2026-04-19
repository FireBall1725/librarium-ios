# Changelog

All notable changes to **librarium-ios** are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Versioning

This project uses **`YY.MM.revision`** (e.g. `26.4.0`, `26.4.1`):

- `YY` — two-digit release year.
- `MM` — release month, *not* zero-padded.
- `revision` — feature counter within the month, starting at `0`. Resets to `0` when the month rolls over.
- `-dev` suffix marks local/Debug unshipped builds; Release builds always use strict numeric `YY.MM.revision` so the App Store accepts them.

Versions `0.1.0` → `0.13.0` predate this scheme. `26.4.0` is the first release cut under the new format and the first release of `librarium-ios` as an independent repository.

## [Unreleased]

### Added

- CHANGELOG, CI workflow, and release workflow.

## [26.4.0] — Initial independent release

First release of `librarium-ios` as a standalone repository under the `YY.MM.revision` versioning scheme. Feature parity with the pre-split workspace as of April 2026 — see the archived workspace changelog for the full history up to this point.
