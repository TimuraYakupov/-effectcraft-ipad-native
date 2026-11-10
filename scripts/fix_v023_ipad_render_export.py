"""Restore the native iPad Render Queue output picker after v0.23 merge.

Wires Output To -> native egui destination dialog and relocates imported
desktop/AEP render destinations into writable Documents/EffectCraft/Renders.
The final provider/folder is picked via UIKit AFTER the video is written.
No security-scoped provider URL is passed to a streaming movie encoder.
"""
from pathlib import Path
import shutil
import sys


def replace_once(path: Path, old: str, new: str):
    source = path.read_text(encoding="utf-8")
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one edit site, found {count}: {old[:120]!r}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")


def main(root: Path, scripts: Path) -> None:
    hooks = root / "crates/ui-egui/src/hooks.rs"
    replace_once(
        hooks,
        '    pub pick_save_file: Option<Box<dyn Fn(&str, &str) -> Option<String>>>,',
        '    pub pick_save_file: Option<Box<dyn Fn(&str, &str) -> Option<String>>>,\n'
        '    /// iPad Render Queue Output To: asynchronous, stays in the sandbox until encoding finishes.\n'
        '    pub pick_render_output: Option<Box<dyn Fn(u64, String)>>,',
    )

    queue = root / "crates/ui-egui/src/panels/render_queue.rs"
    replace_once(
        queue,
        '''fn pick_output(app: &EffectcraftApp, it: &RenderQueueItem) -> Option<Option<String>> {
    app.hooks.save_dialog(&app.session.resolve_output(it).unwrap_or_default())
}''',
        '''fn pick_output(app: &EffectcraftApp, it: &RenderQueueItem) -> Option<Option<String>> {
    if let Some(pick) = &app.hooks.pick_render_output {
        pick(it.id, app.session.resolve_output(it).unwrap_or_default());
        return Some(None); // Async iPad dialog owns the result.
    }
    app.hooks.save_dialog(&app.session.resolve_output(it).unwrap_or_default())
}''',
    )
    replace_once(
        queue,
        "let dialog = app.hooks.pick_save_file.is_some();",
        "let dialog = app.hooks.pick_save_file.is_some() || app.hooks.pick_render_output.is_some();",
    )

    diagnostics = root / "apps/effectcraft-ios/src/diagnostics.rs"
    replace_once(
        diagnostics,
        '''    fn ui(&mut self, ui: &mut egui::Ui, frame: &mut eframe::Frame) {
        self.app.ui(ui, frame);''',
        '''    fn ui(&mut self, ui: &mut egui::Ui, frame: &mut eframe::Frame) {
        // The AEP import can retain desktop render-output paths; fix them BEFORE
        // the user can press Render. Never write into an unavailable provider URL.
        self.renders.prepare(&mut self.app);
        self.app.ui(ui, frame);''',
    )

    settings = root / "apps/effectcraft-ios/src/settings.rs"
    replace_once(
        settings,
        '''    session.load_settings();
    if first_launch {''',
        '''    session.load_settings();
    // Native rendering must always use an app-writable local destination.
    // Final Files/On My iPad/iCloud/third-party destination is selected after
    // the encoder has closed the completed movie, via UIKit export-as-copy.
    let renders = documents.join("Renders");
    if let Err(e) = std::fs::create_dir_all(&renders) {
        log::warn!("Cannot prepare native Renders folder: {e}");
    }
    let previous_output = Path::new(session.prefs.export.default_output_folder.trim());
    if !previous_output.starts_with(documents) || previous_output.as_os_str().is_empty() {
        session.prefs.export.default_output_folder = renders.to_string_lossy().into_owned();
    }
    if first_launch {''',
    )

    shutil.copyfile(scripts / "render_files_v034.rs", root / "apps/effectcraft-ios/src/render_files.rs")
    print("Updated 0.23 Render Queue: native Output To, safe imported AEP paths, automatic Save to Files", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: fix_v023_ipad_render_export.py <effectcraft root> <scripts>")
    main(Path(sys.argv[1]), Path(sys.argv[2]))
