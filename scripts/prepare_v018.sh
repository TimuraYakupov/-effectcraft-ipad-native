#!/usr/bin/env bash
# Rebuild the known-good iPad overlay against the *actual* upstream EffectCraft v0.18.0.
set -euo pipefail
OLD="26b40199b72121aa7f4e55a63718e1b4dd48a859" # v0.14.0 overlay base
NEW="c3600f9b59b109da97871a43a6898683a0163cb1" # upstream v0.18.0 release tag
git init effectcraft
git -C effectcraft remote add origin https://github.com/storytold/effectcraft.git
git -C effectcraft fetch --depth 900 origin "${NEW}"
git -C effectcraft cat-file -e "${OLD}^{commit}"
git -C effectcraft checkout -B ipad-overlay "${OLD}"
git -C effectcraft apply --check ../patches/ipad-native.patch
git -C effectcraft apply ../patches/ipad-native.patch
git -C effectcraft add -A
git -C effectcraft -c user.name="EffectCraft iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" commit -m "iPad build 19 native overlay on v0.14.0"
git -C effectcraft checkout -B ipad-v018 "${NEW}"
# 0.18 moved engine layer commands and preferences into new module trees.
# Resolve ONLY these two known modify/delete conflicts; reject all others.
if ! git -C effectcraft -c user.name="EffectCraft iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" merge --no-ff -X ours -m "Port iPad overlay onto v0.18.0" ipad-overlay; then
    expected=$(printf '%s\n' crates/engine/src/commands/layer.rs crates/engine/src/prefs.rs | sort)
    actual=$(git -C effectcraft diff --name-only --diff-filter=U | sort)
    if [[ "${actual}" != "${expected}" ]]; then
        echo "Unexpected 0.18 merge conflicts: ${actual}" >&2
        exit 1
    fi
    git -C effectcraft rm -- crates/engine/src/commands/layer.rs crates/engine/src/prefs.rs
    git -C effectcraft -c user.name="EffectCraft iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" commit -m "Resolve 0.18 engine module relocation in favour of upstream"
fi
# Large upstream refactors: 0.18 split menus.rs into menus/{bar,entries,invoke,..}
# and lib.rs into app.rs and hooks.rs. We cannot retain 0.14's old monolith.
for path in crates/ui-egui/src/menus.rs crates/ui-egui/src/lib.rs crates/media/src/pool.rs; do
    git -C effectcraft show "${NEW}:${path}" > "effectcraft/${path}"
done
python3 scripts/migrate_v018.py effectcraft
python3 scripts/fix_velocity_selection.py effectcraft
python3 scripts/fix_v018_merge_compat.py effectcraft
python3 scripts/fix_v018_bridge_tests.py effectcraft
python3 scripts/fix_v018_touch_drop.py effectcraft
python3 scripts/fix_v018_ui_scale.py effectcraft
python3 scripts/fix_v018_ui_conflicts.py effectcraft
python3 scripts/fix_v018_cursor_hit_offset.py effectcraft
python3 scripts/fix_v018_macos_hardware_shortcuts.py effectcraft
git -C effectcraft status --short
