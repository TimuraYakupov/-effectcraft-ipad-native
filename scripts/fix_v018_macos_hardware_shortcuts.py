"""Treat iPadOS physical keyboards like macOS for EffectCraft shortcuts.

The default desktop keymap uses Cmd/Option/Ctrl as separate modifiers.
v0.18 treats every non-macOS target as Windows/Linux: iOS Cmd becomes Ctrl,
Cmd+Ctrl chords are discarded, menu hints show Ctrl, and matching ignores
the Ctrl distinction. UIKit's HID bridge already reports Mac Cmd/Option/Ctrl
correctly. Fix only the frontend's platform shortcut policy.
"""
from pathlib import Path
import sys

def main(root: Path) -> None:
    path = root/"crates/ui-egui/src/menus/shortcuts.rs"
    s = path.read_text(encoding="utf-8")
    before = 'cfg!(target_os = "macos")'
    after = 'cfg!(any(target_os = "macos", target_os = "ios"))'
    n=s.count(before)
    if n != 4:
        raise RuntimeError(f"Expected 4 mac-only shortcuts, found {n}")
    s=s.replace(before,after)
    old='cfg!(not(target_os = "macos"))'
    new='cfg!(not(any(target_os = "macos", target_os = "ios")))'
    if s.count(old)!=1:
        raise RuntimeError("Could not find Ctrl-fallback shortcut matcher")
    s=s.replace(old,new)
    s=s.replace('/// Shortcut text in this OS\'s notation (`⇧⌘K` on macOS, `Ctrl+Shift+K` elsewhere).',
                '/// macOS and iPadOS hardware keyboards use ⌘, ⌥ and ⌃ as distinct modifiers.')
    s=s.replace('// Off macOS `Cmd` is Ctrl, so a custom Ctrl+Cmd shortcut would',
                '// Off Apple platforms `Cmd` is Ctrl, so a custom Ctrl+Cmd shortcut would')
    tests='''
#[cfg(test)]
mod physical_apple_keyboard_tests {
    use super::*;

    #[test]
    fn command_shift_binding_uses_native_apple_command_on_ios_and_macos() {
        let (mods, key) = parse_shortcut("Cmd+Shift+K").expect("valid desktop shortcut");
        assert_eq!(key, egui::Key::K);
        assert!(mods.command && mods.shift);
        let apple = cfg!(any(target_os = "macos", target_os = "ios"));
        assert_eq!(mods.mac_cmd, apple);
        assert_eq!(mods.ctrl, !apple);
        assert_eq!(shortcut_text("Cmd+Shift+K"), if apple { "⌘⇧K" } else { "Ctrl+Shift+K" });
    }

    #[test]
    fn control_is_not_command_on_apple_hardware_keyboards() {
        let (command, _) = parse_shortcut("Cmd+K").unwrap();
        let (both, _) = parse_shortcut("Ctrl+Cmd+K").unwrap();
        if cfg!(any(target_os = "macos", target_os = "ios")) {
            assert!(!command.ctrl);
            assert!(both.ctrl);
            assert!(mods_match(command, command));
            assert!(!mods_match(both, command));
            assert!(mods_match(both, both));
        }
    }
}
'''
    if "mod physical_apple_keyboard_tests" in s:
        raise RuntimeError("Already installed Apple keyboard regression")
    s+=tests
    path.write_text(s,encoding="utf-8")
    # Fail fast if the UIKit bridge does not forward all four modifiers.
    host=root/"apps/effectcraft-ios/src/keyboard.rs"
    native=host.read_text(encoding="utf-8")
    for field in ('mac_cmd,','command: mac_cmd || ctrl','ctrl,','alt: value & (1 << 19) != 0','shift: value & (1 << 17) != 0'):
        if field not in native:
            raise RuntimeError(f"Missing physical keyboard modifier bridge: {field}")
    print("iPad now uses macOS hardware shortcut policy (Cmd, Option, Control) with regression tests",flush=True)

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
