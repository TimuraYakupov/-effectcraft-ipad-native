"""Build 30: give UIKit hover and mouse clicks one coordinate system.

Device video: primary click selects exactly after Build28 affine calibration, but
hover and draggable property hit regions miss the visible cursor. The Build28
transform was only applied to origin=uikit-primary-tap, while UIKit
UIHoverGestureRecognizer and secondary button records used uncorrected
coordinates. That is the regression. Use the same existing persisted affine map
for ALL UIKit indirect-pointer events in the keyboard bridge (they already pass
through the same zoom normalization). Winit touch/Pencil/native events are NOT
processed through this bridge and remain unchanged. No new calibration required.
"""
from pathlib import Path
import sys


def once(s: str, old: str, new: str, label: str) -> str:
    count = s.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: need 1 anchor, got {count}")
    return s.replace(old, new, 1)


def patch(root: Path) -> None:
    keyboard = root / "apps/effectcraft-ios/src/keyboard.rs"
    s = keyboard.read_text(encoding="utf-8")
    old = '''            let pos = egui::pos2(raw.x,
                if is_uikit_primary {
                    raw.y * self.primary_y_scale + self.primary_y_origin + self.primary_y_adjust
                } else { raw.y });'''
    new = '''            // Every event recorded here comes from UIKit's indirect-pointer
            // recognizers: hover, left click or right click. Apply the SAME
            // validated map to all of them, otherwise hover hit-testing is
            // offset from the separately corrected left-click target.
            // Direct touch/Pencil and winit-native drags never use this path.
            let pos = egui::pos2(raw.x,
                raw.y * self.primary_y_scale + self.primary_y_origin + self.primary_y_adjust);'''
    s = once(s, old, new, "normalize all UIKit mouse events")

    s = once(s,
        "fn only_real_uikit_primary_taps_receive_persistent_vertical_calibration()",
        "fn uikit_hover_and_taps_share_persisted_vertical_calibration()",
        "rename Build 27 regression")
    s = once(s,
        'assert!(events.contains(&Event::PointerMoved(egui::pos2(120.0,400.0))));',
        'assert!(events.contains(&Event::PointerMoved(egui::pos2(120.0,387.0))));',
        "Build 27 hover assertion")
    s = once(s,
        '        } if pos.y==400.0)));',
        '        } if pos.y==387.0)));',
        "Build 27 secondary assertion")

    s = once(s,
        "fn two_point_transform_aligns_top_mid_and_bottom_but_not_secondary_or_hover()",
        "fn two_point_transform_aligns_primary_hover_and_secondary_at_every_height()",
        "rename Build 28 regression")
    s = once(s,
        'assert_eq!(events.last(),Some(&Event::PointerMoved(egui::pos2(250.0,500.0))));',
        'assert_eq!(events.last(),Some(&Event::PointerMoved(egui::pos2(250.0,485.0))));',
        "Build 28 hover assertion")
    s = once(s,
        'button:egui::PointerButton::Secondary,pos,..} if pos.y==500.0)));',
        'button:egui::PointerButton::Secondary,pos,..} if pos.y==485.0)));',
        "Build 28 secondary assertion")

    # A dedicated integration regression: UIKit hover and the primary/secondary
    # hit positions agree at several heights when the mapping is non-identity.
    test_marker = "    #[test]\n    fn idle_input_wakes_the_actual_egui_repaint_callback() {"
    test = '''    #[test]
    fn corrected_hover_and_buttons_are_pixel_consistent_in_top_middle_bottom() {
        let mut bridge = Keyboard::new();
        bridge.primary_y_scale = 0.93;
        bridge.primary_y_origin = 24.0;
        bridge.primary_y_adjust = 0.0;
        for raw_y in [100.0_f32, 420.0, 900.0] {
            let expected = raw_y * 0.93 + 24.0;
            let mut events = vec![];
            bridge.record(&json!({"kind":"pointer", "x":210.0, "y":raw_y}),
                false, false, &mut events).unwrap();
            assert!(events.iter().any(|e| matches!(e, Event::PointerMoved(p)
                if (p.y-expected).abs() < 0.01)));
            assert!(bridge.last_hover.is_some_and(|(p,_)| (p.y-expected).abs()<0.01));
            events.clear();
            bridge.record(&json!({"kind":"pointer","origin":"uikit-primary-tap",
                "button":"primary","x":210.0,"y":raw_y,"down":true}),
                false,false,&mut events).unwrap();
            assert!(events.iter().any(|e| matches!(e, Event::PointerButton {
                pos, button:egui::PointerButton::Primary, pressed:true,..
            } if (pos.y-expected).abs()<0.01)));
            events.clear();
            bridge.record(&json!({"kind":"pointer","button":"secondary",
                "x":210.0,"y":raw_y,"down":true}),
                false,false,&mut events).unwrap();
            assert!(events.iter().any(|e| matches!(e, Event::PointerButton {
                pos, button:egui::PointerButton::Secondary, pressed:true,..
            } if (pos.y-expected).abs()<0.01)));
        }
    }

'''
    s = once(s, test_marker, test + test_marker, "unified pointer regression")
    keyboard.write_text(s, encoding="utf-8")

    diagnostics=root/"apps/effectcraft-ios/src/diagnostics.rs"
    d=diagnostics.read_text(encoding="utf-8")
    d=once(d, "This changes ONLY UIKit primary taps, not touch or right click.",
        "This adjusts UIKit trackpad hover and mouse buttons together, not direct touch or Pencil.",
        "correct diagnostics copy")
    d=once(d,'"Diagnostics · build 29"','"Diagnostics · build 30"',
        "diagnostics build")
    diagnostics.write_text(d,encoding="utf-8")

    main=root/"apps/effectcraft-ios/src/main.rs"
    m=main.read_text(encoding="utf-8")
    m=once(m,'"build=29 startup','"build=30 startup',"startup")
    m=once(m,'"EffectCraft · build 29. RAM:','"EffectCraft · build 30. RAM:',"startup UI label")
    main.write_text(m,encoding="utf-8")
    print("Build 30: UIKit hover/right-click/primary use same saved affine mapping; native touch & Pencil untouched.",flush=True)


if __name__=="__main__":
    patch(Path(sys.argv[1] if len(sys.argv)>1 else "."))
