"""Red-team the iPad release drop fix on both v0.18 UI target shapes.

Temporarily switch each of the two native release handlers to hover_pos and
ensure the regression tests fail from lost media layers, not from a compile
error. Restore the original files even if a test or assertion fails.
"""
from pathlib import Path
import subprocess

targets={
 Path("crates/ui-egui/src/panels/timeline.rs"):"rows_rect",
 Path("crates/ui-egui/src/panels/viewer_drop.rs"):"map.area",
}
originals={path:path.read_text(encoding="utf-8") for path in targets}
try:
    for path,region in targets.items():
        before=f'i.pointer.interact_pos()).filter(|_| ui.rect_contains_pointer({region}))'
        after=f'i.pointer.hover_pos()).filter(|_| ui.rect_contains_pointer({region}))'
        source=originals[path]
        assert source.count(before)==1, f"native release target missing: {path}"
        path.write_text(source.replace(before,after,1),encoding="utf-8")
    result=subprocess.run(
        ["cargo","+1.95.0","test","--locked","-p","effectcraft-ios","--features","eframe/x11","media_drag_tests::native_touch_release_"],
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True
    )
    print(result.stdout,flush=True)
    assert result.returncode!=0, "old hover-only native release unexpectedly passed"
    assert "2 failed" in result.stdout and result.stdout.count("drop must add one layer at")==2, "expected exactly the two dropped-layer regression failures"
    assert "could not compile" not in result.stdout, "compile failure does not prove native touch regression"
    print("Validated: both old hover-only drop handlers lose native touch releases",flush=True)
finally:
    for path,source in originals.items():
        path.write_text(source,encoding="utf-8")
