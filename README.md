# EffectCraft for iPad — build 13

A native ARM64 iPad editor built from EffectCraft 0.10.0, pinned at
`05955c08b4fd025f1a09882df72e6dbff1a8148a`. Rust/egui runs over Metal without a
WebView. Builds run on GitHub Actions macOS runners; a local Mac is not required.

## Build and install

Open Actions → Native iPad preview → the latest successful run. Download the
EffectCraft-Native-Preview artifact and extract `EffectCraft-0.10.0-iPad-Build-13.ipa`.
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



Build 13 uses the display name **EffectCraft**, retaining the existing bundle ID and storage.
Diagnostics and cache budget controls are available in **Help → Diagnostics…**; there is no permanent overlay button. Existing installations switch to 2 GiB RAM preview once on upgrade, then retain later manual choices. Physical primary mouse touches now have an owned down/move/up/cancel path, without duplicate touchscreen events. The simulator checks pointer capture and touch/Pencil/secondary fallback, and frontend regression tests import WAV media then drag it from Project into the Composition viewer and Timeline. Physical iPad/LiveContainer pointer behavior still needs device validation.
