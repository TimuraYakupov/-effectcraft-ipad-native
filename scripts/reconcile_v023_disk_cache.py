"""Rebase the iPad disk-cache overlay on the complete upstream v0.23 module.

The 0.21->0.23 three-way merge with -X ours can leave a hybrid disk_cache.rs:
old Queue/Job structs but new frame file stamps and write_format calls. That
hybrid cannot compile and risks corrupting previews. Start from upstream's
coherent implementation, then apply only bounded, iOS-specific safeguards.
"""
from pathlib import Path
import subprocess
import sys


def replace_once(source: str, old: str, new: str) -> str:
    if source.count(old) != 1:
        raise RuntimeError(f"Unexpected upstream v0.23 cache layout: {old[:90]}")
    return source.replace(old, new, 1)


def main(root: Path, commit: str) -> None:
    target = root / "crates/render/src/disk_cache.rs"
    original = subprocess.check_output(
        ["git", "-C", str(root), "show", f"{commit}:crates/render/src/disk_cache.rs"],
        text=True,
    )
    if 'pub fn drop_generation(&self)' not in original or 'fn write_format(&self' not in original:
        raise RuntimeError("Wrong version of disk-cache module; refusing overlay")

    # Keep upstream 0.23's file-stamp format, stale-file protection, distinct
    # frame queue and free-space reservation. Limit only the iOS queue memory
    # to the native preview's previous 32 MiB bound.
    original = replace_once(
        original,
        '#[cfg(not(target_arch = "wasm32"))]\nconst FRAME_QUEUE_BYTES: usize = 1 << 30;',
        '#[cfg(all(not(target_arch = "wasm32"), target_os = "ios"))]\n'
        'const FRAME_QUEUE_BYTES: usize = 32 << 20;\n'
        '#[cfg(all(not(target_arch = "wasm32"), not(target_os = "ios")))]\n'
        'const FRAME_QUEUE_BYTES: usize = 1 << 30;',
    )

    # Compatibility alias for native iPad diagnostics: upstream renamed
    # DiskStats.errors to .failed. Both counters refer to the same failures.
    original = replace_once(
        original,
        '    pub failed: u64,\n}',
        '    pub failed: u64,\n'
        '    /// iPad diagnostic alias for the upstream failed-write count.\n'
        '    pub errors: u64,\n}',
    )
    original = replace_once(
        original,
        '            failed: self.failed.load(Ordering::Relaxed),\n',
        '            failed: self.failed.load(Ordering::Relaxed),\n'
        '            errors: self.failed.load(Ordering::Relaxed),\n',
    )

    # Failed disk writes on a storage-constrained iPad should not keep
    # allocating/compressing frames before another attempted write.
    original = replace_once(
        original,
        '    pub fn accepts_writes(&self) -> bool {\n'
        '        let (max, limit) = (self.max_bytes(), self.limit_bytes());',
        '    pub fn accepts_writes(&self) -> bool {\n'
        '        #[cfg(target_os = "ios")]\n'
        '        if self.failed.load(Ordering::Relaxed) > 0 {\n'
        '            return false;\n'
        '        }\n'
        '        let (max, limit) = (self.max_bytes(), self.limit_bytes());',
    )

    # The native diagnostic panel still uses can_prefetch() to explain why
    # disk prefetch is paused. Preserve that API using the v0.23 effective
    # free-space cap rather than only the older max_bytes setting.
    before = "struct Meta {"
    if original.count(before) != 1:
        raise RuntimeError("Unexpected v0.23 DiskStats/Meta boundary")
    original = original.replace(
        before,
        """impl DiskStats {
    /// Leave room for the next cached frame, including the disk free-space
    /// reserve introduced upstream; suspend after an I/O write failure.
    pub fn can_prefetch(&self) -> bool {
        let limit = self.limit_bytes.min(self.max_bytes);
        self.errors == 0 && limit > 0 && self.bytes < limit.saturating_sub(limit / 10)
    }
}

struct Meta {""",
        1,
    )

    target.write_text(original, encoding="utf-8")
    print(
        "Reconciled complete upstream 0.23 cache: file stamps, queue priority, "
        "32 MiB iPad frame queue, failed-write fallback",
        flush=True,
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: reconcile_v023_disk_cache.py <root> <commit>")
    main(Path(sys.argv[1]), sys.argv[2])
