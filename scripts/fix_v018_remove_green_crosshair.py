"""Remove obsolete green pointer crosshair without changing solved 2-point calibration.

Build 28's top/bottom orange targets are needed only while calibrating.
Build 27's green click marker was a temporary diagnostic and should no longer
cover the editor after every physical trackpad click.
"""
from pathlib import Path
import sys


def remove_green_overlay(source: str) -> str:
    marker = "        if let Some((pos, at)) = self.keyboard.recent_primary {\n"
    n = source.count(marker)
    if n != 1:
        raise RuntimeError(f"Expected one obsolete green cursor overlay, found {n}")
    start = source.index(marker)
    end_marker = "        if self.open {\n"
    end = source.find(end_marker, start)
    if end < 0:
        raise RuntimeError("Cannot find diagnostics window following old green overlay")
    old = source[start:end]
    for expected in ["egui::Color32::LIGHT_GREEN", "p.circle_stroke", "p.line_segment", "self.keyboard.recent_primary"]:
        if expected not in old:
            raise RuntimeError(f"Refusing to remove non-green overlay: {expected}")
    if "calibration_stage" in old or "TOP" in old or "BOTTOM" in old:
        raise RuntimeError("Refusing to remove two-point orange calibration targets")
    source = source[:start] + source[end:]
    labels = [
        '                ui.label("A green crosshair marks the last UIKit left-click for 10 seconds. Compare it with the visible cursor/layer row.");\n',
        '                ui.label("A green crosshair marks the last UIKit left-click for 10 seconds.");\n',
    ]
    for label in labels:
        if source.count(label) != 1:
            raise RuntimeError(f"Green overlay label missing: {label}")
        source = source.replace(label, "", 1)
    return source


def patch(root: Path):
    diagnostics = root / "apps/effectcraft-ios/src/diagnostics.rs"
    source = diagnostics.read_text(encoding="utf-8")
    source = remove_green_overlay(source)
    if source.count('"Diagnostics · build 28"') != 1:
        raise RuntimeError("Diagnostics Build 28 marker not found")
    source = source.replace('"Diagnostics · build 28"', '"Diagnostics · build 29"', 1)
    for expected in ["Calibrate TOP + BOTTOM", "TOP · 1/2", "BOTTOM · 2/2", "primary_y_scale"]:
        if expected not in source:
            raise RuntimeError(f"Two-point calibration must be preserved: {expected}")
    diagnostics.write_text(source, encoding="utf-8")

    main = root / "apps/effectcraft-ios/src/main.rs"
    data = main.read_text(encoding="utf-8")
    for old, new in [('"build=28 startup', '"build=29 startup'),
                     ('"EffectCraft · build 28. RAM:', '"EffectCraft · build 29. RAM:')]:
        if data.count(old) != 1:
            raise RuntimeError(f"Missing startup build label: {old}")
        data = data.replace(old, new, 1)
    main.write_text(data, encoding="utf-8")
    print("Removed green crosshair and its text; retained orange top/bottom targets and saved calibration.")


if __name__ == "__main__":
    patch(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
