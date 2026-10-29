"""Finish native iPad UIKit primary-tap routing and label the actual Build 26.

Tests keep this Apple input path in view without adding an on-screen keyboard.
"""
from pathlib import Path
import sys

def replace_once(path, old, new):
    s=path.read_text(encoding="utf-8")
    if s.count(old)!=1:
        raise RuntimeError(f"{path}: expected one match for {old!r}, found {s.count(old)}")
    path.write_text(s.replace(old,new,1),encoding="utf-8")

def main(root: Path):
    keyboard=root/"apps/effectcraft-ios/src/keyboard.rs"
    replace_once(keyboard,
        '"{} · view={} controller={} · UIKit presses={} · last HID={}",',
        '"{} · view={} controller={} · UIKit presses={} · last HID={} · primary taps={}",')
    replace_once(keyboard,
        '                    status["last_code"].as_u64().unwrap_or(0)\n',
        '                    status["last_code"].as_u64().unwrap_or(0),\n'
        '                    status["native_primary_taps"].as_u64().unwrap_or(0)\n')
    diagnostics=root/"apps/effectcraft-ios/src/diagnostics.rs"
    replace_once(diagnostics,'"Diagnostics · build 19"','"Diagnostics · build 26"')
    main_rs=root/"apps/effectcraft-ios/src/main.rs"
    replace_once(main_rs,'"build=19 startup','"build=26 startup')
    replace_once(main_rs,'"EffectCraft · build 19. RAM:', '"EffectCraft · build 26. RAM:')
    print("Build 26 diagnostics reports actual version and native UIKit primary tap count",flush=True)

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
