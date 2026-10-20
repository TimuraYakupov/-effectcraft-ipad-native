# EffectCraft for iPad — build 14

A native ARM64 iPad editor built from EffectCraft 0.10.0, pinned at
`05955c08b4fd025f1a09882df72e6dbff1a8148a`. Rust/egui runs over Metal without a
WebView. Builds run on GitHub Actions macOS runners; a local Mac is not required.

## Build and install

Open Actions → Native iPad preview → the latest successful run. Download the
EffectCraft-Native-Preview artifact and extract `EffectCraft-0.10.0-iPad-Build-14.ipa`.
This is an unsigned device build for the existing LiveContainer installation
workflow. Keep the same app/container identity to retain projects and settings.
It is not an App Store or TestFlight distribution.

## Included

- Original licensed pink unicorn app icon.
- Touch, hardware keyboard shortcuts, pointer hover, right-click and timeline trim handles.
- Native Files opening, saving and importing, with coordinated provider access.
- File → Import AE ZIP, Export Project ZIP, Save ZIP to Files and Import Fonts.
- Persistent TTF/OTF/TTC/OTC fonts, matching Character controls and refreshed text caches.
- One render worker; RAM preview starts at 2 GiB, layer/media caches at 64 MiB each.
- RAM and disk preview caching, with green/blue timeline indicators and selectable budgets.
- Native CPAL audio output and iPad audio session handling for playback/interruption.
- Preferences in Documents/Settings; cache choices survive relaunch.
- Automatic recovery copies in Documents/Recovery, every minute by default and on focus loss.
  The next launch offers the latest auto-save after an unclean exit.
- Bookmarks restore external folder/save access on relaunch. If a provider revokes
  access, choose that location again in Files. The last 128 external locations are retained. Opening projects imports a persistent
  local copy; it does not use the unreliable LiveContainer open-in-place handoff.

## Render Queue

Render outputs default to Documents/Renders. Once rendering finishes, select the
completed queue item and press **Save to Files…** in the Render Queue footer.
Movies and audio are exported as files. Primary image sequences are streamed to ZIP,
limited to 4096 frames / 512 MiB. Original rendered files stay available after
cancelling the save picker. Additional output modules stay in their specified folders.

To exchange editable projects with After Effects, use the File-menu AE Bridge
commands rather than video export. Unsupported AE features still follow the
Bridge's validation rules; rendering a movie does not replace the project.

## Validation

CI builds the actual ARM64 iOS executable, validates its Mach-O platform, checks
IPA packaging and icon entries, exercises the production UIKit keyboard bridge in
an iPad Simulator, runs frontend tests, and checks MP4, movie audio and image-sequence
round trips. Physical iPad audio routes, provider permission restoration, suspension,
and playback still require device checks. See [VALIDATION.md](VALIDATION.md).

Third-party and original artwork notices are included in the IPA. No private
projects, media or Apple-proprietary artwork are bundled in this repository.



Build 14 keeps the display name **EffectCraft**, the 2 GiB RAM preview limit and
**Help → Diagnostics…**. It removes build 13's replacement of WinitUIView touch
methods after a device report that mouse actions stopped working. Primary input
again follows the native winit path from build 12; keyboard, hover and secondary
click retain that version's bridge. This hotfix does not claim to resolve the
original imported-media drag issue. UIKit smoke checks assert that all four
native touch methods remain unchanged after bridge installation, including when
the editor is presented inside a host. Physical iPad/LiveContainer mouse behavior
still requires device validation.
