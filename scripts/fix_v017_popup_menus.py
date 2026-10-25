"""Reconcile custom iPad File entries with EffectCraft v0.17's new Popup menu bar.

0.17 replaced the old ui.menu_button with Popup::menu, so the 0.14 overlay's
platform_nodes injection was no longer used by the visible top-level File
menu. Reinsert the bridge menu entries and preserve automation anchors.
"""
from pathlib import Path
import sys

def main(root: Path) -> None:
    path = root / "crates/ui-egui/src/menus.rs"
    text = path.read_text(encoding="utf-8")
    if "fn platform_nodes(app:" not in text:
        raise RuntimeError("iPad bridge menu host hooks were lost during merge")
    popup_old = 'crate::widgets::menu_scroll(ui, browsing, |ui| menu_nodes(app, ui, children, &mut clicked, &mut nav, 0));'
    popup_new = '''crate::widgets::menu_scroll(ui, browsing, |ui| {
                            let nodes = platform_nodes(app, label, children);
                            menu_nodes(app, ui, &nodes, &mut clicked, &mut nav, 0);
                        });'''
    if text.count(popup_old) != 1:
        raise RuntimeError(f"Cannot locate upstream Popup menu, found {text.count(popup_old)}")
    text = text.replace(popup_old, popup_new)
    # Submenu panels also need dynamic iPad entries, but this exact menu may
    # already have been resolved automatically by the three-way merge.
    inside = '''        menu_nodes(app, ui, children, &mut clicked, &mut crate::menu_keys::Nav::default(), 0);'''
    replacement = '''        let nodes = platform_nodes(app, name, children);
        menu_nodes(app, ui, &nodes, &mut clicked, &mut crate::menu_keys::Nav::default(), 0);'''
    if inside in text:
        text = text.replace(inside, replacement, 1)
    # Register the actual rect for both static and platform-specific command rows.
    # This also updates iPad's visible File-command regression harness on v0.17.
    entry_old = '''                let r = browse_hover(nav, menu_entry(app, ui, e));
                nav.entry(ui, depth, &r, false);'''
    entry_new = '''                let r = browse_hover(nav, menu_entry(app, ui, e));
                app.auto.add(&format!("menu.command.{}", e.command), r.rect, &e.label);
                nav.entry(ui, depth, &r, false);'''
    if text.count(entry_old) != 1:
        raise RuntimeError(f"Cannot find menu row registration site (found {text.count(entry_old)})")
    text = text.replace(entry_old, entry_new)
    path.write_text(text, encoding="utf-8")
    print("Adapted iPad File/Help bridge menus for upstream v0.17 popup bar", flush=True)

if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
