"""Restore iPad Bridge command enablement lost in the v0.17 three-way merge.

v0.17 rewrote 'entry_enabled'. Its engine fallback rejects bridge.* commands
that are intentionally handled by the native host, even though the custom File
menu remains visible. Ensure host-specific enablement precedes engine fallback
and prove real menu invocation reaches the native handler.
"""
from pathlib import Path
import sys

def insert_once(text: str, before: str, after: str) -> str:
    if text.count(before) != 1:
        raise RuntimeError(f"Expected one insertion anchor {before[:100]!r}, found {text.count(before)}")
    return text.replace(before, after, 1)

def main(root: Path) -> None:
    path = root / "crates/ui-egui/src/menus.rs"
    src = path.read_text(encoding="utf-8")
    if 'fn bridge_enabled(state: &BridgeState, id: &str)' not in src:
        raise RuntimeError("Missing iPad Bridge enablement implementation")
    if 'if BRIDGE_COMMANDS.iter().any(|(command, _)| *command == id)' not in src:
        raise RuntimeError("Missing iPad Bridge command dispatcher: fix would expose inert items")
    if 'let state = bridge_state(app).ok_or("The iPad ZIP bridge is unavailable")?' not in src:
        raise RuntimeError("Missing iPad Bridge dispatch state validation")
    start = 'pub(crate) fn entry_enabled(app: &EffectcraftApp, e: &MenuEntry) -> bool {\n'
    guard = '''    // The native host implements these actions. Never ask the engine's
    // is_enabled() about bridge.* commands: it has no such commands.
    if BRIDGE_COMMANDS.iter().any(|(id, _)| *id == e.command) {
        return bridge_state(app).is_some_and(|state| bridge_enabled(&state, &e.command));
    }
    if e.command == "platform.diagnostics" {
        return app.hooks.diagnostics.is_some();
    }
'''
    if src.count(start) != 1:
        raise RuntimeError("Could not find v0.17 entry_enabled")
    # This block may have survived a future merge intact; don't insert twice.
    section = src.split(start,1)[1].split('\n}',1)[0]
    if 'return bridge_state(app).is_some_and' not in section:
        src = insert_once(src, start, start + guard)
    path.write_text(src, encoding="utf-8")
    bridge = root / "apps/effectcraft-ios/src/bridge.rs"
    code = bridge.read_text(encoding="utf-8")
    test_anchor = '''    #[test]
    fn bridge_export_is_portable_and_does_not_change_the_open_project() {'''
    new_test = '''    #[test]
    fn native_file_menu_actions_are_enabled_and_dispatch_to_host() {
        let mut session = effectcraft_host::session();
        session.execute("comp.new", json!({"name":"Bridge test", "width":320, "height":180, "frameRate":30, "duration":10})).unwrap();
        let mut app = EffectcraftApp::new(session);
        let ctx = egui::Context::default();
        let mut host = Bridge::install(&mut app, &ctx, NativeDocuments::new());
        host.show(&mut app, &ctx);
        let entries = menus::menu_items(&app);
        for cmd in ["bridge.importAEZip", "bridge.exportProjectZip", "bridge.importFonts"] {
            let entry = entries.iter().find(|e| e.id == cmd).expect("iPad bridge entry missing");
            assert!(entry.enabled, "iPad Bridge command is greyed out: {cmd}");
        }
        let save = entries.iter().find(|e| e.id == "bridge.saveZipToFiles").unwrap();
        assert!(!save.enabled, "Save ZIP should only enable after export");
        menus::invoke(&mut app, &ctx, "bridge.importAEZip", json!({})).unwrap();
        assert_eq!(host.commands.try_recv().unwrap(), "bridge.importAEZip");
        menus::invoke(&mut app, &ctx, "bridge.importFonts", json!({})).unwrap();
        assert_eq!(host.commands.try_recv().unwrap(), "bridge.importFonts");
        menus::invoke(&mut app, &ctx, "bridge.exportProjectZip", json!({})).unwrap();
        assert_eq!(host.commands.try_recv().unwrap(), "bridge.exportProjectZip");
    }

'''
    if "native_file_menu_actions_are_enabled_and_dispatch_to_host" not in code:
        code = insert_once(code, test_anchor, new_test + test_anchor)
    bridge.write_text(code, encoding="utf-8")
    print("Restored enabled native Bridge File actions and added real host-dispatch test", flush=True)

if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
