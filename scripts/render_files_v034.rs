//! Native iPad render delivery. Render into the writable EffectCraft sandbox first,
//! then let UIDocumentPicker export a copy into ANY Files provider/folder.
//! The rendered original stays available after cancelling the destination picker.
use crate::native_documents::NativeDocuments;
use effectcraft_ui_egui::EffectcraftApp;
use effectcraft_engine::project::render_queue::{RenderQueueItem, RenderStatus};
use eframe::egui;
use std::{
    collections::{HashMap, VecDeque},
    path::{Component, Path, PathBuf},
    sync::mpsc::{self, Receiver},
};

struct OutputChoice {
    id: u64,
    filename: String,
    subfolder: String,
    error: String,
}

pub struct RenderFiles {
    requests: Receiver<Vec<String>>,
    choices: Receiver<(u64, String)>,
    choice: Option<OutputChoice>,
    work: Option<Receiver<Result<PathBuf, String>>>,
    pending: Option<String>,
    temporary: Option<PathBuf>,
    native: NativeDocuments,
    /// Queue items seen when an actual render job starts; never open a Save dialog
    /// for a historical "Done" item loaded from an .aep/.ecproj.
    tracked: Option<Vec<u64>>,
    deliveries: VecDeque<Vec<String>>,
}

impl RenderFiles {
    pub fn install(app: &mut EffectcraftApp, ctx: &egui::Context, native: NativeDocuments) -> Self {
        let (send, requests) = mpsc::sync_channel(4);
        let wake = ctx.clone();
        app.hooks.save_rendered = Some(Box::new(move |paths| {
            if paths.is_empty() || paths.len() > 4096 {
                return Err("Invalid render output count".into());
            }
            send.try_send(paths).map_err(|_| "A render export is already waiting".to_string())?;
            wake.request_repaint();
            Ok(())
        }));
        let (choose, choices) = mpsc::sync_channel(4);
        let wake = ctx.clone();
        app.hooks.pick_render_output = Some(Box::new(move |id, path| {
            if let Err(error) = choose.try_send((id, path)) {
                log::warn!("Cannot open output destination dialog: {error}");
            }
            wake.request_repaint();
        }));
        Self {
            requests,
            choices,
            choice: None,
            work: None,
            pending: None,
            temporary: None,
            native,
            tracked: None,
            deliveries: VecDeque::new(),
        }
    }

    pub fn is_open(&self) -> bool {
        self.pending.is_some() || self.work.is_some() || self.choice.is_some()
    }

    /// Rebase paths imported from desktop After Effects onto a writable iPad
    /// location. The render engine must NEVER try /Users/…, C:\\… or an
    /// arbitrary path inherited from an AEP render queue.
    pub fn prepare(&self, app: &mut EffectcraftApp) {
        if app.session.is_rendering() {
            return;
        }
        let root = crate::bridge::documents().join("Renders");
        if let Err(error) = std::fs::create_dir_all(&root) {
            app.ui.status = format!("Cannot create iPad render folder: {error}");
            return;
        }
        let changes: Vec<(u64, String)> = app
            .session
            .project
            .render_queue
            .iter()
            .filter(|item| item.render && !matches!(item.status, RenderStatus::Rendering | RenderStatus::Done | RenderStatus::Unqueued))
            .filter_map(|item| {
                let output = app.session.resolve_output(item);
                let invalid = output.as_deref().is_none_or(|p| !writable_render_path(Path::new(p), &root));
                if invalid {
                    let path = if item.output.format.is_sequence() {
                        "[compName]_[#####].[fileExtension]"
                    } else {
                        "[compName].[fileExtension]"
                    };
                    Some((item.id, path.to_owned()))
                } else {
                    None
                }
            })
            .collect();

        for (id, path) in changes {
            match app.session.execute("renderQueue.setOutput", serde_json::json!({"item": id, "path": path})) {
                Ok(_) => {
                    app.ui.status = "Output moved to EffectCraft/Renders. After rendering, choose the final destination in Files.".into();
                    log::info!(target: "effectcraft_diagnostics", "rebased AEP render path for item={id} into iPad Renders");
                }
                Err(e) => {
                    log::error!(target: "effectcraft_diagnostics", "cannot rebase render output item={id}: {e}");
                    app.ui.status = format!("Render destination: {e}");
                }
            }
        }
    }

    pub fn show(&mut self, app: &mut EffectcraftApp, ctx: &egui::Context) {
        self.observe_render(app);

        if self.choice.is_none()
            && let Ok((id, current)) = self.choices.try_recv()
        {
            let file = current.replace('\\', "/");
            let fallback = "Composition.mp4";
            let filename = file.rsplit('/').next().filter(|s| !s.is_empty()).unwrap_or(fallback).to_string();
            self.choice = Some(OutputChoice { id, filename, subfolder: String::new(), error: String::new() });
        }
        self.output_dialog(app, ctx);

        if !self.is_open() {
            if let Ok(paths) = self.requests.try_recv() {
                self.deliver(app, ctx, paths);
            } else if let Some(paths) = self.deliveries.pop_front() {
                self.deliver(app, ctx, paths);
            }
        }
        if let Some(work) = &self.work {
            match work.try_recv() {
                Ok(result) => {
                    self.work = None;
                    match result {
                        Ok(path) => { self.temporary = Some(path.clone()); self.start(app, &path); }
                        Err(error) => app.ui.status = format!("Cannot package render: {error}"),
                    }
                }
                Err(mpsc::TryRecvError::Disconnected) => {
                    self.work = None;
                    app.ui.status = "Render delivery worker stopped".into();
                }
                Err(mpsc::TryRecvError::Empty) => {}
            }
        }
        if let Some(id) = self.pending.clone() {
            if let Some(result) = self.native.poll(&id) {
                self.pending = None;
                app.ui.status = match result {
                    Ok(value) if value["cancelled"].as_bool() == Some(true) =>
                        "Save cancelled. Render remains in EffectCraft/Renders; use Save to Files to try again.".into(),
                    Ok(value) if value["ok"].as_bool() == Some(true) =>
                        "Rendered file saved to your chosen Files location.".into(),
                    Ok(value) => format!("File save returned no confirmation: {value}"),
                    Err(error) => format!("Cannot save render to Files: {error}"),
                };
                // Temporary ZIP may be disposed, but the original frames are NEVER removed.
                if let Some(path) = self.temporary.take() {
                    let _ = std::fs::remove_file(path);
                }
            }
        }
        if self.is_open() || !self.deliveries.is_empty() {
            ctx.request_repaint_after(std::time::Duration::from_millis(100));
        }
    }

    fn observe_render(&mut self, app: &mut EffectcraftApp) {
        if app.session.render_job.is_some() {
            if self.tracked.is_none() {
                self.tracked = Some(
                    app.session.project.render_queue.iter()
                        .filter(|it| it.render && !matches!(it.status, RenderStatus::Unqueued | RenderStatus::Done))
                        .map(|it| it.id)
                        .collect(),
                );
            }
            return;
        }
        let Some(ids) = self.tracked.take() else { return };
        for id in ids {
            let Some(it) = app.session.project.render_queue.iter().find(|it| it.id == id) else { continue };
            match &it.status {
                RenderStatus::Done => match completed_paths(app, it) {
                    Ok(paths) if !paths.is_empty() => {
                        if paths.iter().all(|p| Path::new(p).is_file()) {
                            self.deliveries.push_back(paths);
                        } else {
                            app.ui.status = "Render reported complete, but its output is missing. Check EffectCraft/Renders.".into();
                        }
                    }
                    Ok(_) => {}
                    Err(error) => app.ui.status = format!("Cannot offer rendered file: {error}"),
                },
                RenderStatus::Failed(error) => {
                    log::error!(target: "effectcraft_diagnostics", "render_failed item={id}: {error}");
                    app.ui.status = format!("Render failed: {error}");
                }
                _ => {}
            }
        }
    }

    fn deliver(&mut self, app: &mut EffectcraftApp, ctx: &egui::Context, paths: Vec<String>) {
        if paths.is_empty() || paths.len() > 4096 {
            app.ui.status = "Invalid render output count".into();
            return;
        }
        if paths.len() == 1 {
            self.start(app, Path::new(&paths[0]));
            return;
        }
        match self.native.staging("Rendered-Sequence.zip", "zip") {
            Err(error) => app.ui.status = error,
            Ok(output) => {
                let (send, receive) = mpsc::sync_channel(1);
                let wake = ctx.clone();
                let result = std::thread::Builder::new()
                    .name("ec-render-delivery".into())
                    .spawn(move || {
                        let result = package_sequence(&paths, &output).map(|_| output);
                        let _ = send.send(result);
                        wake.request_repaint();
                    });
                match result {
                    Ok(_) => {
                        self.work = Some(receive);
                        app.ui.status = "Packaging rendered image sequence…".into();
                    }
                    Err(error) => app.ui.status = error.to_string(),
                }
            }
        }
    }

    fn start(&mut self, app: &mut EffectcraftApp, path: &Path) {
        if !path.is_file() {
            app.ui.status = format!("Rendered output is missing: {}", path.display());
            return;
        }
        match self.native.export_copy(path) {
            Ok(id) => {
                self.pending = Some(id);
                app.ui.status = "Choose where to save the finished render in iPad Files…".into();
            }
            Err(error) => app.ui.status = format!("Files picker unavailable: {error}. Output remains in EffectCraft/Renders."),
        }
    }

    fn output_dialog(&mut self, app: &mut EffectcraftApp, ctx: &egui::Context) {
        let Some(choice) = self.choice.as_mut() else { return };
        let mut apply = false;
        let mut cancel = false;
        egui::Modal::new(egui::Id::new("ipad-render-output")).show(ctx, |ui| {
            ui.heading("Render output on iPad");
            ui.label("Set the local render filename. After rendering, iPad Files will let you choose ANY destination.");
            ui.horizontal(|ui| { ui.label("Filename:"); ui.text_edit_singleline(&mut choice.filename); });
            ui.horizontal(|ui| { ui.label("Folder in Renders (optional):"); ui.text_edit_singleline(&mut choice.subfolder); });
            if !choice.error.is_empty() {
                ui.colored_label(egui::Color32::RED, &choice.error);
            }
            ui.horizontal(|ui| {
                if ui.button("Use this output").clicked() { apply = true; }
                if ui.button("Cancel").clicked() { cancel = true; }
            });
        });
        if cancel {
            self.choice = None;
        } else if apply {
            match apply_output_choice(app, choice.id, &choice.filename, &choice.subfolder) {
                Ok(path) => {
                    app.ui.status = format!("Render output: {}. Files will ask where to save it after render.", path.display());
                    self.choice = None;
                }
                Err(error) => choice.error = error,
            }
        }
        if self.choice.is_some() { ctx.request_repaint_after(std::time::Duration::from_millis(100)); }
    }
}

fn writable_render_path(path: &Path, root: &Path) -> bool {
    path.is_absolute()
        && path.starts_with(root)
        && !path.components().any(|c| matches!(c, Component::ParentDir))
        && !path.to_string_lossy().contains(['\\', '\0'])
}

fn safe_part(part: &str) -> Result<&str, String> {
    if part.trim().is_empty() || part.len() > 160 || part == "." || part == ".."
        || part.starts_with('.')
        || part.contains(['/', '\\', ':', '<', '>', '\0'])
        || Path::new(part).components().count() != 1
    {
        return Err("Use a simple filename or folder name without slashes/colon".into());
    }
    Ok(part)
}

fn apply_output_choice(app: &mut EffectcraftApp, id: u64, name: &str, folder: &str) -> Result<PathBuf, String> {
    let item = app.session.project.render_queue.iter().find(|i| i.id == id).ok_or("Render Queue item no longer exists")?;
    let ext = item.output.format.extension();
    let name = safe_part(name.trim())?;
    let mut folder_path = crate::bridge::documents().join("Renders");
    if !folder.trim().is_empty() {
        folder_path.push(safe_part(folder.trim())?);
    }
    std::fs::create_dir_all(&folder_path).map_err(|e| format!("Cannot create render folder: {e}"))?;
    let stem = if name.to_ascii_lowercase().ends_with(&format!(".{ext}")) {
        name.to_owned()
    } else {
        format!("{name}.{ext}")
    };
    let path = folder_path.join(stem);
    app.session.execute("renderQueue.setOutput", serde_json::json!({"item": id, "path": path.to_string_lossy()}))
        .map_err(|e| e.to_string())?;
    Ok(path)
}

fn completed_paths(app: &EffectcraftApp, item: &RenderQueueItem) -> Result<Vec<String>, String> {
    if !item.output.format.is_sequence() {
        return item.last_output.clone().map(|path| vec![path]).ok_or_else(|| "Render this item first".into());
    }
    let comp = app.session.project.comp(item.comp).ok_or("Composition missing")?;
    let count = item.settings.frame_count(comp);
    if count == 0 || count > 4096 {
        return Err("Save image sequences of up to 4096 frames per ZIP".into());
    }
    let path = app.session.resolve_output(item).ok_or("Output path missing")?;
    let first = item.settings.first_frame(comp);
    (0..count)
        .map(|i| {
            let frame = first.checked_add(i as i64).ok_or_else(|| "Sequence frame number overflow".to_string())?;
            Ok(effectcraft_engine::project::render_queue::sequence_path(&path, frame))
        })
        .collect()
}

fn package_sequence(paths: &[String], output: &Path) -> Result<(), String> {
    let entries = paths
        .iter()
        .map(|path| {
            let path = PathBuf::from(path);
            let name = path.file_name().and_then(|s| s.to_str()).ok_or("Invalid sequence filename")?.to_owned();
            if !path.is_file() { return Err(format!("Rendered frame is missing: {name}")); }
            Ok((name, path))
        })
        .collect::<Result<Vec<_>, String>>()?;
    crate::store_zip::write(output, &entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_imported_desktop_paths_are_rebased() {
        let root = Path::new("/sandbox/EffectCraft/Renders");
        assert!(writable_render_path(Path::new("/sandbox/EffectCraft/Renders/movie.mp4"), root));
        assert!(!writable_render_path(Path::new("/Users/editor/Desktop/movie.mp4"), root));
        assert!(!writable_render_path(Path::new("C:\\Work\\movie.mp4"), root));
        assert!(!writable_render_path(Path::new("/sandbox/EffectCraft/Renders/../elsewhere/movie.mp4"), root));
    }

    #[test]
    fn filename_validation_rejects_traversal_and_unsafe_paths() {
        for invalid in ["", ".", "..", "/tmp/movie.mp4", "folder/file.mp4", "C:\\movie.mp4", "bad:movie.mp4"] {
            assert!(safe_part(invalid).is_err(), "{invalid}");
        }
        assert!(safe_part("Video 01.mp4").is_ok());
    }

    #[test]
    fn sequence_export_rejects_missing_frames_and_preserves_originals() {
        let root = std::env::temp_dir().join(format!("ec-render-package-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let a = root.join("frame0001.png");
        let b = root.join("frame0002.png");
        std::fs::write(&a, b"original frame one").unwrap();
        let paths = vec![a.to_string_lossy().into_owned(), b.to_string_lossy().into_owned()];
        assert!(package_sequence(&paths, &root.join("missing.zip")).is_err());
        assert!(!root.join("missing.zip").exists());
        std::fs::write(&b, b"original frame two").unwrap();
        package_sequence(&paths, &root.join("complete.zip")).unwrap();
        assert_eq!(std::fs::read(&a).unwrap(), b"original frame one");
        assert_eq!(std::fs::read(&b).unwrap(), b"original frame two");
        assert!(std::fs::metadata(root.join("complete.zip")).unwrap().len() > 32);
        let _ = std::fs::remove_dir_all(root);
    }
}
