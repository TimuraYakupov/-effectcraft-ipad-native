# EffectCraft native iPad preview

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
`EffectCraft-Native-Preview-6.ipa` as an Actions artifact. No Apple signing key is needed
for this unsigned output. Previous builds launched in LiveContainer on the test iPad.
The preview uses `com.effectcraft.ipad.nativepreview`, separate from the stable app.

For a local Mac: install Rust 1.95.0 with `aarch64-apple-ios`, run the source preparation
and build steps from the workflow, then `python3 scripts/package_ipa.py`.

## Verification before the first cloud run

See `VALIDATION.md` for what was checked locally and what still requires macOS/iPad.
Build success must not be inferred from the presence of this source package.

EffectCraft and this code: MIT OR Apache-2.0. The workflow fetches the upstream
licenses and attributed assets together with the source.
