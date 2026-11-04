"""Reconcile upstream v0.21 disk-cache free-space logic with iPad cache safety.

iPad v0.18's added `errors`, bounded compressed queue, 128 MiB guard and
`write_error` overlap with upstream v0.21's `failed` and disk-space reserve.
The naive -X ours merge leaves references to an absent field and out-of-scope
variable in write_now. Keep the *new* upstream eviction/space-reserve algorithm,
but continue using the native error counter (and expose upstream `failed`
as an alias for code that expects it).
"""
from pathlib import Path
import sys

def patch(root: Path):
    p=root/"crates/render/src/disk_cache.rs"
    s=p.read_text(encoding="utf-8")
    startmarker='    /// Write an entry now (atomic rename), then evict down to the limit.'
    endmarker='    /// Remove least recently used entries until the cache fits its limit.'
    if s.count(startmarker)!=1 or s.count(endmarker)!=1:
        raise RuntimeError("Unexpected 0.21 write_now layout; refusing unsafe cache patch")
    start=s.index(startmarker)
    end=s.index(endmarker,start)
    new='''    /// Write an entry now, retaining 0.21's free-space reserve and atomic
    /// rename plus iPad's error tracking (disk errors disable further prefetch).
    fn write_now(&self, kind: Kind, key: u128, payload: &[u8]) {
        if self.contains(kind, key) {
            return;
        }
        let path = self.path(kind, key);
        let Some(parent) = path.parent() else { return };
        if let Err(error) = std::fs::create_dir_all(parent) {
            self.write_error(&error);
            return;
        }
        let data = seal(kind, payload);
        // 0.21's free-space reserve: do not write entries that will be evicted.
        if data.len() as u64 > self.limit_bytes() {
            return;
        }
        self.evict_to(self.limit_bytes().saturating_sub(data.len() as u64));
        let n = self.tmp_counter.fetch_add(1, Ordering::Relaxed);
        let tmp = parent.join(format!("{key:032x}.tmp.{}.{n}", std::process::id()));
        if let Err(error) = std::fs::write(&tmp, &data)
            .and_then(|()| std::fs::rename(&tmp, &path)) {
            let _ = std::fs::remove_file(&tmp);
            self.write_error(&error);
            return;
        }
        self.writes.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut g) = self.index.lock() {
            g.insert(kind, key, data.len() as u64);
        }
    }

    fn write_error(&self, error: &std::io::Error) {
        if self.errors.fetch_add(1, Ordering::Relaxed) == 0 {
            log::error!("Disk cache write failed: {error}. Preview can continue using RAM.");
        }
    }

'''
    s=s[:start]+new+s[end:]
    # Keep v0.21's public DiskStats.failed field in addition to the existing
    # iPad-specific DiskStats.errors (used for prefetch backoff).
    struct_start=s.index('pub struct DiskStats {')
    struct_end=s.index('}',struct_start)
    struct=s[struct_start:struct_end]
    if 'pub errors: u64,' not in struct:
        raise RuntimeError("Native iPad error stats missing after source merge")
    if 'pub failed: u64,' not in struct:
        struct=struct.replace('    pub errors: u64,','    pub errors: u64,\n    /// Upstream v0.21 name; same counter as `errors`.\n    pub failed: u64,')
    s=s[:struct_start]+struct+s[struct_end:]
    stats_begin=s.index('    pub fn stats(&self) -> DiskStats {')
    stats_end=s.index('    /// Delete every entry',stats_begin)
    stats=s[stats_begin:stats_end]
    if 'errors: self.errors.load(Ordering::Relaxed),' not in stats:
        raise RuntimeError("Native cache error counter missing from stats initializer")
    if 'failed: self.errors.load(Ordering::Relaxed),' not in stats:
        stats=stats.replace('            errors: self.errors.load(Ordering::Relaxed),',
            '            errors: self.errors.load(Ordering::Relaxed),\n            failed: self.errors.load(Ordering::Relaxed),')
    s=s[:stats_begin]+stats+s[stats_end:]
    if 'self.failed.fetch_add(' in s:
        raise RuntimeError("Stale upstream failed counter reference remains")
    p.write_text(s,encoding="utf-8")
    print("0.21 disk cache reconciled: free-space reserve + iPad 32 MiB queue/error prefetch + failed stats alias",flush=True)

if __name__=='__main__':
    patch(Path(sys.argv[1] if len(sys.argv)>1 else '.'))
