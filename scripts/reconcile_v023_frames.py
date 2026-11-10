"""Keep official EffectCraft 0.23 frame scheduling intact with native iPad limits.

The native 0.18 frame-renderer patch and upstream 0.23 f16/virtual-media
changes overlap. A three-way -X ours merge leaves mixed signatures and missing
F16 types. Replace the hybrid with authentic upstream code, then reapply
small supported iPad-specific limits and the two APIs consumed by the native
iPad UI overlay.
"""
from pathlib import Path
import subprocess
import sys


def replace_one(src: str, old: str, new: str) -> str:
    if src.count(old) != 1:
        raise RuntimeError(f"Unexpected upstream 0.23 frames layout: {old[:110]!r} (found {src.count(old)})")
    return src.replace(old, new, 1)


def main(root: Path, upstream: str) -> None:
    path = root / "crates/ui-egui/src/frames.rs"
    src = subprocess.check_output(
        ["git", "-C", str(root), "show", f"{upstream}:crates/ui-egui/src/frames.rs"],
        text=True,
    )
    if "mod f16;" not in src or "pub use f16::{F16_PIXEL_BYTES, F16Frame};" not in src:
        raise RuntimeError("Expected native half-float 0.23 preview implementation")

    src = replace_one(
        src,
        "const GPU_BUDGET: usize = 1 << 30;",
        'const IPAD_PREVIEW_MAX: usize = 2 << 30;\n'
        'const GPU_BUDGET: usize = if cfg!(target_os = "ios") { 256 << 20 } else { 1 << 30 };',
    )
    src = replace_one(
        src,
        'const GPU_RECOVERY_INTERVAL: std::time::Duration = std::time::Duration::from_secs(30);',
        'const GPU_RECOVERY_INTERVAL: std::time::Duration = std::time::Duration::from_secs(30);\n\n'
        '/// RAM preview usage returned to the native iPad diagnostics.\n'
        '#[derive(Clone, Copy, Debug)]\n'
        'pub struct PreviewCacheUsage {\n'
        '    pub bytes: usize,\n'
        '    pub gpu_bytes: usize,\n'
        '    pub frames: usize,\n'
        '    pub budget: usize,\n'
        '}',
    )

    src = replace_one(
        src,
        'let threads = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(2, 16);',
        'let threads = if cfg!(target_os = "ios") { 1 } else { std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4).clamp(2, 16) };',
    )
    src = replace_one(
        src,
        'budget: 3 << 30, gpu_budget: GPU_BUDGET, gpu_pressure: None',
        'budget: if cfg!(target_os = "ios") { 128 << 20 } else { 3 << 30 }, gpu_budget: GPU_BUDGET, gpu_pressure: None',
    )
    src = replace_one(
        src,
        '''            pool: rayon::ThreadPoolBuilder::new()
                .num_threads(threads)
                .thread_name(|i| format!("ec-frame-{i}"))
                .panic_handler(|_| log::error!("a frame render panicked; that frame was skipped"))
                .build()
                .ok(),''',
        '''            pool: {
                let builder = rayon::ThreadPoolBuilder::new()
                    .num_threads(threads)
                    .thread_name(|i| format!("ec-frame-{i}"))
                    .panic_handler(|_| log::error!("a frame render panicked; that frame was skipped"));
                #[cfg(target_os = "ios")]
                let builder = builder.stack_size(8 << 20);
                let result = builder.build();
                #[cfg(target_os = "ios")]
                match &result {
                    Ok(pool) => log::info!(target: "effectcraft_diagnostics", "frame_pool workers={} stack_mib=8", pool.current_num_threads()),
                    Err(error) => log::error!(target: "effectcraft_diagnostics", "frame_pool creation failed, fallback pool active: {error}"),
                }
                result.ok()
            },''',
    )
    src = replace_one(
        src,
        '''    pub fn is_cached(&self, k: &FrameKey) -> bool {
        self.cache.lock().map(|c| c.map.contains_key(k)).unwrap_or(false)
    }

    pub fn inflight(&self) -> usize {''',
        '''    pub fn is_cached(&self, k: &FrameKey) -> bool {
        self.cache.lock().map(|c| c.map.contains_key(k)).unwrap_or(false)
    }

    /// Non-blocking disk preview index check for the iPad timeline.
    /// A missing content key is scheduled on a worker, not hashed by the UI.
    pub fn is_cached_on_disk(&self, src: &RenderSource, key: &FrameKey) -> bool {
        #[cfg(target_arch = "wasm32")]
        {
            let _ = (src, key);
            false
        }
        #[cfg(not(target_arch = "wasm32"))]
        {
            let Some(dc) = &src.disk else { return false };
            let known = self.content_keys.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
                .get(&(key.revision, key.comp)).copied();
            let Some(content) = known else {
                self.request_content_key(src.project.clone(), key.revision, key.comp);
                return false;
            };
            let dk = disk_cache::frame_key(content, key.frame, key.scale, key.view ^ key.opts);
            dc.contains(disk_cache::Kind::Frame, dk)
        }
    }

    pub fn inflight(&self) -> usize {''',
    )
    src = replace_one(
        src,
        '''    pub fn set_budget(&self, bytes: usize) {
        if let Ok(mut c) = self.cache.lock() {
            c.budget = bytes;
            c.evict_to_budget();
        }
    }

    pub fn budget(&self) -> usize {''',
        '''    pub fn set_budget(&self, bytes: usize) {
        if let Ok(mut c) = self.cache.lock() {
            c.budget = if cfg!(target_os = "ios") { bytes.min(IPAD_PREVIEW_MAX) } else { bytes };
            c.evict_to_budget();
        }
    }

    pub fn cache_usage(&self) -> Option<PreviewCacheUsage> {
        let c = self.cache.lock().ok()?;
        Some(PreviewCacheUsage { bytes: c.bytes, gpu_bytes: c.gpu_bytes, frames: c.map.len(), budget: c.budget })
    }

    pub fn budget(&self) -> usize {''',
    )

    f16_path = root / "crates/ui-egui/src/frames/f16.rs"
    if not f16_path.is_file():
        f16_path.parent.mkdir(parents=True, exist_ok=True)
        f16_path.write_text(
            subprocess.check_output(
                ["git", "-C", str(root), "show", f"{upstream}:crates/ui-egui/src/frames/f16.rs"],
                text=True,
            ),
            encoding="utf-8",
        )
    path.write_text(src, encoding="utf-8")
    print("Restored official 0.23 f16/frame scheduler and native iPad 2 GB cache cap, pointer-compatible frame cache APIs", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: reconcile_v023_frames.py <root> <upstream>")
    main(Path(sys.argv[1]), sys.argv[2])
