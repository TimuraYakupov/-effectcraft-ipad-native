"""Fix the visible iPad pointer vs native primary-click coordinate mismatch.

The UIKit hover recognizer and winit's primary-button path are independent:
with iPad pointer acceleration/viewport insets the click can land roughly one
Timeline row below the visible cursor. When a recent UIKit hover position
matches the same physical pointer within a small radius, use that accurate
position for winit primary presses/releases. Never shift touches globally,
never change the secondary-click bridge or touch drag/drop.
"""
from pathlib import Path
import sys

def exactly(text, old, new, label):
    n=text.count(old)
    if n!=1:
        raise RuntimeError(f"{label}: expected one anchor, got {n}")
    return text.replace(old,new,1)

def main(root: Path):
    path=root/"apps/effectcraft-ios/src/keyboard.rs"
    s=path.read_text(encoding="utf-8")
    s=exactly(s,
        "    primary_down: bool,\n}",
        "    primary_down: bool,\n    /// The visual UIKit indirect-pointer hover, in egui points.\n    last_hover: Option<(egui::Pos2, std::time::Instant)>,\n}",
        "last_hover field")
    s=exactly(s,
        "            primary_down: false,\n",
        "            primary_down: false,\n            last_hover: None,\n",
        "hover initialization")
    s=exactly(s,
        "        self.primary_down = false;\n        self.modifiers = Modifiers::NONE;",
        "        self.primary_down = false;\n        self.last_hover = None;\n        self.modifiers = Modifiers::NONE;",
        "focus loss")
    s=exactly(s,
        '            if value["phase"].as_str() == Some("gone") {\n                if !self.primary_down { events.push(Event::PointerGone); }',
        '            if value["phase"].as_str() == Some("gone") {\n                self.last_hover = None;\n                if !self.primary_down { events.push(Event::PointerGone); }',
        "hover leave")
    s=exactly(s,
        '            let pos = egui::pos2(x as f32, y as f32);\n            events.push(Event::PointerMoved(pos));',
        '            let pos = egui::pos2(x as f32, y as f32);\n            if value["down"].is_null() {\n                self.last_hover = Some((pos, std::time::Instant::now()));\n            }\n            events.push(Event::PointerMoved(pos));',
        "UIKit visual hover")
    anchor="    pub fn input(&mut self, ctx: &egui::Context, input: &mut egui::RawInput, blocked: bool) -> Result<(), String> {"
    impl='''    /// A primary mouse click must follow the *visible* iPad pointer, not the
    /// occasionally inset-adjusted winit position. Do not mutate multitouch
    /// events or native events with no nearby, recent UIKit hover.
    fn align_native_primary(&self, events: &mut [Event]) -> usize {
        let Some((hover, at)) = self.last_hover else { return 0 };
        if at.elapsed() > std::time::Duration::from_secs(2) {
            return 0;
        }
        let mut fixed = 0;
        for event in events {
            if let Event::PointerButton { pos, button: egui::PointerButton::Primary, .. } = event {
                let d = *pos - hover;
                // The reported bug is ~one row high. Large separations mean
                // this is a real touch elsewhere, not the indirect pointer.
                if d.length_sq() > 0.25 && d.length_sq() <= 32.0 * 32.0 {
                    log::debug!(target: "effectcraft_pointer",
                        "Aligned primary click to visual pointer (delta {:.1}, {:.1})", d.x, d.y);
                    *pos = hover;
                    fixed += 1;
                }
            }
        }
        fixed
    }

'''
    s=exactly(s,anchor,impl+anchor,"pointer normalization routine")
    old='''        if had_records && input.focused && input.events.iter().any(|e| matches!(e, Event::WindowFocused(false))) {'''
    new='''        // RawInput already contains winit's mouse clicks. UIKit hover records
        // were appended above: apply their coordinates to the native primary
        // buttons before egui hit-tests any layer or other widget.
        if !blocked {
            self.align_native_primary(&mut input.events);
        }
        if had_records && input.focused && input.events.iter().any(|e| matches!(e, Event::WindowFocused(false))) {'''
    s=exactly(s,old,new,"native raw input alignment")
    tests='''    #[test]
    fn primary_click_follows_visible_hover_not_the_offset_native_y() {
        let mut bridge = Keyboard::new();
        let mut hover_events=vec![];
        bridge.record(&json!({"kind":"pointer","x":130.0,"y":383.0}),false,false,&mut hover_events).unwrap();
        let mut native = vec![
            Event::PointerButton { pos: egui::pos2(130.0,396.0), button: egui::PointerButton::Primary, pressed:true, modifiers:Modifiers::NONE },
            Event::PointerButton { pos: egui::pos2(130.0,396.0), button: egui::PointerButton::Primary, pressed:false, modifiers:Modifiers::NONE },
        ];
        assert_eq!(bridge.align_native_primary(&mut native), 2);
        for e in native {
            assert!(matches!(e,Event::PointerButton { pos, .. } if pos==egui::pos2(130.0,383.0)));
        }
    }

    #[test]
    fn remote_touch_and_secondary_click_must_not_snap_to_old_hover() {
        let mut bridge=Keyboard::new();
        let mut e=vec![];
        bridge.record(&json!({"kind":"pointer","x":130.0,"y":383.0}),false,false,&mut e).unwrap();
        let mut native=vec![
            Event::PointerButton { pos: egui::pos2(360.0,430.0), button: egui::PointerButton::Primary, pressed:true, modifiers:Modifiers::NONE },
            Event::PointerButton { pos: egui::pos2(130.0,396.0), button: egui::PointerButton::Secondary, pressed:true, modifiers:Modifiers::NONE },
        ];
        assert_eq!(bridge.align_native_primary(&mut native), 0);
        assert!(matches!(native[0],Event::PointerButton{pos,..} if pos==egui::pos2(360.0,430.0)));
        assert!(matches!(native[1],Event::PointerButton{pos,..} if pos==egui::pos2(130.0,396.0)));
        bridge.record(&json!({"kind":"pointer","phase":"gone"}),false,false,&mut e).unwrap();
        let mut near=vec![Event::PointerButton{pos:egui::pos2(130.0,395.0),button:egui::PointerButton::Primary,pressed:true,modifiers:Modifiers::NONE}];
        assert_eq!(bridge.align_native_primary(&mut near),0);
    }

'''
    s=exactly(s,
        "    #[test]\n    fn idle_input_wakes_the_actual_egui_repaint_callback() {",
        tests+"    #[test]\n    fn idle_input_wakes_the_actual_egui_repaint_callback() {",
        "pointer alignment tests")
    path.write_text(s,encoding="utf-8")
    print("Normalized native iPad primary clicks to the visual UIKit cursor, with tests",flush=True)

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
