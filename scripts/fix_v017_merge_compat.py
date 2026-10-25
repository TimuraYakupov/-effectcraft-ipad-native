"""Adapt build-19 disk-cache overlay to EffectCraft v0.17 content key generations.

v0.17 keys cached content hashes by (revision, composition, virtual-media
generation), rather than the old (revision, composition) pair. Keep the new
generation in all iPad-only RAM/disk cache reads and assertions.
"""
from pathlib import Path
import sys

def replace_exact(text: str, before: str, after: str, count: int) -> str:
    found = text.count(before)
    if found != count:
        raise RuntimeError(f"Expected {count} of {before!r}, found {found}")
    return text.replace(before, after)

def main(root: Path) -> None:
    path = root / "crates/ui-egui/src/frames.rs"
    source = path.read_text(encoding="utf-8")
    before = '''            let content = self.content_keys.lock().unwrap_or_else(std::sync::PoisonError::into_inner).get(&(key.revision, key.comp)).copied();'''
    after = '''            let epoch = self.virtual_epoch.load(Ordering::Relaxed);
            let content = self.content_keys.lock().unwrap_or_else(std::sync::PoisonError::into_inner).get(&(key.revision, key.comp, epoch)).copied();'''
    source = replace_exact(source, before, after, 1)
    source = replace_exact(source, ".insert((1, 1), content);", ".insert((1, 1, 0), content);", 1)
    source = replace_exact(source, ".insert((1, 1), content.wrapping_add(1));", ".insert((1, 1, 0), content.wrapping_add(1));", 1)
    path.write_text(source, encoding="utf-8")
    print("Adapted iPad disk-frame lookup and tests to v0.17 virtual media generation", flush=True)

if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
