# EffectCraft native iPad preview

## Preview build 11: pointer input, AE Bridge and fonts

Build 10 hardware input works on the user's iPad. Build 11 wakes the real eframe
event loop when native input arrives, including while the editor is idle.
Public UIKit hover and secondary-button recognizers deliver pointer movement and
right-click to egui. Both trim handles appear when hovering over a timeline bar.

File now includes Import AE ZIP…, Export Project ZIP…, Save ZIP to Files… and
Import Fonts…. ZIP export snapshots the project, packages referenced media using
portable relative paths and presents the system save picker. The prepared ZIP
can be saved again. Import uses the existing project-opening and unsaved-change
flow. Packages use the stored ZIP format supported by the existing AE Bridge.
Fonts (TTF/OTF/TTC/OTC) are validated, saved in EffectCraft Documents/Fonts and
restored on launch; Character and rendered-frame caches refresh after import.

Output: `EffectCraft-Native-Preview-12.ipa`, build 11. RAM remains 1 GiB.
Simulator and automated tests do not replace physical mouse/trackpad testing
inside LiveContainer.

## Preview build 10: UIKit keyboard focus

The user reported no hardware input in build 9. Its window sendEvent override
never assigned a first responder outside IME editing. Build 10 extends the Winit
UIView/UIViewController pressesBegan/Changed/Ended/Cancelled methods instead.
The controller becomes first responder for hardware input without UIKeyInput,
so it does not request the software keyboard. Actual IME output yields to the
text view; focus is restored after text editing and file dialogs. The legacy
UIApplication.windows fallback matches winit's lifecycle without scene manifests.

Diagnostics shows UIKit hook/focus state, native press count, editor received
count and last HID code. Pressing keys there updates counters without running
project commands. An iPad Simulator smoke app tests the actual production UIKit
module, responder focus, Space down/repeat/up, Cmd+S and IME/dialog recovery.
It also checks automatic IME focus recovery and a guest presented by a host
controller, while keeping the guest's own modal dialogs protected.
It uses test doubles for key payloads; it does not prove real hardware/LiveContainer
delivery. That still needs the user's physical iPad check.

Output: `EffectCraft-Native-Preview-10.ipa`, build 10. RAM remains 1 GiB.

## Preview build 9: hardware keyboard

The user confirmed project opening, saving and import in build 8. Build 9 adds
hardware key-down/key-up delivery to the native egui host. Space taps preview;
holding Space keeps the existing Hand-tool behavior. Cmd/Ctrl+Z, Shift+Z, C/X/V,
S, arrows and Delete/Backspace use the editor's existing shortcut handlers.
Printable text continues through UIKit while a text editor owns focus. Clipboard
text is bounded to 128 KiB; the event backlog is bounded and resets on focus loss.
UIKit document pickers retain their normal keyboard handling. Host file/diagnostic
dialogs suppress project commands while allowing focused text entry.

This wraps only WinitUIWindow's inherited public sendEvent: method; it does not
replace UIKit's global event handling. The file bridge remains DocumentBridge8;
keyboard state uses Keyboard9. RAM remains 1 GiB, disk cache 1 GiB, one worker.
Output: `EffectCraft-Native-Preview-9.ipa`, bundle build 9, same preview identity.
Physical keyboard behavior still needs confirmation on the user's iPad.

## Preview build 8: copy-based project opening

The supplied device recording shows file selection but the Files window does not
close after Open. The failing open-in-place handoff has not been diagnosed on the
physical device. Build 8 uses copy/import mode for project and media selection,
constrains the picker to data/content, and declares ecproj/ecprojx document UTIs
in the packaged Info.plist. Both document-picker delegate selectors are handled,
with duplicate completion suppressed and explicit dismissal on selection/cancel.

Project copies are retained in unique Opened Projects folders inside EffectCraft
Documents (shared LiveContainer/EffectCraft on LiveContainer). The editor never
uses the picker's temporary URL as its project. Save updates the working copy;
Save As chooses another location. Originals remain unchanged. Loose project
media still need relinking or a Bridge ZIP. RAM remains 1 GiB.

Output: `EffectCraft-Native-Preview-8.ipa`, build 8, same preview identity.
This is a compatibility change requiring testing in the user's LiveContainer.
Cancelling the system Open/Import picker reveals the local Documents browser.
Copy a project and its Assets folder to Files > On My iPad > LiveContainer >
EffectCraft, cancel the system picker, then select the local project. The fallback
Cancel button aborts the command; Browse iPad files retries the system picker.

## Preview build 7: direct system file dialogs

File > Open presents the system picker immediately: select a project or Bridge
ZIP itself. File > Import supports up to 64 files; media are copied to a unique
persistent Imported Media folder, streamed with a 1 GiB limit per file.

Save As prepares a project snapshot without changing the session's path or saved
state, then opens the system export/move picker with its filename. Normal engine
Save As finishes after a destination is confirmed. Cancel leaves the project dirty.
Ordinary Save writes back through coordinated access. Other single-file exports
prepare local output first, then present the system export picker. The app-local
browser remains a fallback after errors.

Provider coordination and scope registration run off UIKit's main thread. Picker
presentation/completion are logged. The build-6 folder-only flow is replaced;
its exact device failure remains unconfirmed. Selection and external save behavior
still require iPad testing. Permission is per-file for this launch; a loose project
does not grant all its sibling media. Use a Bridge ZIP for project+media, or import
media separately. Persistent security bookmarks are not implemented yet.

RAM remains 1024 MiB, disk 1 GiB, one render worker. Output:
`EffectCraft-Native-Preview-7.ipa`, build 7, same preview identity.

## Preview build 6: system Files folders and 1 GiB RAM

File > Open / Save As > **Other locations (Files)** opens the iPadOS folder
picker. Choose an accessible folder in On My iPad, iCloud Drive or another Files
provider, then select the project or enter its filename in the app browser.
The selected folder is kept accessible for this launch. Reselect it after relaunch;
persistent bookmarks are not stored yet. Projects retain relative media paths.
ZIPs are extracted to the local EffectCraft Projects folder.

External project reads and atomic replacements use NSFileCoordinator while the
folder's security-scoped URL is retained. A small UIKit Objective-C module in
`platform/EffectCraftDocuments.m` is linked by the wrapper; the editor's Rust
code uses bounded file-based requests and contains no unsafe FFI. Actual picker
presentation and provider behavior in LiveContainer require device testing.

RAM preview caching now defaults to **1024 MiB**, with 256/512/1024 MiB controls
in Diagnostics. Disk caching still defaults to 1 GiB. One render worker and
64 MiB layer/media caches remain. Total process memory exceeds the viewer-cache
limit; the larger limit needs testing on the iPad. The output is
`EffectCraft-Native-Preview-6.ipa`, bundle build number 6, same preview identity.

## Preview build 5: personal project files

File > Open, Save and Save As now use a non-blocking in-app file browser.
File > Import uses the same browser, including multiple media selection. Project
replacement keeps the engine's unsaved-changes guard; Save As asks before replacing
an existing file, and saves use the engine's atomic file writer.

On LiveContainer, launch once to create **Files > On My iPad > LiveContainer >
EffectCraft**, then copy projects/media there. Open the app's File > Open dialog,
tap Refresh, select a file and tap Open. Standalone installations use the app's
Documents folder. This is an app-local browser, not the UIKit/iCloud file picker.
The shared LiveContainer path still needs physical-device verification.

Supported: native `.ecproj`, XML copies `.ecprojx`/`.xml`, and stored (uncompressed)
Bridge ZIPs with exactly one `.ecproj` at their root. ZIP media are streamed into
a unique Projects/Imported-* folder beside the project; existing imports are
never overwritten. ZIP CRCs, paths, sizes, entry count and cancellation are checked.
For a compressed ZIP, unpack it in Files first, then open its `.ecproj` together
with the original relative media folder. Limits: 32 MiB project JSON, 4096 archive
entries, 512 MiB unpacked bytes, 1 GiB archive size. No archive-sized RAM buffer.
Keep the Imported folder's media when moving/saving projects; saving `.ecproj`
alone does not collect media into a portable ZIP.

The output is `EffectCraft-Native-Preview-5.ipa`, bundle build number 5, with the
same native preview identity. Build 4's 256 MiB RAM / 1 GiB disk defaults remain.

## Preview build 4: disk-backed previews

The user confirmed smooth cached playback at 256 MiB in build 3; Quarter fit the
whole demo, while Half and Full exhausted the RAM limit. Build 4 starts with
256 MiB RAM and a 1 GiB persistent disk cache. One render worker and the 64 MiB
layer/media caches are unchanged.

In **Diagnostics · build 4**, choose a 1/2/4 GiB disk limit, disable disk caching,
clear cached files, or inspect frame count, stored bytes, reads and writes.
Green on the timeline means RAM; blue means disk-only. Leave playback paused
for idle caching to fill beyond the RAM window, then play. Frames are read and
decompressed on the frame worker. GPU frames are read back there before saving.
The cache lives in the app's `Library/Caches/EffectCraft/Disk Cache`, survives
relaunch, and may be reclaimed by iPadOS. Settings start at 256 MiB / 1 GiB on
each launch. New projects, edits, quality and view changes use different keys.

Only final preview frames are persisted on iPad; float layer buffers remain in
RAM. The compressed write queue has a 32 MiB limit. Idle filling pauses near
90% of the disk budget or after a write error, avoiding endless cache eviction.
When a caching preview cannot fit on disk either, it falls back to a RAM-sized
range. A full filesystem reports write failures and leaves RAM preview usable.
Disk playback speed and memory behavior still need testing on the actual iPad.
An individual compressed frame larger than the queue is written directly by the
frame worker rather than repeatedly dropped; it never blocks the UI thread.

The output is `EffectCraft-Native-Preview-4.ipa`, bundle build number 4, with the
same native preview identifier. Install it over the previous preview in LiveContainer.

## Preview build 3 history

Build 2 was reported to play without exiting on the test iPad. Its 64 MiB preview
cache held only eight full-HD RGBA8 frames, so old frames were quickly evicted.
Build 3 starts with 128 MiB and restores idle caching, keeping one frame worker.
Open **Diagnostics · build 3** to select 64, 128 or 256 MiB, inspect actual retained
frames and bytes, toggle idle caching, or choose Full/Half/Quarter preview quality.
Changing the limit or quality stops playback. Half uses roughly one quarter of
Full's frame memory; Quarter uses one sixteenth. These controls affect preview,
not export resolution. The safe startup limit resets to 128 MiB on each launch.

The preview limit includes CPU and GPU frame pixels together; layer and media
caches remain 64 MiB each. Total process memory and temporary rendering buffers
can exceed those limits. Larger limits still need testing on the device.
The output is `EffectCraft-Native-Preview-3.ipa`, bundle build number 3, with the
same preview identifier as build 2.

## Diagnostic build 2 history

The first native preview launched on an iPad, but exited during preview caching.
The cause is unconfirmed. This diagnostic build requests one frame worker with
an 8 MiB stack, reduces CPU preview/layer/media caches and GPU frame cache to
64 MiB each, and turns off idle prefetch and disk cache. Metal remains enabled.
These are cache limits, not a limit on total process memory or temporary render buffers.

Every frame start/completion, cache occupancy, playback transition, panic and
GPU error is recorded in Documents/EffectCraftDiagnostics/Logs/effectcraft.log.
iOS log writes are synced after each record; two previous logs survive relaunch.
Open **Diagnostics · build 2 → Previous run** after relaunching following a crash.
Use **Copy log**, or capture the final visible log lines if clipboard transfer is unavailable.
The log viewer reads at most the final 64 KiB. No project contents are logged.

The output is `EffectCraft-Native-Diagnostic-2.ipa` (bundle build number 2,
same preview bundle identifier). The existing stable web-based app is separate.

Experimental native Rust/egui frontend using Metal, based on EffectCraft 0.10.0
(`05955c08b4fd025f1a09882df72e6dbff1a8148a`). Includes the previously tested iPad
editing/font and still-image-cache fixes. Upstream source is fetched at that exact commit;
`patches/ipad-native.patch` contains the changes. No personal media or projects are included.

This is an experimental native frontend, not a replacement for the stable iPad app.
It starts with EffectCraft's synthetic demo. Test launch, panel/timeline interaction,
playback and Metal rendering. App-local files and stored Bridge ZIP import are
connected in build 5; build 6 adds the UIKit folder picker. Custom-font installation,
portable Bridge ZIP export and audio output are not yet connected in this frontend.

## Build

Push this build repository to GitHub. The first push starts the build automatically;
later builds can also be started with **Actions → Native iPad preview → Run workflow**.
The standard `macos-15` runner builds an unsigned ARM64 iOS executable and packages
`EffectCraft-Native-Preview-10.ipa` as an Actions artifact. No Apple signing key is needed
for this unsigned output. Previous builds launched in LiveContainer on the test iPad.
The preview uses `com.effectcraft.ipad.nativepreview`, separate from the stable app.

For a local Mac: install Rust 1.95.0 with `aarch64-apple-ios`, run the source preparation
and build steps from the workflow, then `python3 scripts/package_ipa.py`.

## Verification before the first cloud run

See `VALIDATION.md` for what was checked locally and what still requires macOS/iPad.
Build success must not be inferred from the presence of this source package.

EffectCraft and this code: MIT OR Apache-2.0. The workflow fetches the upstream
licenses and attributed assets together with the source.



Preview 12 restores the original app icon and adds native audio output, persisted preferences, auto-save/recovery, restored external folder permissions, and Render Queue delivery to Files. Render locally to Renders, select a completed item in Render Queue, then use **Save to Files…**. Image sequences use a bounded ZIP export. See VALIDATION.md for device checks and limits.
