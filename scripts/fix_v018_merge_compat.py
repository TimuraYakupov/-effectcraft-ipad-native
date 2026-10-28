"""Adapt iPad frame-cache keys to 0.18's virtual-media generation.

0.18 refactored frame-cache tests; handle both remaining old test keys and
upstream's replacement instead of assuming the 0.17 test still exists.
"""
from pathlib import Path
import sys

def main(root: Path) -> None:
    path=root/"crates/ui-egui/src/frames.rs"
    s=path.read_text(encoding="utf-8")
    old="            let content = self.content_keys.lock().unwrap_or_else(std::sync::PoisonError::into_inner).get(&(key.revision, key.comp)).copied();"
    updated="            let epoch = self.virtual_epoch.load(Ordering::Relaxed);\n            let content = self.content_keys.lock().unwrap_or_else(std::sync::PoisonError::into_inner).get(&(key.revision, key.comp, epoch)).copied();"
    if s.count(old)==1:
        s=s.replace(old,updated)
    elif updated not in s:
        raise RuntimeError("iPad disk cache lookup missing or upstream key structure changed")
    for before,after in [
        (".insert((1, 1), content);",".insert((1, 1, 0), content);"),
        (".insert((1, 1), content.wrapping_add(1));",".insert((1, 1, 0), content.wrapping_add(1));")
    ]:
        if before in s:
            s=s.replace(before,after)
    path.write_text(s,encoding="utf-8")
    print("Normalized 0.18 disk cache key generations",flush=True)

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
