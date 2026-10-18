# EffectCraft native iPad preview

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

This is a graphics/touch smoke prototype, not a replacement for the stable iPad app.
It starts with EffectCraft's synthetic demo. Test launch, panel/timeline interaction,
playback and Metal rendering. Native document pickers, AE ZIP bridge, custom-font
installation and audio output are not yet connected in this frontend.

## Build

Push this build repository to GitHub. The first push starts the build automatically;
later builds can also be started with **Actions → Native iPad preview → Run workflow**.
The standard `macos-15` runner builds an unsigned ARM64 iOS executable and packages
`EffectCraft-Native-Preview-4.ipa` as an Actions artifact. No Apple signing key is needed
for this unsigned output. Previous builds launched in LiveContainer on the test iPad.
The preview uses `com.effectcraft.ipad.nativepreview`, separate from the stable app.

For a local Mac: install Rust 1.95.0 with `aarch64-apple-ios`, run the source preparation
and build steps from the workflow, then `python3 scripts/package_ipa.py`.

## Verification before the first cloud run

See `VALIDATION.md` for what was checked locally and what still requires macOS/iPad.
Build success must not be inferred from the presence of this source package.

EffectCraft and this code: MIT OR Apache-2.0. The workflow fetches the upstream
licenses and attributed assets together with the source.
