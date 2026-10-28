"""Keep native touch-release drops working after v0.18 refactors.

The egui pointer hover disappears on touch release while interact_pos is
retained. Use interact_pos on the precise media drop target only, preserving
the normal mouse pointer behavior everywhere else.
"""
from pathlib import Path
import sys

def main(root: Path):
    for rel,region in [
        ("crates/ui-egui/src/panels/timeline.rs","rows_rect"),
        ("crates/ui-egui/src/panels/viewer_drop.rs","map.area"),
    ]:
        path=root/rel
        source=path.read_text(encoding="utf-8")
        old=f'i.pointer.hover_pos()).filter(|_| ui.rect_contains_pointer({region}))'
        fixed=f'i.pointer.interact_pos()).filter(|_| ui.rect_contains_pointer({region}))'
        if source.count(fixed)==1:
            print("Retained native touch drop in",rel)
            continue
        if source.count(old)!=1:
            raise RuntimeError(f"Drop target moved unexpectedly: {rel}; old={source.count(old)} fixed={source.count(fixed)}")
        path.write_text(source.replace(old,fixed,1),encoding="utf-8")
        print("Restored native touch release drop in",rel,flush=True)

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
