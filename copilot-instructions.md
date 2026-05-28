Copilot / Agent Instructions

Purpose
- Provide a short, actionable set of conventions for edits and new files in this repository.

Basic repo structure
- `Mochi.xcodeproj/` — Xcode project; update target membership here when adding new files.
- `Mochi/` — app Swift sources and asset catalogs.
  - `Mochi/core` - backend code for all platforms
  - `Mochi/iOS/` — iOS-specific views and helpers.
  - `Mochi/iOS-legacy/` — iOS 15-specific views and helpers.
  - `Mochi/iPadOS/` — iPadOS-specific views and helpers.
  - `Mochi/iPadOS-legacy/` — iPadOS 15-specific views and helpers.
  - `Mochi/macOS/` — macOS-specific views and helpers.
  - `Mochi/macOS-legacy/` — macOS 12-specific views and helpers.
  - `Mochi/tvOS/` — tvOS-specific views and helpers.
  - `Mochi/visionOS/` — visionOS-specific views and helpers.
  - `Mochi/watchOS/` — watchOS-specific views and helpers.
  - `MochiApp.swift`, `ContentView.swift` — shared app entrypoints.
- `RootHelper/` - RootHelper for Mochi
  - `main.c` - main file for RootHelper
- `.github/workflows/` — CI config; do not modify without explicit instruction.
- `simulator.sh` — developer helper script to build and launch simulators.
- `procursus-bootstrap.sh` — bootstrap helper script; treat as infra, not app code.
- All source files must include the GPL-3.0 license header.


Core conventions
- Put platform-specific code under `Mochi/<platform>/` (e.g. `Mochi/tvOS/`).
- Use top-level types for models and view models when multiple files need access.
- Keep patches focused: small diffs, minimal unrelated reformatting.

When adding helpers
- Create a per-target helper file (e.g. `Helpers_tvOS.swift`) and add it to the Xcode target. If that is not possible immediately, an inline minimal implementation is acceptable as a stopgap.