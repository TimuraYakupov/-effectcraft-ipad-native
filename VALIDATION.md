# Validation — 2026-10-18

## Preview build 11 — 2026-10-20 UTC

Device feedback confirms build 10 keyboard delivery. Reported regressions are
idle shortcut latency, missing hover/right-click, absent native AE Bridge menus
and missing custom font installation. The wrapper now supplies these native host
hooks without changing the engine's interchange schema or editor shortcuts.

Checks cover idle-input repaint callback, secondary-button event ordering, actual
File-menu visibility, timeline context menu and trimming, portable project/media
ZIP round trip, persistent and duplicate font registration, bounded ZIP input,
diagnostic journal and IPA metadata. Python zipfile independently validates the
writer's central directory, Unicode names and CRC. Optional headless snapshots
exercise the native File menu, hovered layer bar and layer context menu.

Actions runs the full native frontend tests on Linux, UIKit responder/pointer
callback smoke test on iPad Simulator, and ARM64 iOS release compilation. Pointer
callbacks use synthetic recognizer state; actual mouse/trackpad behavior and
end-to-end AE application import still require device/application verification.

## Preview build 10 — 2026-10-19 UTC

Device feedback: keyboard still does not work in build 9. Its Rust event-translation
tests did not cover UIKit focus/routing. The pinned winit view resigns first responder
when IME is disabled; the window interceptor did not establish a replacement.
Build 10 replaces it with view/controller UIResponder press methods, a non-UIKeyInput
hardware first responder, IME-based handoff and legacy-window discovery.

Live diagnostics exposes native hook/focus and both native/editor event counts;
diagnostic-window input is observable while project commands remain suppressed.
All 8 translation/text/clipboard tests and 3 packaging tests pass locally, along
with locked ARM64 iOS cargo check. The existing blocked-input test now verifies
that diagnostic counters advance without producing editor keys.

Actions additionally runs an actual UIKit iPad Simulator app with the production
Objective-C bridge. It verifies missing pre-install controller focus, successful
hook installation and focus, no UIKeyInput on the hardware responder, exact Space
down/repeat/up records, Cmd+S modifiers, text-focus handoff, file-dialog exclusion,
focus recovery and native status. Key payloads are synthetic test doubles sent
through the installed UIKit responder methods; real iPad/LiveContainer keyboard
delivery is explicitly not claimed by this smoke test.
The smoke also covers a guest presented inside a host controller and a system
modal presented by the guest. IME focus is restored if the hardware controller
still owns it, including an out-of-date queued state; software-keyboard dismissal
does not trigger unconditional text-view refocusing.

## Preview build 9 — 2026-10-19

The user confirmed build 8 opening, saving and importing. The pinned winit iOS
backend handles UIKeyInput but does not deliver physical presses as editor key
transitions. The wrapper adds bounded key/modifier/clipboard input before egui's
RawInput processing, retaining existing editor shortcut and text-focus guards.
Space release is preserved; repeats do not become extra taps. Focus loss resets
held state without generating a Space release. Stray releases are ignored.

The small hardware-keys Cargo harness tests the actual production modules against
egui 0.36.2: HID mappings, Space down/repeat/up, Cmd/Ctrl with a Russian layout,
focused text recovery, modal blocking, single clipboard events, focus loss,
malformed/oversized input, and text entry/paste through a real TextEdit. It avoids
pulling the renderer into the test binary. Actions runs this plus journal, ZIP and
packaging checks, compiles both UIKit modules with the iPhoneOS SDK, and builds
the full native ARM64 release. Device key routing and LiveContainer clipboard
permissions require a physical iPad check; no device result is claimed here.

Passed locally: all 8 keyboard tests, all 3 packaging tests, and locked
`cargo check --target aarch64-apple-ios -p effectcraft-ios` with Rust 1.95.0.

## Preview build 8 — 2026-10-19

Inspected all seconds of the 9.53-second user recording: the file highlights,
but the system picker remains open after Open. It does not establish whether
the OS/provider is rejecting the open-in-place operation or a callback is missing.
The project parser is not reached in the shown sequence.

Changes: copy/import mode instead of in-place for files, data/content filtering,
ecproj/ecprojx UTI declarations, both delegate completion selectors, explicit
picker dismissal on selection/cancel, persistent
working copies. The packaged-plist regression checks both extensions, data
conformance and document handlers. Three packaging tests pass locally. Rust logic
is unchanged except matching bridge directory/build labels; full release compilation
and platform SDK compilation run in Actions. Earlier frontend tests are historical,
not rerun for this wrapper-only change. Actual opening remains a device test.
The system Open/Import cancellation path now reveals the existing local browser;
Save cancellation still aborts without changing the project saved state. This
small Rust flow change is checked by the complete iOS release compilation.

## Preview build 7

The user reported that build 6's folder picker did not complete after Open. The
cause is unconfirmed. Build 7 replaces the folder-only project/media flow with
direct file selection and project export/move. Scope registration and provider
copying have moved off the main thread. Imported files are copied persistently.

Passed locally: locked ARM64 iOS cargo check; 12 native tests, including an
expanded modal cancellation test proving that preparing a system Save As snapshot
does not change the project path/saved revision or clear dirty state; 3 packaging
tests. The fallback browser was rendered at 1024x768 and inspected. Layering and
asset checks are run with the existing preview gates. The complete upstream CI
suite is not run. UIKit compile/link and physical picker/provider testing remain
cloud/device checks. RAM remains 1 GiB; stability needs device verification.

## Preview build 6

The user confirmed project open/save in build 5. Build 6 adds the system folder
picker, retained security-scoped folder access and coordinated project read/write.
RAM preview default/maximum is 1024 MiB, with 256/512/1024 controls. Disk default
remains 1 GiB. Permissions are session-only; files must be reselected after relaunch.

Passed locally: locked ARM64 iOS cargo check; 12 native frontend tests including
folder grant boundaries, protocol failures/cancellation and local atomic save/read;
3 packaging tests; changed Rust formatting; dependency layering; asset attribution
(39 assets). The browser was rendered at 1024x768 and inspected. The UIKit module
requires macOS SDK compilation in Actions, followed by real iPad testing of picker
presentation, file providers, external saving and the 1 GiB memory setting.
The complete upstream CI suite has not been run.

## Preview build 5

The user confirmed build 4 playback from the blue disk-cache range is smooth at
Full resolution on the iPad. Build 5 adds app-local open/save/import dialogs and
stored Bridge ZIP extraction while retaining that cache configuration.

Passed: locked ARM64 iOS cargo check; 9 native frontend tests (save/reopen,
preservation on failed open/save, filename boundaries, LiveContainer path mapping,
rendered modal and Cancel callback, ZIP round-trip/CRC/traversal/duplicate projects/
cancel cleanup, journal tail handling); 3 packaging tests; formatting; dependency
layering; asset attribution (39 assets). The file dialog was rendered headlessly
at 1024x768 and inspected; touch controls were sized to 40 logical pixels.
The ZIP fixtures are generated by Python's standard zipfile and contain synthetic
text only. The cloud workflow repeats the standalone ZIP and journal tests.

Pending on device: the shared LiveContainer folder's visibility in Files, keyboard
input into the save filename, actual project/media compatibility and file persistence
across app replacement. The complete upstream CI suite has not been run.

## Preview build 4

Build 3 was tested by the user at 256 MiB: Quarter cached the whole demo and
played smoothly; Half/Full played cached portions smoothly but exhausted RAM.
Build 4 adds a 1 GiB default disk cache (1/2/4 GiB controls), extends iPad idle
and cache-before-play ranges beyond RAM, and restores frames on the worker.
The iPad stores final RGBA8 frames, including read-back GPU frames, with a bounded
32 MiB compressed write queue. Layer disk caching is off on iPad. The cache is
inside Library/Caches and can be purged by iPadOS.

New regression cases cover disk availability beyond a one-frame RAM budget,
worker restoration of actual pixels without rendering, persistence on reopen,
quality/options/content isolation, malformed frame lengths, write failure and
the prefetch storage threshold. Device playback from disk remains unverified.

Passed on Linux (Rust 1.95.0): locked ARM64 iOS cargo check; 11 render disk-cache
tests and 2 UI frame-cache tests; 2 journal tests; 3 IPA packaging tests; formatting
of changed Rust files; dependency layering; asset attribution (39 assets). Test
profile optimization was disabled to keep host regression compilation practical.
The patch was reapplied to pinned upstream source and compared byte for byte.
The complete upstream CI suite has not been run.

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
