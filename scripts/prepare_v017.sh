#!/usr/bin/env bash
# Prepare a real upstream v0.17.0 checkout, preserving the last known-good iPad
# overlay as a separate commit and three-way merging it onto the release.
set -euo pipefail
OLD="26b40199b72121aa7f4e55a63718e1b4dd48a859" # v0.14.0 / build 19
NEW="362474a843ddb67555d4c2d19ad6a590388aad0e" # v0.17.0 tag
git init effectcraft
git -C effectcraft remote add origin https://github.com/storytold/effectcraft.git
# v0.14 -> v0.17 is 294 commits. Keep the common ancestor available for
# Git's normal three-way merge (fetching two depth-1 tips would NOT work).
git -C effectcraft fetch --depth 380 origin "${NEW}"
git -C effectcraft cat-file -e "${OLD}^{commit}"
git -C effectcraft checkout -B ipad-overlay "${OLD}"
git -C effectcraft apply --check ../patches/ipad-native.patch
git -C effectcraft apply ../patches/ipad-native.patch
git -C effectcraft add -A
git -C effectcraft -c user.name="EffectCraft iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" commit -m "iPad build 19 overlay on v0.14.0"
git -C effectcraft checkout -B ipad-v017 "${NEW}"
# Conflicting upstream modifications win; iPad-only code and nonconflicting
# changes survive. CI builds/tests will expose any lost host integration.
git -C effectcraft -c user.name="EffectCraft iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" merge --no-ff -X ours -m "Port iPad overlay onto v0.17.0" ipad-overlay
# The old iPad reduced-still cache patch collides with upstream #1812, which
# already implements a more complete still_at_size cache and nominal key.
# Restore the 0.17 upstream implementation rather than keeping an orphaned
# reduced_still conditional from the 0.14 merge.
git -C effectcraft show "${NEW}:crates/media/src/pool.rs" > effectcraft/crates/media/src/pool.rs
python3 scripts/fix_velocity_selection.py effectcraft
# Workspace packages grew since v0.14; make the lockfile consistent instead
# of copying outdated 0.14 package metadata into a 0.17 binary.
git -C effectcraft status --short
