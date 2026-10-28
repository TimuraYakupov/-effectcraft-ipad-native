"""Preserve the previous 25%-200% scale range for our native iPad port."""
from pathlib import Path
import sys

def patch(root: Path, rel: str, old: str, new: str):
    file=root/rel
    s=file.read_text(encoding="utf-8")
    if s.count(old)!=1:
        raise RuntimeError(f"{rel}: cannot locate unique 0.18 UI-scale range")
    file.write_text(s.replace(old,new,1),encoding="utf-8")
    print("Adapted iPad UI scale in",rel,flush=True)

def main(root: Path):
    patch(root,"crates/engine/src/settings/prefs/dialog.rs",
          'Kind::Int(75, 200, "%")',
          'Kind::Int(if cfg!(target_os = "ios") { 25 } else { 75 }, 200, "%")')
    patch(root,"crates/engine/src/settings/prefs/document.rs",
          "self.appearance.ui_scale.clamp(75, 200)",
          'self.appearance.ui_scale.clamp(if cfg!(target_os = "ios") { 25 } else { 75 }, 200)')

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
