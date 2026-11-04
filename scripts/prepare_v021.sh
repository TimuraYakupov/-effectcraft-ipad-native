#!/usr/bin/env bash
# Build a *real* EffectCraft v0.21.0 engine preserving the tested v0.18 iPad host.
# The native host is first reconstructed against its known-good 0.18.0 base;
# only then do we merge authentic upstream 0.21.0 changes with three-way git.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
UPSTREAM_021=7870b5916ae0749d497d880989683bf2946d6c8b

bash scripts/prepare_v018.sh

git -C effectcraft add -A
git -C effectcraft -c user.name="EffectCraft Native iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" \
  commit -m "Preserve all working iPad native host integrations on EffectCraft 0.18.0"
git -C effectcraft branch ipad-v018-complete
# History depth covers 0.18->0.21 so Git can merge independent upstream changes.
git -C effectcraft fetch --depth 2400 origin "${UPSTREAM_021}"
git -C effectcraft cat-file -e "${UPSTREAM_021}^{commit}"
git -C effectcraft merge-base --is-ancestor c3600f9b59b109da97871a43a6898683a0163cb1 "${UPSTREAM_021}"

# Native platform is deliberately preferred on overlapping hunks (keyboard
# bridge, document imports, iOS view, frame cache); non-overlapping upstream
# changes flow in. Report structural conflicts instead of silently discarding.
if ! git -C effectcraft -c user.name="EffectCraft Native iPad CI" -c user.email="effectcraft-ipad@users.noreply.github.com" \
    merge --no-ff -X ours -m "Merge official EffectCraft v0.21.0 into native iPad port" "${UPSTREAM_021}"; then
    echo "Unresolved structural conflicts while rebasing the native iPad host:" >&2
    git -C effectcraft status --short >&2
    git -C effectcraft diff --name-only --diff-filter=U >&2
    exit 1
fi

python3 scripts/fix_v021_disk_cache.py effectcraft

# 0.21 introduces dedicated preview lanes. The native -X ours merge retains
# the iPad pool customization but skips the lane/queue setup from upstream.
# Restore only the missing initializers, preserving the iPad pool/cache.
python3 - <<'PY'
from pathlib import Path
p=Path('effectcraft/crates/ui-egui/src/frames.rs')
s=p.read_text()
a=s.index('impl Default for Frames {')
b=s.index('\n}\n', a)+2
block=s[a:b]
assert block.count('        Frames {') == 1, 'Unexpected Frames::default() layout'
assert block.count('            queue: Arc::new(Mutex::new(queue)),') == 1
assert block.count('            ctx: None,') == 1
assert '    lanes: Vec<rayon::ThreadPool>,' in s, 'Upstream 0.21 preview lanes missing from struct'
if '        let queue = Queue {' not in block:
    init='''        #[cfg(not(target_arch = "wasm32"))]
        let lanes: Vec<rayon::ThreadPool> = (0..threads)
            .map_while(|i| {
                rayon::ThreadPoolBuilder::new()
                    .num_threads(1)
                    .thread_name(move |_| format!("ec-preview-{i}"))
                    .panic_handler(|_| log::error!("a frame render panicked; that frame was skipped"))
                    .build()
                    .ok()
            })
            .collect();
        #[cfg(not(target_arch = "wasm32"))]
        let queue = Queue { idle_lanes: (0..lanes.len()).collect(), lanes: lanes.len(), ..Default::default() };
        #[cfg(target_arch = "wasm32")]
        let queue = Queue::default();
'''
    block=block.replace('        Frames {',init+'        Frames {',1)
if '            lanes,\n' not in block:
    block=block.replace('            ctx: None,','            #[cfg(not(target_arch = "wasm32"))]\n            lanes,\n            ctx: None,',1)
assert '        let queue = Queue {' in block and '            lanes,\n' in block
s=s[:a]+block+s[b:]
p.write_text(s)
print('Reconciled 0.21 frame priority queue and native iPad preview lanes', flush=True)
PY

python3 - <<'PY'
import pathlib,re,subprocess
root=pathlib.Path('effectcraft')
manifest=(root/'Cargo.toml').read_text()
assert re.search(r'(?m)^version = "0\.21\.0"$',manifest), 'Genuine upstream 0.21.0 version missing from workspace'
assert (root/'apps/effectcraft-ios/src/keyboard.rs').is_file(), 'Native UIKit keyboard missing'
assert (root/'apps/effectcraft-ios/src/files.rs').is_file(), 'Native iPad Files bridge missing'
assert (root/'crates/ui-egui/src/hooks.rs').is_file(), 'UI hooks missing'
kbd=(root/'apps/effectcraft-ios/src/keyboard.rs').read_text()
for token in ['primary_y_scale','indirect_drag_active','scroll_events_received','calibration_active']:
    assert token in kbd, f'Native pointer feature lost: {token}'
assert (root/'apps/effectcraft-ios/Cargo.toml').is_file()
print('Source verified: actual EffectCraft 0.21.0 with native iPad keyboard/drag/scroll/Files preserved')
PY
git -C effectcraft log -1 --format='%h %s'
