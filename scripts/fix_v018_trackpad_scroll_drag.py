"""Restore indirect pointer drag hit-testing and iPadOS two-finger scrolling.

The previously fixed tap and hover coordinates are UIKit-based, while an
actual drag was still handled by winit touch events in a separate coordinate
system. A non-cancelling UIKit indirect-pointer pan reports primary dragging
through the *same* calibrated positions as hover/tap. UIKit's supported
UIPanGestureRecognizer.allowedScrollTypesMask handles two-finger scrolls and
mouse wheels without stealing direct finger/Pencil touches.
"""
from pathlib import Path
import sys


def once(s, old, new, label):
    n=s.count(old)
    if n!=1:
        raise RuntimeError(f"{label}: expected one anchor, found {n}")
    return s.replace(old,new,1)


def patch(root):
    objpath=Path("platform/EffectCraftKeyboard.m")
    obj=objpath.read_text(encoding="utf-8")
    obj=once(obj,
        '@property(nonatomic,strong) UITapGestureRecognizer *secondary;\n',
        '@property(nonatomic,strong) UITapGestureRecognizer *secondary;\n'
        '@property(nonatomic,strong) UIPanGestureRecognizer *scroll;\n'
        '@property(nonatomic,strong) UIPanGestureRecognizer *drag;\n'
        '@property(nonatomic,assign) BOOL indirectDragging;\n',
        "gesture properties")

    marker='- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {'
    methods='''// Native scrolling doesn't enter winit as a trackpad wheel in the iPad host.
// A continuous UIKit scroll gesture supports two-finger trackpads / Magic Mouse;
// discrete supports scroll wheel mice. No direct touch events are intercepted.
- (void)scrolling:(UIPanGestureRecognizer *)gesture {
    if (![self active]) return;
    UIGestureRecognizerState state = gesture.state;
    if (state != UIGestureRecognizerStateBegan && state != UIGestureRecognizerStateChanged &&
        state != UIGestureRecognizerStateEnded && state != UIGestureRecognizerStateCancelled) return;
    CGPoint offset = [gesture translationInView:self.view];
    [gesture setTranslation:CGPointZero inView:self.view];
    NSString *phase = state == UIGestureRecognizerStateBegan ? @"start" :
        state == UIGestureRecognizerStateChanged ? @"move" : @"end";
    ECKWrite(@{@"kind":@"scroll", @"phase":phase,
        @"dx":@(offset.x), @"dy":@(offset.y)});
}
// A pressed indirect-pointer drag must use the same coordinates as UIKit taps
// and hover. This recognizer observes without cancelling native touch delivery.
// The Rust input adapter suppresses *duplicate native pointer* events while
// the recognizer is active, not ordinary direct-touch/Pencil interactions.
- (void)dragging:(UIPanGestureRecognizer *)gesture {
    if (![self active]) return;
    UIGestureRecognizerState state = gesture.state;
    if (state == UIGestureRecognizerStateBegan) {
        // This pan listens only to indirect pointer touches. Ignore right drag.
        if (!(gesture.buttonMask & UIEventButtonMaskPrimary)) return;
        self.indirectDragging = YES;
        CGPoint point = [gesture locationInView:self.view];
        CGPoint travel = [gesture translationInView:self.view];
        CGPoint down = CGPointMake(point.x - travel.x, point.y - travel.y);
        ECKWrite(@{@"kind":@"pointer", @"origin":@"uikit-primary-drag",
            @"phase":@"start", @"x":@(down.x), @"y":@(down.y)});
        ECKWrite(@{@"kind":@"pointer", @"origin":@"uikit-primary-drag",
            @"phase":@"move", @"x":@(point.x), @"y":@(point.y)});
    } else if (self.indirectDragging &&
               (state == UIGestureRecognizerStateChanged || state == UIGestureRecognizerStateEnded ||
                state == UIGestureRecognizerStateCancelled || state == UIGestureRecognizerStateFailed)) {
        CGPoint point = [gesture locationInView:self.view];
        NSString *phase = state == UIGestureRecognizerStateChanged ? @"move" :
            state == UIGestureRecognizerStateCancelled ? @"cancel" : @"end";
        ECKWrite(@{@"kind":@"pointer", @"origin":@"uikit-primary-drag",
            @"phase":phase, @"x":@(point.x), @"y":@(point.y)});
        if (state != UIGestureRecognizerStateChanged) self.indirectDragging = NO;
    }
}
'''
    obj=once(obj,marker,methods+marker,"pointer handlers")
    obj=once(obj,
        '    return [a isKindOfClass:UIHoverGestureRecognizer.class] || [b isKindOfClass:UIHoverGestureRecognizer.class];',
        '    return [a isKindOfClass:UIHoverGestureRecognizer.class] || [b isKindOfClass:UIHoverGestureRecognizer.class] ||\n'
        '        a == self.scroll || b == self.scroll || a == self.drag || b == self.drag;',
        "recognize simultaneous input")
    obj=once(obj,
        '    if (ECKMouse.secondary) [ECKMouse.view removeGestureRecognizer:ECKMouse.secondary];',
        '    if (ECKMouse.secondary) [ECKMouse.view removeGestureRecognizer:ECKMouse.secondary];\n'
        '    if (ECKMouse.scroll) [ECKMouse.view removeGestureRecognizer:ECKMouse.scroll];\n'
        '    if (ECKMouse.drag) [ECKMouse.view removeGestureRecognizer:ECKMouse.drag];\n'
        '    ECKMouse.indirectDragging = NO;',
        "cleanup gesture lifecycle")
    obj=once(obj,
        '    [view addGestureRecognizer:secondary]; ECKMouse.secondary = secondary;',
        '''    [view addGestureRecognizer:secondary]; ECKMouse.secondary = secondary;
    UIPanGestureRecognizer *scroll = [[UIPanGestureRecognizer alloc] initWithTarget:ECKMouse action:@selector(scrolling:)];
    // UIKit scroll events are not UITouch events. Do not swallow finger touches.
    scroll.allowedTouchTypes = @[];
    scroll.allowedScrollTypesMask = UIScrollTypeMaskContinuous | UIScrollTypeMaskDiscrete;
    scroll.cancelsTouchesInView = NO;
    scroll.delegate = ECKMouse;
    [view addGestureRecognizer:scroll]; ECKMouse.scroll = scroll;
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:ECKMouse action:@selector(dragging:)];
    drag.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
    drag.allowedScrollTypesMask = 0;
    drag.cancelsTouchesInView = NO;
    drag.delaysTouchesBegan = NO;
    drag.delaysTouchesEnded = NO;
    drag.delegate = ECKMouse;
    [view addGestureRecognizer:drag]; ECKMouse.drag = drag;''',
        "attach UIKit scroll and drag")
    objpath.write_text(obj,encoding="utf-8")

    keyboard=root/"apps/effectcraft-ios/src/keyboard.rs"
    s=keyboard.read_text(encoding="utf-8")
    s=once(s,
        '    pub calibration_last_raw: Option<egui::Pos2>,\n}',
        '    pub calibration_last_raw: Option<egui::Pos2>,\n'
        '    pub indirect_drag_active: bool,\n'
        '    pub scroll_events_received: u64,\n}',
        "keyboard drag state")
    s=once(s,
        '            calibration_last_raw: None,\n',
        '            calibration_last_raw: None,\n'
        '            indirect_drag_active: false,\n'
        '            scroll_events_received: 0,\n',
        "init drag state")
    s=once(s,
        '        self.primary_down = false;\n        self.last_hover = None;',
        '        self.primary_down = false;\n        self.indirect_drag_active = false;\n        self.last_hover = None;',
        "reset drag state")

    marker='        if value["kind"].as_str() == Some("pointer") {'
    scroll_code='''        if value["kind"].as_str() == Some("scroll") {
            let dx = value["dx"].as_f64()
                .filter(|v| v.is_finite() && v.abs() < 10_000.0)
                .ok_or("Invalid scroll X")? as f32;
            let dy = value["dy"].as_f64()
                .filter(|v| v.is_finite() && v.abs() < 10_000.0)
                .ok_or("Invalid scroll Y")? as f32;
            let phase = match value["phase"].as_str() {
                Some("start") => egui::TouchPhase::Start,
                Some("end") => egui::TouchPhase::End,
                Some("cancel") => egui::TouchPhase::Cancel,
                _ => egui::TouchPhase::Move,
            };
            self.scroll_events_received = self.scroll_events_received.saturating_add(1);
            events.push(Event::MouseWheel {
                unit: egui::MouseWheelUnit::Point,
                delta: egui::vec2(dx, dy),
                phase,
                modifiers: self.modifiers,
            });
            return Ok(());
        }
'''
    # The pointer branch also appears inside input() with deeper indentation.
    # Only insert the wheel handler into record(), before the first branch.
    if s.count(marker) != 2:
        raise RuntimeError(f"Expected record() and input() pointer branches, got {s.count(marker)}")
    s=s.replace(marker,scroll_code+marker,1)
    marker='            if let Some(down) = value["down"].as_bool() {'
    drag_code='''            if value["origin"].as_str() == Some("uikit-primary-drag") {
                let phase = value["phase"].as_str().unwrap_or("move");
                match phase {
                    "start" => {
                        self.indirect_drag_active = true;
                        self.primary_down = true;
                        events.push(Event::PointerButton {
                            pos, button: egui::PointerButton::Primary,
                            pressed: true, modifiers: self.modifiers,
                        });
                    }
                    "end" | "cancel" => {
                        self.indirect_drag_active = false;
                        self.primary_down = false;
                        events.push(Event::PointerButton {
                            pos, button: egui::PointerButton::Primary,
                            pressed: false, modifiers: self.modifiers,
                        });
                    }
                    "move" => {}
                    _ => return Err("Invalid UIKit drag phase".into()),
                }
                return Ok(());
            }
'''
    s=once(s,marker,drag_code+marker,"unified calibrated drag")
    s=once(s,
        '        let native_event_count = input.events.len();',
        '        let native_event_count = input.events.len();\n'
        '        let mut indirect_drag_in_frame = self.indirect_drag_active;\n'
        '        let mut uikit_scroll_in_frame = false;',
        "native events boundary")
    s=once(s,
        '                    if value["kind"].as_str() == Some("pointer") {',
        '''                    if value["origin"].as_str() == Some("uikit-primary-drag") {
                        indirect_drag_in_frame = true;
                    }
                    if value["kind"].as_str() == Some("scroll") {
                        uikit_scroll_in_frame = true;
                    }
                    if value["kind"].as_str() == Some("scroll") {
                        let zoom = f64::from(ctx.zoom_factor()).max(0.1);
                        for axis in ["dx", "dy"] {
                            if let Some(v) = value[axis].as_f64() { value[axis] = json!(v / zoom); }
                        }
                    }
                    if value["kind"].as_str() == Some("pointer") {''',
        "capture and normalize UIKit drag/scroll")

    marker='        if had_records && input.focused && input.events.iter().any(|e| matches!(e, Event::WindowFocused(false))) {'
    filter_code='''        if (indirect_drag_in_frame || self.indirect_drag_active || uikit_scroll_in_frame)
            && native_event_count > 0
        {
            // Native winit touch-backed mouse drag is displaced relative to the
            // calibrated UIKit pan. Only remove *native* duplicate mouse/touch
            // events during a confirmed indirect-pointer pan. UIKit events were
            // appended after the first native_event_count records.
            let native = input.events.drain(..native_event_count);
            let clean = native.filter(|e| {
                if indirect_drag_in_frame || self.indirect_drag_active {
                    !matches!(e, Event::PointerMoved(_) | Event::PointerButton { .. } |
                        Event::PointerGone | Event::Touch { .. })
                } else if uikit_scroll_in_frame {
                    !matches!(e, Event::MouseWheel { .. })
                } else { true }
            }).collect::<Vec<_>>();
            input.events.splice(0..0, clean);
        }
'''
    s=once(s,marker,filter_code+marker,"prevent duplicate native drag/scroll delivery")

    # Extra unit checks enforce calibrated panning, wheel axis/phases and correct
    # relative direction without touching the native iPad UIKit implementation.
    test_marker='    #[test]\n    fn idle_input_wakes_the_actual_egui_repaint_callback() {'
    tests='''    #[test]
    fn synthetic_uikit_indirect_drag_uses_same_calibrated_hit_position() {
        let mut bridge=Keyboard::new();
        bridge.primary_y_scale=0.9;
        bridge.primary_y_origin=24.0;
        bridge.primary_y_adjust=0.0;
        let mut events=vec![];
        bridge.record(&json!({"kind":"pointer","origin":"uikit-primary-drag",
            "phase":"start","x":100.0,"y":100.0}),false,false,&mut events).unwrap();
        assert!(bridge.indirect_drag_active);
        assert!(events.iter().any(|e| matches!(e,Event::PointerButton{
            button:egui::PointerButton::Primary,pressed:true,pos,..}
            if (pos.y-114.0).abs()<0.001)));
        events.clear();
        bridge.record(&json!({"kind":"pointer","origin":"uikit-primary-drag",
            "phase":"move","x":100.0,"y":300.0}),false,false,&mut events).unwrap();
        assert!(events.iter().any(|e| matches!(e,Event::PointerMoved(p)
            if (p.y-294.0).abs()<0.001)));
        events.clear();
        bridge.record(&json!({"kind":"pointer","origin":"uikit-primary-drag",
            "phase":"end","x":100.0,"y":300.0}),false,false,&mut events).unwrap();
        assert!(!bridge.indirect_drag_active);
        assert!(events.iter().any(|e| matches!(e,Event::PointerButton{
            button:egui::PointerButton::Primary,pressed:false,pos,..}
            if (pos.y-294.0).abs()<0.001)));
    }

    #[test]
    fn two_finger_scroll_emits_point_wheel_with_phases() {
        let mut bridge=Keyboard::new();
        let mut events=vec![];
        for (phase, expected) in [("start",egui::TouchPhase::Start),
            ("move",egui::TouchPhase::Move),("end",egui::TouchPhase::End)] {
            bridge.record(&json!({"kind":"scroll","phase":phase,
                "dx":-8.0,"dy":24.0}),false,false,&mut events).unwrap();
            assert!(matches!(events.last(),Some(Event::MouseWheel{unit:egui::MouseWheelUnit::Point,
                delta,phase, ..}) if delta.x == -8.0 && delta.y == 24.0 && *phase == expected));
        }
        assert_eq!(bridge.scroll_events_received,3);
    }

'''
    s=once(s,test_marker,tests+test_marker,"drag and scroll regression tests")
    keyboard.write_text(s,encoding="utf-8")
    diagnostics=root/"apps/effectcraft-ios/src/diagnostics.rs"
    d=diagnostics.read_text(encoding="utf-8")
    d=once(d, '                ui.label(format!("Pointer events received: {}", self.keyboard.pointer_received));',
        '                ui.label(format!("Pointer events received: {} · trackpad scroll events: {}", self.keyboard.pointer_received, self.keyboard.scroll_events_received));',
        "pointer scroll diagnostics")
    d=once(d,'"Diagnostics · build 30"','"Diagnostics · build 31"',"diag label")
    diagnostics.write_text(d,encoding="utf-8")
    main=root/"apps/effectcraft-ios/src/main.rs"
    m=main.read_text(encoding="utf-8")
    m=once(m,'"build=30 startup','"build=31 startup',"startup")
    m=once(m,'"EffectCraft · build 30. RAM:','"EffectCraft · build 31. RAM:',"startup status")
    main.write_text(m,encoding="utf-8")
    print("Build 31 UIKit scrolling, indirect-pan pointer path, duplicate native input guard, regression tests",flush=True)

if __name__=="__main__":
    patch(Path(sys.argv[1] if len(sys.argv)>1 else "."))
