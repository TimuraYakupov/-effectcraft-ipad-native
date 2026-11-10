#!/usr/bin/env bash
# Build the authentic EffectCraft 0.23.0 source on the native iPad host.
# Recover the iPad-specific fixes from the previous 0.21 port first.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
UPSTREAM_021=7870b5916ae0749d497d880989683bf2946d6c8b
UPSTREAM_023=921bc496cc839447f899a83652a38975007afc55

bash scripts/prepare_v021.sh

# The new compact-project format added a second bool parameter in 0.21;
# update native saves (the 0.21 Build 32 compiler stopped here).
python3 - <<'PY'
from pathlib import Path
fixes = {
    Path('effectcraft/apps/effectcraft-ios/src/bridge.rs'): (
        'to_file_json_with_view(&view)',
        'to_file_json_with_view(&view, false)'
    ),
    Path('effectcraft/apps/effectcraft-ios/src/files.rs'): (
        'to_file_json_with_view(&app.session.saved_view())',
        'to_file_json_with_view(&app.session.saved_view(), false)'
    ),
}
for path, (old, new) in fixes.items():
    source = path.read_text(encoding='utf-8')
    if old in source:
        assert source.count(old) == 1, f'Unexpected project save occurrences: {path}'
        source = source.replace(old, new, 1)
        path.write_text(source, encoding='utf-8')
    assert new in source, f'Native project serialization API missing: {path}'
print('Native iPad project save compatibility updated', flush=True)
PY

git -C effectcraft add -A
git -C effectcraft -c user.name="EffectCraft Native iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" commit -m "Correct native project serialization call for compact-project API"

# Start 0.23 from a reconciled 0.21 native port rather than repeating the older
# 0.18 -> 0.23 integration in one merge.
git -C effectcraft fetch --depth 3000 origin "${UPSTREAM_023}"
git -C effectcraft cat-file -e "${UPSTREAM_023}^{commit}"
git -C effectcraft merge-base --is-ancestor "${UPSTREAM_021}" "${UPSTREAM_023}"

if ! git -C effectcraft -c user.name="EffectCraft Native iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" \
  merge --no-ff -X ours -m "Merge official EffectCraft v0.23.0 into native iPad port" "${UPSTREAM_023}"; then
  echo "Unresolved native-v0.23 integration conflicts:" >&2
  git -C effectcraft status --short >&2
  git -C effectcraft diff --name-only --diff-filter=U >&2
  exit 1
fi

# Undo stale -X ours disk-cache code from the 0.21 overlay, retaining only
# safe iPad memory/error limits on top of the coherent 0.23 implementation.
python3 scripts/reconcile_v023_disk_cache.py effectcraft "${UPSTREAM_023}"
python3 scripts/reconcile_v023_frames.py effectcraft "${UPSTREAM_023}"
python3 scripts/fix_v023_ipad_render_export.py effectcraft scripts

python3 - <<'PY'
import pathlib,re
root=pathlib.Path('effectcraft')
manifest=(root/'Cargo.toml').read_text()
assert 'version = "0.23.0"' in manifest, 'Authentic upstream v0.23.0 missing'
for rel in ['apps/effectcraft-ios/src/keyboard.rs', 'apps/effectcraft-ios/src/files.rs', 'crates/ui-egui/src/hooks.rs']:
    assert (root/rel).is_file(), f'Lost iPad bridge: {rel}'
kbd=(root/'apps/effectcraft-ios/src/keyboard.rs').read_text()
for token in ['primary_y_scale','indirect_drag_active','scroll_events_received','calibration_active']:
    assert token in kbd, f'Lost native pointer feature: {token}'
for rel in ['apps/effectcraft-ios/src/bridge.rs','apps/effectcraft-ios/src/files.rs']:
    assert 'to_file_json_with_view(' in (root/rel).read_text(), f'Lost iOS save API: {rel}'
print('Verified original v0.23.0 and retained native keyboard/Files/trackpad bridge', flush=True)
PY
git -C effectcraft log -1 --format='%h %s'
