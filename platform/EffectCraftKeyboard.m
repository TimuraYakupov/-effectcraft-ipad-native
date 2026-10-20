// MIT OR Apache-2.0. Hardware keyboard bridge for the native iPad wrapper.
// Extends only the Winit view/controller's UIResponder methods.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <unistd.h>

static dispatch_queue_t ECKQueue;
static dispatch_source_t ECKTimer;
typedef void (*ECKPressIMP)(id, SEL, NSSet<UIPress *> *, UIPressesEvent *);
static ECKPressIMP ECKOriginal[2][4];
static BOOL ECKInstalled[2];
static unsigned long long ECKSeen;
static NSInteger ECKLastCode;
static NSTimeInterval ECKLastStatus;
static __weak UIViewController *ECKGuest;
static NSString *ECKSession;
static NSURL *ECKRoot;
static BOOL ECKText;
static BOOL ECKBlocked;
static unsigned long long ECKSequence;
static NSMutableSet<NSNumber *> *ECKDown;

static NSURL *ECKDirectory(void) {
    const char *home = getenv("HOME");
    NSString *path = home ? [NSString stringWithUTF8String:home] : nil;
    return path ? [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"Library/Caches/EffectCraft/Keyboard11"] isDirectory:YES] : nil;
}
static BOOL ECKKnown(NSInteger code) {
    return (code >= 4 && code <= 56) || (code >= 58 && code <= 69) || (code >= 73 && code <= 82) ||
           (code >= 84 && code <= 99) || (code >= 224 && code <= 231);
}
static BOOL ECKPrintable(NSInteger code) { return (code >= 4 && code <= 39) || (code >= 44 && code <= 56) || (code >= 84 && code <= 99); }
static void ECKWrite(NSDictionary *record) {
    if (!ECKRoot || !ECKSession) return;
    NSString *name = [NSString stringWithFormat:@"%@-%020llu.key", ECKSession, ++ECKSequence];
    NSURL *file = [ECKRoot URLByAppendingPathComponent:name];
    dispatch_async(ECKQueue, ^{
        @autoreleasepool {
            NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:file.URLByDeletingLastPathComponent includingPropertiesForKeys:nil options:0 error:NULL];
            NSMutableArray<NSURL *> *pending = [NSMutableArray new];
            for (NSURL *item in files) if ([item.pathExtension isEqual:@"key"]) [pending addObject:item];
            NSDictionary *bounded = record;
            if (pending.count >= 256) {
                for (NSURL *item in pending) [NSFileManager.defaultManager removeItemAtURL:item error:NULL];
                bounded = @{@"kind":@"reset"};
            }
            NSData *data = [NSJSONSerialization dataWithJSONObject:bounded options:0 error:NULL];
            if (data.length <= (1U << 20)) [data writeToURL:file options:NSDataWritingAtomic error:NULL];
        }
    });
}
static UIKeyModifierFlags ECKFlags(UIKey *key, BOOL down) {
    UIKeyModifierFlags flags = key.modifierFlags;
    UIKeyModifierFlags flag = 0;
    switch (key.keyCode) {
        case 224: case 228: flag = UIKeyModifierControl; break;
        case 225: case 229: flag = UIKeyModifierShift; break;
        case 226: case 230: flag = UIKeyModifierAlternate; break;
        case 227: case 231: flag = UIKeyModifierCommand; break;
        default: break;
    }
    return down ? flags | flag : flags & ~flag;
}
static void ECKReset(void) {
    if (ECKSession) ECKWrite(@{@"kind":@"reset"});
    [ECKDown removeAllObjects];
}
static BOOL ECKHandle(id responder, NSSet<UIPress *> *presses) {
    ECKSeen += presses.count;
    if (presses.anyObject.key) ECKLastCode = presses.anyObject.key.keyCode;
    UIWindow *view = [responder isKindOfClass:UIViewController.class] ? ((UIViewController *)responder).view.window : ((UIView *)responder).window;
    // A presented UIKit controller (Files, share sheets) owns its keyboard.
    if (!ECKSession || ECKBlocked || !view.isKeyWindow ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        ECKGuest.presentedViewController || !presses.count || presses.count > 32) return NO;
    // Never forward a partially handled batch: that would duplicate key/text events.
    for (UIPress *press in presses) {
        UIKey *key = press.key;
        BOOL command = (key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierControl)) != 0;
        if (!key || !ECKKnown(key.keyCode) ||
            (ECKText && ECKPrintable(key.keyCode) && !command && ![ECKDown containsObject:@(key.keyCode)])) {
            return NO;
        }
    }
    // Modifier transitions precede other keys in the same UIKit batch.
    NSArray<UIPress *> *ordered = [presses.allObjects sortedArrayUsingComparator:^NSComparisonResult(UIPress *a, UIPress *b) {
        BOOL am = a.key.keyCode >= 224, bm = b.key.keyCode >= 224;
        if (am != bm) return am ? NSOrderedAscending : NSOrderedDescending;
        return [@(a.key.keyCode) compare:@(b.key.keyCode)];
    }];
    for (UIPress *press in ordered) {
        if (press.phase == UIPressPhaseStationary) continue;
        if (press.phase == UIPressPhaseCancelled) { ECKReset(); continue; }
        BOOL down = press.phase == UIPressPhaseBegan || press.phase == UIPressPhaseChanged;
        UIKey *key = press.key;
        NSNumber *code = @(key.keyCode);
        BOOL repeat = down && [ECKDown containsObject:code];
        if (down) [ECKDown addObject:code]; else [ECKDown removeObject:code];
        UIKeyModifierFlags flags = ECKFlags(key, down);
        NSMutableDictionary *record = [@{@"kind":@"key", @"code":code, @"down":@(down), @"repeat":@(repeat), @"flags":@(flags)} mutableCopy];
        NSString *logical = key.charactersIgnoringModifiers ?: @"";
        NSString *text = key.characters ?: @"";
        if (logical.length <= 64) record[@"logical"] = logical;
        if (text.length <= 64) record[@"text"] = text;
        BOOL command = (flags & (UIKeyModifierCommand | UIKeyModifierControl)) != 0;
        if (down && !repeat && command && !(flags & (UIKeyModifierAlternate | UIKeyModifierShift))) {
            if (key.keyCode == 6) record[@"kind"] = @"copy";
            if (key.keyCode == 27) record[@"kind"] = @"cut";
            if (key.keyCode == 25) {
                record[@"kind"] = @"paste";
                NSString *paste = UIPasteboard.generalPasteboard.string ?: @"";
                if ([paste lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= (128U << 10)) record[@"text"] = paste;
                else { record[@"kind"] = @"error"; record[@"text"] = @"Clipboard text exceeds 128 KiB"; }
            }
        }
        ECKWrite(record);
    }
    return YES;
}
static SEL ECKSelector(NSUInteger phase) {
    switch (phase) {
        case 0: return @selector(pressesBegan:withEvent:);
        case 1: return @selector(pressesChanged:withEvent:);
        case 2: return @selector(pressesEnded:withEvent:);
        default: return @selector(pressesCancelled:withEvent:);
    }
}
static void ECKPress(id responder, SEL selector, NSSet<UIPress *> *presses, UIPressesEvent *event) {
    if (ECKHandle(responder, presses)) return;
    NSUInteger type = [responder isKindOfClass:UIViewController.class] ? 1 : 0;
    for (NSUInteger phase = 0; phase < 4; phase++) {
        if (selector == ECKSelector(phase) && ECKOriginal[type][phase]) {
            ECKOriginal[type][phase](responder, selector, presses, event); return;
        }
    }
}
static BOOL ECKCanFocus(id responder, SEL selector) { (void)responder; (void)selector; return YES; }
static void ECKInstall(void) {
    for (NSUInteger type = 0; type < 2; type++) {
        Class cls = NSClassFromString(type ? @"WinitUIViewController" : @"WinitUIView");
        if (!cls || ECKInstalled[type]) continue;
        BOOL installed = YES;
        for (NSUInteger phase = 0; phase < 4; phase++) {
            SEL selector = ECKSelector(phase);
            Method method = class_getInstanceMethod(cls, selector);
            if (!method) { installed = NO; continue; }
            if (method_getImplementation(method) == (IMP)ECKPress) continue;
            ECKPressIMP original = (ECKPressIMP)method_getImplementation(method);
            if (class_addMethod(cls, selector, (IMP)ECKPress, method_getTypeEncoding(method))) ECKOriginal[type][phase] = original;
            else installed = NO;
        }
        if (type) {
            Method focus = class_getInstanceMethod(cls, @selector(canBecomeFirstResponder));
            if (focus && method_getImplementation(focus) != (IMP)ECKCanFocus)
                installed = class_addMethod(cls, @selector(canBecomeFirstResponder), (IMP)ECKCanFocus, method_getTypeEncoding(focus)) && installed;
        }
        ECKInstalled[type] = installed;
    }
}
static UIViewController *ECKController(UIViewController *controller, NSUInteger *remaining) {
    if (!controller || !*remaining) return nil;
    --*remaining;
    if ([controller isKindOfClass:NSClassFromString(@"WinitUIViewController")]) return controller;
    for (UIViewController *child in controller.childViewControllers) {
        UIViewController *found = ECKController(child, remaining);
        if (found) return found;
    }
    return ECKController(controller.presentedViewController, remaining);
}
static UIViewController *ECKFind(void) {
    NSUInteger remaining = 64;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden) continue;
            UIViewController *found = ECKController(window.rootViewController, &remaining);
            if (found) return found;
        }
    }
    // winit 0.30 owns its windows directly, without a scene manifest or delegate.window.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.hidden) continue;
        UIViewController *found = ECKController(window.rootViewController, &remaining);
        if (found) return found;
    }
#pragma clang diagnostic pop
    return nil;
}
@interface ECPointer : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIView *view;
@property(nonatomic,strong) UIHoverGestureRecognizer *hover;
@property(nonatomic,strong) UITapGestureRecognizer *secondary;
@end
static ECPointer *ECKMouse;
@implementation ECPointer
- (BOOL)active {
    return ECKSession && self.view.window.isKeyWindow && !ECKGuest.presentedViewController &&
        UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
}
- (void)hovering:(UIHoverGestureRecognizer *)gesture {
    if (![self active]) return;
    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        ECKWrite(@{@"kind":@"pointer",@"phase":@"gone"}); return;
    }
    if (gesture.state != UIGestureRecognizerStateBegan && gesture.state != UIGestureRecognizerStateChanged) return;
    CGPoint point = [gesture locationInView:self.view];
    ECKWrite(@{@"kind":@"pointer",@"x":@(point.x),@"y":@(point.y)});
}
- (void)rightClick:(UITapGestureRecognizer *)gesture {
    if (![self active] || gesture.state != UIGestureRecognizerStateRecognized) return;
    CGPoint point = [gesture locationInView:self.view];
    ECKWrite(@{@"kind":@"pointer",@"x":@(point.x),@"y":@(point.y),@"down":@YES});
    ECKWrite(@{@"kind":@"pointer",@"x":@(point.x),@"y":@(point.y),@"down":@NO});
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    return [a isKindOfClass:UIHoverGestureRecognizer.class] || [b isKindOfClass:UIHoverGestureRecognizer.class];
}
@end
static void ECKInstallPointer(UIView *view) {
    if (!view || ECKMouse.view == view) return;
    if (!ECKMouse) ECKMouse = [ECPointer new];
    if (ECKMouse.hover) [ECKMouse.view removeGestureRecognizer:ECKMouse.hover];
    if (ECKMouse.secondary) [ECKMouse.view removeGestureRecognizer:ECKMouse.secondary];
    ECKMouse.view = view;
    UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc] initWithTarget:ECKMouse action:@selector(hovering:)];
    hover.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
    hover.cancelsTouchesInView = NO;
    hover.delegate = ECKMouse;
    [view addGestureRecognizer:hover]; ECKMouse.hover = hover;
    UITapGestureRecognizer *secondary = [[UITapGestureRecognizer alloc] initWithTarget:ECKMouse action:@selector(rightClick:)];
    secondary.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
    secondary.buttonMaskRequired = UIEventButtonMaskSecondary;
    secondary.delaysTouchesBegan = YES;
    secondary.cancelsTouchesInView = YES;
    secondary.delegate = ECKMouse;
    [view addGestureRecognizer:secondary]; ECKMouse.secondary = secondary;
}
static void ECKActivate(void) {
    ECKInstall();
    UIViewController *controller = ECKFind();
    ECKGuest = controller;
    ECKInstallPointer(controller.view);
    UIWindow *window = controller.view.window;
    BOOL active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
    BOOL modal = controller.presentedViewController != nil;
    if (ECKInstalled[1] && !ECKBlocked && window.isKeyWindow && active && !modal && (!ECKText || controller.isFirstResponder)) {
        // egui debounces set_ime_allowed. A queued old state must not steal its
        // one-time IME focus; reconcile both directions when fresh state arrives.
        UIResponder *target = ECKText ? controller.view : controller;
        if (!target.isFirstResponder) [target becomeFirstResponder];
    }
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - ECKLastStatus < 0.25) return;
    ECKLastStatus = now;
    NSString *state = !controller ? @"No Winit controller" : !window.isKeyWindow ? @"Window is not key" :
        !active ? @"App inactive" : modal ? @"System dialog" : ECKBlocked ? @"File dialog" :
        ECKText ? @"Text input" : controller.isFirstResponder ? @"Ready" : @"Keyboard focus unavailable";
    NSDictionary *status = @{@"session":ECKSession ?: @"", @"state":state, @"view_hook":@(ECKInstalled[0]),
        @"controller_hook":@(ECKInstalled[1]), @"focus":@(controller.isFirstResponder), @"native_presses":@(ECKSeen), @"last_code":@(ECKLastCode)};
    NSURL *root = ECKRoot;
    dispatch_async(ECKQueue, ^{
        NSData *data = [NSJSONSerialization dataWithJSONObject:status options:0 error:NULL];
        if (data && data.length <= 4096) [data writeToURL:[root URLByAppendingPathComponent:@"native.status"] options:NSDataWritingAtomic error:NULL];
    });
}
static void ECKTick(void) {
    @autoreleasepool {
        NSURL *root = ECKDirectory();
        if (!root || ![NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:NULL]) return;
        NSURL *stateFile = [root URLByAppendingPathComponent:@"state.json"];
        NSNumber *size = nil; [stateFile getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        if (!size || size.unsignedLongLongValue > 1024) return;
        NSData *bytes = [NSData dataWithContentsOfURL:stateFile];
        NSDictionary *state = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:NULL] : nil;
        if (![state isKindOfClass:NSDictionary.class] || [state[@"pid"] intValue] != getpid()) return;
        NSString *session = state[@"session"];
        if (![session isKindOfClass:NSString.class] || !session.length || session.length > 96 ||
            [session rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789-"] invertedSet]].location != NSNotFound) return;
        BOOL text = [state[@"text"] boolValue], blocked = [state[@"blocked"] boolValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![ECKSession isEqual:session]) { ECKReset(); ECKSession = session; ECKSequence = 0; }
            if (blocked && !ECKBlocked) ECKReset();
            ECKRoot = root; ECKText = text; ECKBlocked = blocked;
            ECKActivate();
        });
        NSURL *clipboard = [root URLByAppendingPathComponent:@"clipboard.request"];
        size = nil; [clipboard getResourceValue:&size forKey:NSURLFileSizeKey error:NULL];
        if (size && size.unsignedLongLongValue <= (1U << 20)) {
            bytes = [NSData dataWithContentsOfURL:clipboard];
            [NSFileManager.defaultManager removeItemAtURL:clipboard error:NULL];
            NSDictionary *copy = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:NULL] : nil;
            if ([copy isKindOfClass:NSDictionary.class] && [copy[@"session"] isEqual:session] && [copy[@"text"] isKindOfClass:NSString.class]) {
                NSString *value = copy[@"text"];
                if ([value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= (128U << 10))
                    dispatch_async(dispatch_get_main_queue(), ^{ UIPasteboard.generalPasteboard.string = value; });
            }
        }
    }
}
__attribute__((constructor,used)) static void ECInstallKeyboard(void) {
    @autoreleasepool {
        ECKDown = [NSMutableSet new];
        ECKQueue = dispatch_queue_create("effectcraft.hardware-keyboard", DISPATCH_QUEUE_SERIAL);
        ECKTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, ECKQueue);
        dispatch_source_set_timer(ECKTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC/30, NSEC_PER_SEC/300);
        dispatch_source_set_event_handler(ECKTimer, ^{ ECKTick(); });
        dispatch_resume(ECKTimer);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; ECKReset(); }];
    }
}
