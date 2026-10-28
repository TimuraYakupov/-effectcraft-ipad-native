"""Build 22: regression tests for active native File bridge commands."""
from pathlib import Path
import sys

def main(root: Path) -> None:
    path=root/"apps/effectcraft-ios/src/bridge.rs"
    s=path.read_text(encoding="utf-8")
    if "native_file_menu_actions_are_enabled_and_dispatch_to_host" in s:
        return
    marker='''    #[test]
    fn bridge_export_is_portable_and_does_not_change_the_open_project() {'''
    test='''    #[test]
    fn native_file_menu_actions_are_enabled_and_dispatch_to_host() {
        let mut session = effectcraft_host::session();
        session.execute("comp.new", json!({"name":"Bridge test", "width":320, "height":180, "frameRate":30, "duration":10})).unwrap();
        let mut app = EffectcraftApp::new(session);
        let ctx = egui::Context::default();
        let mut host = Bridge::install(&mut app, &ctx, NativeDocuments::new());
        host.show(&mut app, &ctx);
        let entries = menus::menu_items(&app);
        for cmd in ["bridge.importAEZip", "bridge.exportProjectZip", "bridge.importFonts"] {
            let entry = entries.iter().find(|e| e.id == cmd).expect("iPad Bridge command missing");
            assert!(entry.enabled, "iPad File menu action disabled: {cmd}");
        }
        let save=entries.iter().find(|e| e.id == "bridge.saveZipToFiles").unwrap();
        assert!(!save.enabled, "Save ZIP should only enable after preparing archive");
        for cmd in ["bridge.importAEZip", "bridge.importFonts", "bridge.exportProjectZip"] {
            menus::invoke(&mut app, &ctx, cmd, json!({})).unwrap();
            assert_eq!(host.commands.try_recv().unwrap(), cmd);
        }
    }

'''
    if s.count(marker)!=1:
        raise RuntimeError("Can't locate native bridge test insertion")
    path.write_text(s.replace(marker,test+marker),encoding="utf-8")

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
