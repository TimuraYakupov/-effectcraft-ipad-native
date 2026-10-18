# EffectCraft native iPad preview

## Diagnostic build 2

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
`EffectCraft-Native-Preview.ipa` as an Actions artifact. No Apple signing key is needed
for this unsigned output. The first install/start in LiveContainer remains unverified.
The preview uses `com.effectcraft.ipad.nativepreview`, separate from the stable app.

For a local Mac: install Rust 1.95.0 with `aarch64-apple-ios`, run the source preparation
and build steps from the workflow, then `python3 scripts/package_ipa.py`.

## Verification before the first cloud run

See `VALIDATION.md` for what was checked locally and what still requires macOS/iPad.
Build success must not be inferred from the presence of this source package.

EffectCraft and this code: MIT OR Apache-2.0. The workflow fetches the upstream
licenses and attributed assets together with the source.
