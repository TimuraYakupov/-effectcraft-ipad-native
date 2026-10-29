"""Two-point affine UIKit primary-pointer calibration for iPad.

A constant vertical offset works at one height but cannot align clicks across
the full screen if UI/viewport scaling differs. Capture unmodified UIKit
coordinates at two visible targets, solve egui_y = scale * uikit_y + offset,
persist with validation, and retain manual fine tuning. Only physical
indirect-pointer primary taps use the transform; hover, finger, right button,
and dragging remain unchanged.
"""
from pathlib import Path
import sys

def once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f"{label}: expected unique anchor, found {n}")
    return text.replace(old, new, 1)

def patch(root):
    f=root/"apps/effectcraft-ios/src/keyboard.rs"
    s=f.read_text(encoding="utf-8")

    s=once(s,
        '    pub recent_primary: Option<(egui::Pos2, std::time::Instant)>,\n}',
        '''    pub recent_primary: Option<(egui::Pos2, std::time::Instant)>,
    /// Affine UIKit→egui vertical coordinate mapping from two reference taps.
    pub primary_y_scale: f32,
    pub primary_y_origin: f32,
    pub calibration_active: bool,
    pub calibration_tap_count: u64,
    pub calibration_last_raw: Option<egui::Pos2>,
}''',
        "keyboard state fields")

    s=once(s,
        '            recent_primary: None,\n',
        '''            recent_primary: None,
            primary_y_scale: 1.0,
            primary_y_origin: 0.0,
            calibration_active: false,
            calibration_tap_count: 0,
            calibration_last_raw: None,
''',
        "default keyboard state")

    # Restore previous two-point calibration on app launch if finite/in-range.
    s=once(s,
        '        let primary_y_adjust = std::fs::read_to_string(home.join("Library/Caches/EffectCraft/Keyboard11/pointer-y-offset.txt"))',
        '''        let pointer_transform = std::fs::read_to_string(
            home.join("Library/Caches/EffectCraft/Keyboard11/pointer-affine.json")
        ).ok().and_then(|s| serde_json::from_str::<Value>(&s).ok())
            .and_then(|v| {
                let scale = v["scale"].as_f64()? as f32;
                let offset = v["offset"].as_f64()? as f32;
                if scale.is_finite() && offset.is_finite()
                    && (0.5..=1.5).contains(&scale) && offset.abs() <= 512.0 {
                    Some((scale, offset))
                } else { None }
            }).unwrap_or((1.0, 0.0));
        let primary_y_adjust = std::fs::read_to_string(home.join("Library/Caches/EffectCraft/Keyboard11/pointer-y-offset.txt"))''',
        "load calibration")

    s=once(s,
        '            primary_y_scale: 1.0,\n            primary_y_origin: 0.0,',
        '            primary_y_scale: pointer_transform.0,\n            primary_y_origin: pointer_transform.1,',
        "load saved transform")

    s=once(s,
        '''            let pos = egui::pos2(x as f32, y as f32 + if is_uikit_primary { self.primary_y_adjust } else { 0.0 });
            if is_uikit_primary && value["down"].as_bool() == Some(true) {
                self.recent_primary = Some((pos, std::time::Instant::now()));
            }
            if value["down"].is_null() {''',
        '''            let raw = egui::pos2(x as f32, y as f32);
            if is_uikit_primary && value["down"].as_bool() == Some(true) {
                self.calibration_tap_count = self.calibration_tap_count.saturating_add(1);
                self.calibration_last_raw = Some(raw);
            }
            // During calibration consume synthetic UIKit tap events before egui
            // can act on underlying project controls.
            if is_uikit_primary && self.calibration_active {
                return Ok(());
            }
            let pos = egui::pos2(raw.x,
                if is_uikit_primary {
                    raw.y * self.primary_y_scale + self.primary_y_origin + self.primary_y_adjust
                } else { raw.y });
            if is_uikit_primary && value["down"].as_bool() == Some(true) {
                self.recent_primary = Some((pos, std::time::Instant::now()));
            }
            if value["down"].is_null() {''',
        "affine tap input")

    marker = '    pub fn output(&mut self, ctx: &egui::Context, blocked: bool) -> Result<(), String> {'
    method='''    /// Save two-point calibration atomically: no arbitrary global touch offset.
    pub fn save_primary_affine(&mut self, scale: f32, offset: f32) -> Result<(), String> {
        if !scale.is_finite() || !offset.is_finite()
            || !(0.5..=1.5).contains(&scale) || offset.abs() > 512.0 {
            return Err("Invalid two-point calibration. Retry both targets.".into());
        }
        std::fs::create_dir_all(&self.directory).map_err(|e| e.to_string())?;
        let path = self.directory.join("pointer-affine.json");
        let data = json!({"scale":scale, "offset":offset}).to_string();
        write_atomic(&path, data.as_bytes()).map_err(|e| e.to_string())?;
        self.primary_y_scale = scale;
        self.primary_y_origin = offset;
        // A legacy one-point adjustment must not be stacked on the new mapping.
        self.save_primary_y_adjust(0.0)?;
        Ok(())
    }

'''
    s=once(s,marker,method+marker,"save transform")

    test_marker = '    #[test]\n    fn idle_input_wakes_the_actual_egui_repaint_callback() {'
    test = '''    #[test]
    fn two_point_transform_aligns_top_mid_and_bottom_but_not_secondary_or_hover() {
        let mut bridge=Keyboard::new();
        bridge.primary_y_scale=0.95;
        bridge.primary_y_origin=10.0;
        bridge.primary_y_adjust=0.0;
        let mut events=vec![];
        for (raw_y, expected) in [(100.0,105.0),(500.0,485.0),(900.0,865.0)] {
            events.clear();
            bridge.record(&json!({"kind":"pointer","origin":"uikit-primary-tap",
                "button":"primary","x":250.0,"y":raw_y,"down":true}), false,false,&mut events).unwrap();
            assert!(events.iter().any(|e| matches!(e,Event::PointerButton{pos,
                button:egui::PointerButton::Primary,pressed:true,..}
                if (pos.y-expected).abs()<0.01)));
        }
        assert_eq!(bridge.calibration_tap_count,3);
        bridge.calibration_active=true;
        events.clear();
        bridge.record(&json!({"kind":"pointer","origin":"uikit-primary-tap",
            "button":"primary","x":250.0,"y":500.0,"down":true}),false,false,&mut events).unwrap();
        assert!(events.is_empty());
        assert_eq!(bridge.calibration_last_raw.unwrap(),egui::pos2(250.0,500.0));
        bridge.calibration_active=false;
        bridge.record(&json!({"kind":"pointer","x":250.0,"y":500.0}),false,false,&mut events).unwrap();
        assert_eq!(events.last(),Some(&Event::PointerMoved(egui::pos2(250.0,500.0))));
        events.clear();
        bridge.record(&json!({"kind":"pointer","button":"secondary",
            "x":250.0,"y":500.0,"down":true}),false,false,&mut events).unwrap();
        assert!(events.iter().any(|e| matches!(e,Event::PointerButton{
            button:egui::PointerButton::Secondary,pos,..} if pos.y==500.0)));
    }

'''
    s=once(s,test_marker,test+test_marker,"calibration tests")
    f.write_text(s,encoding="utf-8")

    dpath=root/"apps/effectcraft-ios/src/diagnostics.rs"
    d=dpath.read_text(encoding="utf-8")
    d=once(d,
        '    pub renders: crate::render_files::RenderFiles,\n}',
        '''    pub renders: crate::render_files::RenderFiles,
    pub calibration_stage: u8,
    pub calibration_seen: u64,
    pub calibration_top: Option<(f32, f32)>,
}''',
        "diagnostics state")

    d=once(d,
        '                ui.label("A green crosshair marks the last UIKit left-click for 10 seconds. Compare it with the visible cursor/layer row.");',
        '''                ui.label(format!("2-point mapping: scale {:.5}, offset {:+.1} pt",
                    self.keyboard.primary_y_scale, self.keyboard.primary_y_origin));
                ui.label("One-point Y correction is fine-tuning only: it cannot fix top-to-bottom drift.");
                ui.horizontal(|ui| {
                    if ui.button("Calibrate TOP + BOTTOM").clicked() {
                        self.calibration_stage=1;
                        self.calibration_seen=self.keyboard.calibration_tap_count;
                        self.calibration_top=None;
                        self.keyboard.calibration_active=true;
                    }
                    if self.calibration_stage!=0 && ui.button("Cancel calibration").clicked() {
                        self.calibration_stage=0;
                        self.keyboard.calibration_active=false;
                    }
                });
                if self.calibration_stage!=0 {
                    ui.label(if self.calibration_stage==1 {
                        "Step 1/2: click the upper orange target on the RIGHT."
                    } else {
                        "Step 2/2: click the lower orange target on the RIGHT."
                    });
                }
                ui.label("The next two trackpad taps compute a height-dependent correction automatically. Repeat if screen zoom or orientation changes.");
                ui.label("A green crosshair marks the last UIKit left-click for 10 seconds.");''',
        "2 point calibration controls")

    anchor='        self.renders.show(&mut self.app, ctx);'
    code='''        // Draw two reference markers in the same coordinate system used by
        // egui's hit testing. UIKit captures uncorrected physical tap positions.
        if self.calibration_stage != 0 {
            ctx.request_repaint_after(std::time::Duration::from_millis(40));
            let screen = ctx.content_rect();
            let target_x = (screen.max.x - 90.0).max(screen.min.x + 90.0);
            let upper_y = screen.min.y + 110.0;
            let lower_y = screen.max.y - 110.0;
            let expected_y = if self.calibration_stage == 1 { upper_y } else { lower_y };
            if self.keyboard.calibration_tap_count > self.calibration_seen {
                self.calibration_seen = self.keyboard.calibration_tap_count;
                if let Some(raw) = self.keyboard.calibration_last_raw {
                    if self.calibration_stage == 1 {
                        self.calibration_top = Some((raw.y, upper_y));
                        self.calibration_stage = 2;
                    } else if let Some((raw_top, target_top)) = self.calibration_top {
                        let span = raw.y - raw_top;
                        if span.abs() < 150.0 {
                            self.app.ui.status = "Targets too close: click upper then lower target again.".into();
                            self.calibration_stage = 1;
                            self.calibration_top = None;
                        } else {
                            let scale = (lower_y - target_top) / span;
                            let origin = target_top - scale * raw_top;
                            match self.keyboard.save_primary_affine(scale, origin) {
                                Ok(()) => {
                                    self.app.ui.status = format!(
                                        "Pointer calibrated: Y = {:.5} × raw Y {:+.1} pt", scale, origin);
                                    self.calibration_stage = 0;
                                    self.keyboard.calibration_active = false;
                                }
                                Err(e) => {
                                    self.app.ui.status = e;
                                    self.calibration_stage = 1;
                                    self.calibration_top = None;
                                }
                            }
                        }
                    }
                }
            }
            if self.calibration_stage != 0 {
                let active_y = if self.calibration_stage == 1 { upper_y } else { lower_y };
                let at = egui::pos2(target_x, active_y);
                let paint = ctx.debug_painter();
                let color = egui::Color32::from_rgb(255, 170, 35);
                paint.circle_filled(at, 18.0, egui::Color32::from_black_alpha(220));
                paint.circle_stroke(at, 18.0, egui::Stroke::new(3.0, color));
                paint.line_segment([at+egui::vec2(-14.0,0.0),at+egui::vec2(14.0,0.0)],
                    egui::Stroke::new(2.0,color));
                paint.line_segment([at+egui::vec2(0.0,-14.0),at+egui::vec2(0.0,14.0)],
                    egui::Stroke::new(2.0,color));
                paint.text(at+egui::vec2(0.0,-33.0),egui::Align2::CENTER_BOTTOM,
                    if self.calibration_stage == 1 {"TOP · 1/2"} else {"BOTTOM · 2/2"},
                    egui::FontId::proportional(16.0),color);
            }
            // Keep compilation strict about the intended target.
            let _ = expected_y;
        }
'''
    d=once(d,anchor,code+anchor,"calibration painter and sampling")
    d=once(d,'"Diagnostics · build 27"','"Diagnostics · build 28"',"diagnostics build")
    dpath.write_text(d,encoding="utf-8")

    main=root/"apps/effectcraft-ios/src/main.rs"
    m=main.read_text(encoding="utf-8")
    m=once(m,'                renders,\n', '''                renders,
                calibration_stage: 0,
                calibration_seen: 0,
                calibration_top: None,
''',"initialize diag state")
    m=once(m,'"build=27 startup','"build=28 startup',"startup revision")
    m=once(m,'"EffectCraft · build 27. RAM:', '"EffectCraft · build 28. RAM:',"status revision")
    main.write_text(m,encoding="utf-8")
    print("Build 28: top/bottom two-point physical pointer affine calibration and persistence installed")

if __name__ == "__main__":
    patch(Path(sys.argv[1] if len(sys.argv)>1 else "."))
