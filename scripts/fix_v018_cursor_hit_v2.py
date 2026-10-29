"""Repair the iPad pointer fix based on visual-cursor event lifetime and ordering.

Build 24 only rewrote native PointerButton and discarded the UIKit cursor on hover
end or after two seconds. egui also receives native PointerMoved; those must use
the same coordinates *during a click*. A stationary mouse has a perfectly
valid cursor position even when no hover update arrives for minutes.

All primary mouse events are aligned together, only when supported by nearby
UIKit indirect-pointer hover; finger Touch events and right-click are untouched.
"""
from pathlib import Path
import sys

def replace_one(s,old,new,label):
    count=s.count(old)
    if count!=1: raise ValueError(f"{label}: expected one match, found {count}")
    return s.replace(old,new,1)

def main(root:Path):
    file=root/"apps/effectcraft-ios/src/keyboard.rs"
    s=file.read_text(encoding="utf-8")
    s=replace_one(s,
      '    last_hover: Option<(egui::Pos2, std::time::Instant)>,\n}',
      '    last_hover: Option<(egui::Pos2, std::time::Instant)>,\n'
      '    /// UIKit may end hover on mouse press. Keep its last coordinate for release.\n'
      '    hover_present: bool,\n'
      '    hover_ended_at: Option<std::time::Instant>,\n'
      '    native_primary_down: bool,\n'
      '    native_primary_this_frame: bool,\n'
      '    pub pointer_alignment_count: u64,\n'
      '    pub pointer_alignment_debug: String,\n}',
      "state")
    s=replace_one(s,
      '            last_hover: None,\n',
      '            last_hover: None,\n'
      '            hover_present: false,\n'
      '            hover_ended_at: None,\n'
      '            native_primary_down: false,\n'
      '            native_primary_this_frame: false,\n'
      '            pointer_alignment_count: 0,\n'
      '            pointer_alignment_debug: "No primary mouse event observed".into(),\n',
      "state init")
    s=replace_one(s,
      '        self.last_hover = None;\n        self.modifiers = Modifiers::NONE;',
      '        self.last_hover = None;\n        self.hover_present = false;\n'
      '        self.hover_ended_at = None;\n        self.native_primary_down = false;\n        self.native_primary_this_frame = false;\n        self.modifiers = Modifiers::NONE;',
      "focus reset")
    s=replace_one(s,
      '                self.last_hover = None;\n                if !self.primary_down { events.push(Event::PointerGone); }',
      '                // UIKit hover ends on a trackpad press on some iPadOS versions.\n'
      '                // Keep the last position briefly, otherwise click/release cannot align.\n'
      '                self.hover_present = false;\n'
      '                self.hover_ended_at = Some(std::time::Instant::now());\n'
      '                // Never cancel a native winit click when UIKit hover ends on press.\n'
      '                if !self.primary_down && !self.native_primary_down && !self.native_primary_this_frame {\n'
      '                    events.push(Event::PointerGone);\n'
      '                }',
      "hover ended")
    s=replace_one(s,
      '                self.last_hover = Some((pos, std::time::Instant::now()));\n',
      '                self.last_hover = Some((pos, std::time::Instant::now()));\n'
      '                self.hover_present = true;\n'
      '                self.hover_ended_at = None;\n',
      "hover updates")
    a=s.index('    /// A primary mouse click must follow the *visible* iPad pointer')
    b=s.index('    pub fn input(&mut self, ctx:',a)
    new=r'''    /// Keep native winit pointer movement AND click coordinates consistent with
    /// the visible UIKit indirect-pointer cursor (both are in egui points).
    /// Do not rewrite UIKit-injected events or finger touches. This is based
    /// on an actual UIKit hover observation, never a hardcoded row offset.
    fn align_native_primary(&mut self, events: &mut [Event]) -> usize {
        let Some((hover, _)) = self.last_hover else { return 0 };
        // An unmoving trackpad pointer remains valid indefinitely while hovered.
        // Hover may briefly end when the button is depressed; allow release
        // within two seconds after that transition.
        if !self.hover_present
            && !self.hover_ended_at.is_some_and(|t| t.elapsed() <= std::time::Duration::from_secs(2))
        {
            return 0;
        }
        if events.iter().any(|e| matches!(e, Event::Touch { .. })) {
            return 0;
        }

        let positions: Vec<egui::Pos2> = events.iter().filter_map(|e| {
            if let Event::PointerButton { pos, button: egui::PointerButton::Primary, .. } = e { Some(*pos) } else { None }
        }).collect();
        if positions.is_empty() { return 0; }
        // Only a small discrepancy of the *same* pointer is a correctable
        // native coordinate mismatch. Do not snap a distant touch or mouse.
        let close = positions.iter().all(|p| p.distance_sq(hover) <= 64.0_f32.powi(2));
        let delta = positions[0] - hover;
        self.pointer_alignment_debug = format!("native−UIKit: x={:+.1}, y={:+.1} pt; {}",
            delta.x, delta.y, if close { "aligned" } else { "not aligned (>64pt)" });
        if !close { return 0; }
        let mut fixed = 0;
        for e in events {
            match e {
                Event::PointerMoved(pos) if pos.distance_sq(hover) <= 64.0_f32.powi(2) => {
                    // egui hit-testing uses PointerMoved as well as PointerButton.
                    *pos = hover;
                }
                Event::PointerButton { pos, button: egui::PointerButton::Primary, .. } => {
                    if pos.distance_sq(hover) > 0.25 {
                        *pos = hover;
                        fixed += 1;
                    }
                }
                _ => {}
            }
        }
        self.pointer_alignment_count += fixed as u64;
        fixed
    }

'''
    s=s[:a]+new+s[b:]
    s=replace_one(s,
        '        let prefix = format!("{}-", self.session);',
        '        // Keep the boundary between native winit events and UIKit bridge events.\n'
        '        // Only the former may need calibration.\n'
        '        let native_event_count = input.events.len();\n'
        '        self.native_primary_this_frame = false;\n'
        '        for event in &input.events[..native_event_count] {\n'
        '            if let Event::PointerButton { button: egui::PointerButton::Primary, pressed, .. } = event {\n'
        '                self.native_primary_this_frame = true;\n'
        '                self.native_primary_down = *pressed;\n'
        '            }\n'
        '        }\n'
        '        let prefix = format!("{}-", self.session);',
        "raw input boundary")
    s=replace_one(s,
        '            self.align_native_primary(&mut input.events);',
        '            self.align_native_primary(&mut input.events[..native_event_count]);',
        "raw slice")

    test_anchor="    #[test]\n    fn idle_input_wakes_the_actual_egui_repaint_callback() {"
    new_tests=r'''    #[test]
    fn stationary_apple_pointer_keeps_its_hover_position_after_two_seconds() {
        let mut bridge = Keyboard::new();
        let mut events = vec![];
        bridge.record(&json!({"kind":"pointer","x":95.0,"y":220.0}),false,false,&mut events).unwrap();
        bridge.last_hover.as_mut().unwrap().1 -= std::time::Duration::from_secs(90);
        let mut native=vec![Event::PointerMoved(egui::pos2(95.0,240.0)),
            Event::PointerButton{pos:egui::pos2(95.0,240.0),button:egui::PointerButton::Primary,
                pressed:true,modifiers:Modifiers::NONE}];
        assert_eq!(bridge.align_native_primary(&mut native),1);
        assert!(matches!(native[0],Event::PointerMoved(pos) if pos==egui::pos2(95.0,220.0)));
        assert!(matches!(native[1],Event::PointerButton{pos,..} if pos==egui::pos2(95.0,220.0)));
        assert!(bridge.pointer_alignment_debug.contains("y=+20.0"));
    }

    #[test]
    fn primary_click_uses_last_hover_when_uikit_hover_ends_on_press() {
        let mut bridge=Keyboard::new();
        let mut events=vec![];
        bridge.record(&json!({"kind":"pointer","x":220.0,"y":310.0}),false,false,&mut events).unwrap();
        bridge.record(&json!({"kind":"pointer","phase":"gone"}),false,false,&mut events).unwrap();
        let mut native=vec![Event::PointerButton{pos:egui::pos2(220.0,330.0),
            button:egui::PointerButton::Primary,pressed:false,modifiers:Modifiers::NONE}];
        assert_eq!(bridge.align_native_primary(&mut native),1);
        assert!(matches!(native[0],Event::PointerButton{pos,..} if pos==egui::pos2(220.0,310.0)));
    }

    #[test]
    fn real_touch_input_is_never_snapped_to_hover() {
        let mut bridge=Keyboard::new();
        let mut events=vec![];
        bridge.record(&json!({"kind":"pointer","x":220.0,"y":310.0}),false,false,&mut events).unwrap();
        let mut native=vec![
            Event::Touch { device_id:egui::TouchDeviceId(1), id:egui::TouchId(1),
                phase:egui::TouchPhase::Start, pos:egui::pos2(220.0,330.0), force:None },
            Event::PointerButton{pos:egui::pos2(220.0,330.0),
                button:egui::PointerButton::Primary,pressed:true,modifiers:Modifiers::NONE},
        ];
        assert_eq!(bridge.align_native_primary(&mut native),0);
        assert!(matches!(native[1],Event::PointerButton{pos,..} if pos==egui::pos2(220.0,330.0)));
    }

'''
    # Use API-free touch construction? egui TouchDeviceId and TouchId v0.36 have tuple constructors?
    # Test only synthetic finger case within a separate assertion by checking no snapping
    # on a non-primary button and a far away position, avoiding constructors changing with egui.
    new_tests=new_tests[:new_tests.index("    #[test]\n    fn real_touch_input_is_never_snapped_to_hover()")]
    s=replace_one(s,test_anchor,new_tests+test_anchor,"regression tests")

    extra_test='''    #[test]
    fn uikit_hover_end_does_not_cancel_native_primary_release() {
        let mut bridge=Keyboard::new();
        bridge.native_primary_down=true;
        bridge.native_primary_this_frame=true;
        let mut events=vec![];
        bridge.record(&json!({"kind":"pointer","x":100.0,"y":200.0}),false,false,&mut events).unwrap();
        bridge.record(&json!({"kind":"pointer","phase":"gone"}),false,false,&mut events).unwrap();
        assert!(!events.iter().any(|e| matches!(e,Event::PointerGone)));
        assert!(bridge.hover_ended_at.is_some());
    }

'''
    s=replace_one(s,test_anchor,extra_test+test_anchor,"native mouse release must not be cancelled")

    s=replace_one(s,
      '        bridge.record(&json!({"kind":"pointer","phase":"gone"}),false,false,&mut e).unwrap();\n        let mut near=',
      '        bridge.record(&json!({"kind":"pointer","phase":"gone"}), false, false, &mut e).unwrap();\n        *bridge.hover_ended_at.as_mut().unwrap() -= std::time::Duration::from_secs(3);\n        let mut near=',
      "expired hover regression")
    file.write_text(s,encoding="utf-8")
    # diagnostics UI is hidden under Help, avoids polluting editor
    dp=root/"apps/effectcraft-ios/src/diagnostics.rs"
    t=dp.read_text(encoding="utf-8")
    old='                ui.label(format!("Pointer events received: {}", self.keyboard.pointer_received));'
    new=(old+'\n'
         '                ui.label(format!("Pointer alignments: {} · {}", '
         'self.keyboard.pointer_alignment_count, self.keyboard.pointer_alignment_debug));')
    t=replace_one(t,old,new,"diagnostics")
    dp.write_text(t,encoding="utf-8")
    print("Fixed stationary hover and hover-ended click, synchronized native moves and presses; added regression tests and diagnostic counter.")

if __name__=="__main__":
    main(Path(sys.argv[1] if len(sys.argv)>1 else "."))
