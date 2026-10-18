# Validation — 2026-10-18

## Preview build 3

The user confirmed build 2 playback without a process exit. Screenshots show eight
retained frames and 66,355,200 bytes, consistent with its 64 MiB preview limit.
Build 3 increases the default to 128 MiB, caps iPad preview settings at 256 MiB,
restores idle caching, and adds live occupancy, limit and resolution controls.
One frame worker and the 64 MiB layer/media limits remain unchanged.

Device stability with larger limits and idle caching is not yet verified. Cache
occupancy reports retained viewer pixels, not total resident process memory.
The complete upstream CI suite has not been run.

Passed for build 3 on Linux with Rust 1.95.0: locked ARM64 iOS cargo check,
dependency layering, attributed assets (39), iOS frontend formatting, two journal
tests and three packaging tests. The full patch applies without whitespace errors
to the pinned upstream commit and recreates the prepared source exactly.

## Diagnostic build 2

This build investigates an unconfirmed playback-time process termination reported
on an iPad. It is not a verified crash fix. Standalone journal tests cover missing
files and bounded tail reading with invalid UTF-8; packaging tests still cover
the Mach-O platform guard and preview bundle layout (5 tests total).
The release workflow repeats these tests before compiling the ARM64 iOS app.
Actual device playback and log persistence across termination require iPad testing.

## Initial preview validation

Passed locally (Linux x86_64, Rust 1.95.0):

- `cargo check --target aarch64-apple-ios -p effectcraft-ios`: all dependencies,
  shared engine, UI and iOS-only window configuration type-checked successfully.
- `cargo xtask layers`: dependency layering passed after registering the iOS app at L6.
- `cargo fmt -p effectcraft-ios -- --check` and `cargo xtask assets`: passed.
- `cargo check --locked --target aarch64-apple-ios -p effectcraft-ios`: passed.
- The patch applies to the pinned upstream commit and recreates the prepared source tree.
- `python3 -m unittest discover -s scripts -p 'test_*.py'`: 3 packaging checks,
  covering rejection of WASM and iOS Simulator input, separate preview identity,
  ARM64 payload preservation, ZIP CRC and executable file mode. Synthetic headers
  were used for packaging tests and are not included in this bundle.

Pending: release code generation and linking with Apple's SDK on macOS; inspecting
the real Mach-O; installation/start in LiveContainer; touch, Metal, playback and
memory behavior on a physical iPad. Type checking is not a completed IPA build.

The workflow accepts only an actual ARM64 iOS-device executable, verifies its
platform using Apple's `vtool`, packages it, checks ZIP CRC, and emits SHA-256.
It has no signing secrets and does not publish a GitHub release.

The complete upstream CI suite has not been run; this is an experimental source
bundle, not a production release or an upstream pull request.
