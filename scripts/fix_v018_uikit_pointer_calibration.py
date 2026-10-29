"""Give physical iPad pointer clicks a persistent, inspectable Y calibration.

Build 26 verified that the iPad trackpad's UIKit primary tap recognizer runs,
but a visible row vs hit-target mismatch remains on the actual device.
We must stop guessing offsets. Keep normal touch, secondary click and drag
paths unchanged, add a live calibration slider and a visible tap-position
crosshair. The value is persisted locally, not silently guessed.
"""
from pathlib import Path
import sys

def once(s: str, old: str, new: str, label: str) -> str:
    n = s.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {n}")
    return s.replace(old, new, 1)

def patch(root: Path):
    path = root / "apps/effectcraft-ios/src/keyboard.rs"
    s = path.read_text(encoding="utf-8")
    s = once(s,
        '    pub pointer_alignment_debug: String,\n}',
        '    pub pointer_alignment_debug: String,\n'
        '    /// Correction in egui points, used only by UIKit primary trackpad taps.\n'
        '    pub primary_y_adjust: f32,\n'
        '    /// Most recent UIKit primary click, after calibration, with timestamp.\n'
        '    pub recent_primary: Option<(egui::Pos2, std::time::Instant)>,\n}',
        "calibration state")
    s = once(s,
        '        let time = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|t| t.as_nanos()).unwrap_or(0);\n',
        '        let time = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|t| t.as_nanos()).unwrap_or(0);\n'
        '        let primary_y_adjust = std::fs::read_to_string(home.join("Library/Caches/EffectCraft/Keyboard11/pointer-y-offset.txt"))\n'
        '            .ok().and_then(|s| s.trim().parse::<f32>().ok())\n'
        '            .filter(|v| v.is_finite() && (-48.0..=48.0).contains(v)).unwrap_or(0.0);\n',
        "load persisted offset")
    s = once(s,
        '            pointer_alignment_debug: "No primary mouse event observed".into(),\n',
        '            pointer_alignment_debug: "No primary mouse event observed".into(),\n'
        '            primary_y_adjust,\n'
        '            recent_primary: None,\n',
        "initialize")
    s = once(s,
        '            let pos = egui::pos2(x as f32, y as f32);\n',
        '            let is_uikit_primary = value["origin"].as_str() == Some("uikit-primary-tap")\n'
        '                && value["button"].as_str() == Some("primary");\n'
        '            let pos = egui::pos2(x as f32, y as f32 + if is_uikit_primary { self.primary_y_adjust } else { 0.0 });\n'
        '            if is_uikit_primary && value["down"].as_bool() == Some(true) {\n'
        '                self.recent_primary = Some((pos, std::time::Instant::now()));\n'
        '            }\n',
        "apply only to physical iPad primary tap")

    marker = '    pub fn output(&mut self, ctx: &egui::Context, blocked: bool) -> Result<(), String> {'
    setter = '''    pub fn save_primary_y_adjust(&mut self, correction: f32) -> Result<(), String> {
        if !correction.is_finite() {
            return Err("Invalid pointer calibration".into());
        }
        self.primary_y_adjust = correction.clamp(-48.0, 48.0);
        std::fs::create_dir_all(&self.directory).map_err(|e| e.to_string())?;
        std::fs::write(self.directory.join("pointer-y-offset.txt"), format!("{:.2}", self.primary_y_adjust))
            .map_err(|e| e.to_string())
    }

'''
    s = once(s, marker, setter + marker, "calibration persistence")

    test_marker = '    #[test]\n    fn idle_input_wakes_the_actual_egui_repaint_callback() {'
    test = '''    #[test]
    fn only_real_uikit_primary_taps_receive_persistent_vertical_calibration() {
        let mut bridge = Keyboard::new();
        bridge.primary_y_adjust = -13.0;
        let mut events=vec![];
        bridge.record(&json!({"kind":"pointer","origin":"uikit-primary-tap","button":"primary",
            "x":120.0,"y":400.0,"down":true}), false, false, &mut events).unwrap();
        assert!(events.iter().any(|e| matches!(e, Event::PointerButton {
            pos, button:egui::PointerButton::Primary, pressed:true, ..
        } if pos.x==120.0 && pos.y==387.0)));
        assert!(bridge.recent_primary.is_some());

        events.clear();
        bridge.record(&json!({"kind":"pointer","x":120.0,"y":400.0}), false, false, &mut events).unwrap();
        assert!(events.contains(&Event::PointerMoved(egui::pos2(120.0,400.0))));
        events.clear();
        bridge.record(&json!({"kind":"pointer","button":"secondary","x":120.0,"y":400.0,"down":true}),
            false, false, &mut events).unwrap();
        assert!(events.iter().any(|e| matches!(e, Event::PointerButton {
            pos, button:egui::PointerButton::Secondary, pressed:true, ..
        } if pos.y==400.0)));
    }

'''
    s = once(s,test_marker,test + test_marker,"keyboard regression test")
    path.write_text(s, encoding="utf-8")

    dp=root/"apps/effectcraft-ios/src/diagnostics.rs"
    d=dp.read_text(encoding="utf-8")
    marker='                ui.label(format!("Pointer events received: {}", self.keyboard.pointer_received));'
    replacement=marker+'''
                ui.separator();
                ui.strong("Physical iPad trackpad cursor calibration");
                ui.label("If clicking above a layer selects it, try a negative correction. This changes ONLY UIKit primary taps, not touch or right click.");
                let mut pointer_offset = self.keyboard.primary_y_adjust;
                ui.horizontal(|ui| {
                    let slider = egui::Slider::new(&mut pointer_offset, -48.0..=48.0)
                        .step_by(1.0).text("Y correction (points)");
                    if ui.add(slider).changed() {
                        if let Err(error) = self.keyboard.save_primary_y_adjust(pointer_offset) {
                            self.app.ui.status = error;
                        }
                    }
                    if ui.button("Reset 0").clicked() {
                        if let Err(error) = self.keyboard.save_primary_y_adjust(0.0) {
                            self.app.ui.status = error;
                        }
                    }
                });
                if let Some((pos, _)) = self.keyboard.recent_primary {
                    ui.label(format!("Last UIKit primary tap after correction: x={:.1}, y={:.1}", pos.x, pos.y));
                }
                ui.label("A green crosshair marks the last UIKit left-click for 10 seconds. Compare it with the visible cursor/layer row.");
'''
    d=once(d,marker,replacement,"diagnostics controls")
    marker='        if self.open {\n            ctx.request_repaint_after(std::time::Duration::from_millis(100));'
    added='''        if let Some((pos, at)) = self.keyboard.recent_primary {
            if at.elapsed() < std::time::Duration::from_secs(10) {
                let p = ctx.debug_painter();
                let c = egui::Color32::LIGHT_GREEN;
                p.circle_stroke(pos, 6.0, egui::Stroke::new(2.0, c));
                p.line_segment([pos + egui::vec2(-10.0, 0.0), pos + egui::vec2(10.0, 0.0)], egui::Stroke::new(1.5, c));
                p.line_segment([pos + egui::vec2(0.0, -10.0), pos + egui::vec2(0.0, 10.0)], egui::Stroke::new(1.5, c));
            }
        }
'''
    d=once(d,marker,added+marker,"green pointer calibration crosshair")
    d=once(d,'"Diagnostics · build 26"','"Diagnostics · build 27"',"version label")
    dp.write_text(d,encoding="utf-8")
    main=root/"apps/effectcraft-ios/src/main.rs"
    m=main.read_text(encoding="utf-8")
    m=once(m,'"build=26 startup','"build=27 startup',"startup log")
    m=once(m,'"EffectCraft · build 26. RAM:','"EffectCraft · build 27. RAM:',"status")
    main.write_text(m,encoding="utf-8")
    print("Build27: slider + persistent UIKit primary tap calibration + 10s green crosshair + tests", flush=True)

if __name__ == "__main__":
    patch(Path(sys.argv[1] if len(sys.argv)>1 else "."))
