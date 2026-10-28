"""Rehome the iPad host bridge into EffectCraft 0.18's split UI modules.

0.18 moved menu handling into menus/{bar,entries,invoke,commands}.rs and
Hooks into hooks.rs. Never keep the stale 0.14 monolithic menus.rs or lib.rs:
the upstream interfaces must remain authoritative, with host integrations
adapted in their new modules. Fail loudly when an upstream anchor moves.
"""
from pathlib import Path
import sys

def one(src: str, old: str, new: str, name: str) -> str:
    n = src.count(old)
    if n != 1:
        raise RuntimeError(f"{name}: expected one anchor, found {n}: {old[:105]!r}")
    return src.replace(old, new, 1)

def edit(root: Path, p: str, fn):
    path = root / p
    a = path.read_text(encoding="utf-8")
    b = fn(a)
    if a == b:
        raise RuntimeError(f"{p}: no change")
    path.write_text(b, encoding="utf-8")
    print("Updated", p, flush=True)

def menus_module(s: str) -> str:
    marker = "pub struct UiCommand {"
    extension = '''/// Native host's optional ZIP/font bridge actions (iPad / web host).
#[derive(Clone, Default, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BridgeState {
    pub import_enabled: bool,
    pub export_enabled: bool,
    pub save_enabled: bool,
    #[serde(default)]
    pub fonts_enabled: bool,
    pub status: String,
}

const BRIDGE_COMMANDS: &[(&str, &str)] = &[
    ("bridge.importAEZip", "Import AE ZIP…"),
    ("bridge.exportProjectZip", "Export Project ZIP…"),
    ("bridge.saveZipToFiles", "Save ZIP to Files…"),
    ("bridge.importFonts", "Import Fonts…"),
];

fn bridge_state(app: &EffectcraftApp) -> Option<BridgeState> {
    app.hooks.bridge_state.as_ref().and_then(|get| get())
}

fn bridge_enabled(state: &BridgeState, id: &str) -> bool {
    match id {
        "bridge.importAEZip" => state.import_enabled,
        "bridge.exportProjectZip" => state.export_enabled,
        "bridge.saveZipToFiles" => state.save_enabled,
        "bridge.importFonts" => state.fonts_enabled,
        _ => false,
    }
}

fn bridge_entries(app: &EffectcraftApp) -> Vec<MenuNode> {
    if bridge_state(app).is_none() { return vec![]; }
    BRIDGE_COMMANDS.iter().map(|(id, label)| MenuNode::Item(MenuEntry {
        label: (*label).into(), command: (*id).into(), params: Value::Null,
        shortcut: None, alt_shortcuts: Vec::new(),
    })).collect()
}

fn platform_nodes(app: &EffectcraftApp, name: &str, children: &[MenuNode]) -> Vec<MenuNode> {
    let mut nodes = children.to_vec();
    if name == "File" {
        let bridge = bridge_entries(app);
        if !bridge.is_empty() {
            let at = nodes.iter().position(|n| matches!(n, MenuNode::Submenu { label, .. } if label == "Save As"))
                .map_or(nodes.len(), |i| i + 1);
            nodes.splice(at..at, std::iter::once(MenuNode::Separator).chain(bridge).chain(std::iter::once(MenuNode::Separator)));
        }
    } else if name == "Help" && app.hooks.diagnostics.is_some() {
        nodes.push(MenuNode::Separator);
        nodes.push(MenuNode::Item(MenuEntry {
            label: "Diagnostics…".into(), command: "platform.diagnostics".into(),
            params: Value::Null, shortcut: None, alt_shortcuts: Vec::new(),
        }));
    }
    nodes
}

'''
    return one(s, marker, extension+marker,"menus bridge helpers")

def hooks(s: str) -> str:
    marker="    pub system_theme: Option<SystemThemeFn>,"
    ext='''    pub bridge_state: Option<Box<dyn Fn() -> Option<crate::menus::BridgeState>>>,
    pub bridge_action: Option<Box<dyn Fn(&str) -> Result<(), String>>>,
    pub diagnostics: Option<Box<dyn Fn()>>,
    pub save_rendered: Option<Box<dyn Fn(Vec<String>) -> Result<(), String>>>,
'''
    return one(s,marker,marker+"\n"+ext.rstrip(),"host hooks")

def menu_entries(s: str) -> str:
    marker="pub(crate) fn entry_enabled(app: &EffectcraftApp, e: &MenuEntry) -> bool {"
    guard='''    if e.command == "platform.diagnostics" {
        return app.hooks.diagnostics.is_some();
    }
    if BRIDGE_COMMANDS.iter().any(|(id, _)| *id == e.command) {
        return bridge_state(app).is_some_and(|state| bridge_enabled(&state, &e.command));
    }
'''
    s=one(s,marker,marker+"\n"+guard.rstrip(),"menu entry enablement")
    marker2='''    effectcraft_engine::menus::entries()
        .into_iter()
        .map(|(path, e)| MenuItem {'''
    s=one(s,marker2,'''    let mut items: Vec<MenuItem> = effectcraft_engine::menus::entries()
        .into_iter()
        .map(|(path, e)| MenuItem {''',"menu item iterator")
    marker3='''        })
        .collect()
}'''
    # Check belongs to menu_items and not any other method at this exact location.
    k=s.index("pub fn menu_items(")
    before, after = s[:k],s[k:]
    addon='''        }).collect();
    if app.hooks.diagnostics.is_some() {
        items.push(MenuItem {
            id: "platform.diagnostics".into(), label: "Diagnostics…".into(), path: vec!["Help".into()],
            shortcut: None, enabled: true, checked: None, params: Value::Null,
        });
    }
    for node in bridge_entries(app) {
        if let MenuNode::Item(e) = node {
            items.push(MenuItem {
                id: e.command.clone(), label: e.label.clone(), path: vec!["File".into()],
                shortcut: None, enabled: entry_enabled(app, &e), checked: None, params: e.params,
            });
        }
    }
    items
}'''
    after=one(after,marker3,addon,"bridge menu item enumeration")
    return before+after

def invoke(s: str) -> str:
    marker='pub fn invoke(app: &mut EffectcraftApp, ctx: &egui::Context, id: &str, params: Value) -> Result<Value, String> {'
    guard='''    if id == "platform.diagnostics" {
        app.hooks.diagnostics.as_ref().ok_or("Platform diagnostics unavailable")?();
        ctx.request_repaint();
        return Ok(Value::Null);
    }
    if BRIDGE_COMMANDS.iter().any(|(command, _)| *command == id) {
        let state = bridge_state(app).ok_or("The iPad ZIP bridge is unavailable")?;
        if !bridge_enabled(&state, id) {
            return Err(if id == "bridge.saveZipToFiles" {
                "Export Project ZIP first, then save the prepared ZIP".into()
            } else {
                "Wait for the ZIP bridge to finish loading or its current operation".into()
            });
        }
        app.hooks.bridge_action.as_ref().ok_or("The iPad ZIP bridge handler is unavailable")?(id)?;
        ctx.request_repaint();
        return Ok(Value::Null);
    }
'''
    return one(s,marker,marker+"\n"+guard.rstrip(),"native bridge command dispatch")

def bar(s: str) -> str:
    orig="crate::widgets::menu_scroll(ui, browsing, |ui| menu_nodes(app, ui, children, &mut clicked, &mut nav, 0));"
    changed='''crate::widgets::menu_scroll(ui, browsing, |ui| {
                            let nodes = super::platform_nodes(app, label, children);
                            menu_nodes(app, ui, &nodes, &mut clicked, &mut nav, 0);
                        });'''
    s=one(s,orig,changed,"new 0.18 Popup menu bar")
    orig2="        menu_nodes(app, ui, children, &mut clicked, &mut crate::menu_keys::Nav::default(), 0);"
    changed2="        let nodes = super::platform_nodes(app, name, children);\n        menu_nodes(app, ui, &nodes, &mut clicked, &mut crate::menu_keys::Nav::default(), 0);"
    s=one(s,orig2,changed2,"context menu top-level")
    orig3='''                let r = browse_hover(nav, menu_entry(app, ui, e));
                nav.entry(ui, depth, &r, false);'''
    changed3='''                let r = browse_hover(nav, menu_entry(app, ui, e));
                app.auto.add(&format!("menu.command.{}", e.command), r.rect, &e.label);
                nav.entry(ui, depth, &r, false);'''
    return one(s,orig3,changed3,"native File menu row automation")

def commands(s: str) -> str:
    old='''pub const UI_COMMANDS: &[UiCommand] = &[
'''
    new=old+'''    uic!("platform.diagnostics", "Diagnostics…", ["Help"], None),
    uic!("bridge.importAEZip", "Import AE ZIP…", ["File"], None),
    uic!("bridge.exportProjectZip", "Export Project ZIP…", ["File"], None),
    uic!("bridge.saveZipToFiles", "Save ZIP to Files…", ["File"], None),
    uic!("bridge.importFonts", "Import Fonts…", ["File"], None),
'''
    return one(s,old,new,"UI commands registration")

def main(root: Path) -> None:
    # Caller has restored the upstream v0.18 monolithic module files first.
    edit(root,"crates/ui-egui/src/hooks.rs",hooks)
    edit(root,"crates/ui-egui/src/menus.rs",menus_module)
    edit(root,"crates/ui-egui/src/menus/entries.rs",menu_entries)
    edit(root,"crates/ui-egui/src/menus/invoke.rs",invoke)
    edit(root,"crates/ui-egui/src/menus/bar.rs",bar)
    edit(root,"crates/ui-egui/src/menus/commands.rs",commands)

if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
