"""Reconcile v0.14 iPad UI additions with v0.18 header and render queue layout.

The native overlay removed imports while hiding desktop-only header controls,
but v0.18 still uses Dialog and icons from new code. The updated Render Queue
footer is a function, not a local 'foot' variable: keep the custom Save to Files
button by deriving its rectangle from the panel's own geometry.
"""
from pathlib import Path
import sys

def main(root: Path):
    header=root/"crates/ui-egui/src/header.rs"
    s=header.read_text(encoding="utf-8")
    marker="use crate::icons::Icon;"
    if s.count(marker)!=1:
        raise RuntimeError("Cannot find iPad header icon import")
    if "use crate::{icons, Dialog};" not in s:
        s=s.replace(marker,marker+"\nuse crate::{icons, Dialog};",1)
    header.write_text(s,encoding="utf-8")
    render=root/"crates/ui-egui/src/panels/render_queue.rs"
    s=render.read_text(encoding="utf-8")
    marker="        let button = Rect::from_min_size(pos2(foot.center().x - 75.0, foot.min.y + 1.0), vec2(150.0, FOOT_H - 2.0));"
    if s.count(marker)!=1:
        raise RuntimeError("Cannot find native Save to Files button in render queue")
    s=s.replace(marker,"        let foot = Rect::from_min_max(pos2(rect.min.x, rect.max.y - FOOT_H), rect.max);\n"+marker,1)
    render.write_text(s,encoding="utf-8")
    print("Restored 0.18 header symbols and iPad Render Queue Save to Files geometry",flush=True)

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
