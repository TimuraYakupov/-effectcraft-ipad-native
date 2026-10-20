"""Require the native touch-release tests to fail with build 14's hover-only targets.

Run from the patched EffectCraft source directory, before the normal green tests.
All source changes made by this proof are restored even when the proof fails.
"""
from pathlib import Path
import subprocess

paths = [Path('crates/ui-egui/src/panels/viewer_drop.rs'), Path('crates/ui-egui/src/panels/timeline.rs')]
originals = {path: path.read_text() for path in paths}
try:
    for path, source in originals.items():
        fixed = 'i.pointer.interact_pos()).filter(|_| ui.rect_contains_pointer('
        assert source.count(fixed) == 1, f'unexpected drop target in {path}'
        path.write_text(source.replace(fixed, 'i.pointer.hover_pos()).filter(|_| ui.rect_contains_pointer('))
    result = subprocess.run(
        ['cargo', '+1.95.0', 'test', '--locked', '-p', 'effectcraft-ios', '--features', 'eframe/x11', 'media_drag_tests::native_touch_release_'],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    print(result.stdout, flush=True)
    assert result.returncode != 0, 'old hover-only targets unexpectedly accepted native touch drops'
    assert '2 failed' in result.stdout and result.stdout.count('drop must add one layer at') == 2, 'did not reproduce both lost media drops'
    assert 'could not compile' not in result.stdout, 'compile failures do not prove this regression'
    print('Confirmed: build-14 hover-only targets lose both native touch-release drops.', flush=True)
finally:
    for path, source in originals.items():
        path.write_text(source)
