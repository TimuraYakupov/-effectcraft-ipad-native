// MIT OR Apache-2.0. Hardware keyboard bridge for the native iPad wrapper.
// Intercepts only WinitUIWindow; UIKit document pickers keep their normal input.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <unistd.h>

static dispatch_queue_t ECKQueue;
static dispatch_source_t ECKTimer;
static void (*ECKOriginal)(id, SEL, UIEvent *);
static NSString *ECKSession;
static NSURL *ECKRoot;
static BOOL ECKText;
static BOOL ECKBlocked;
static unsigned long long ECKSequence;
static NSMutableSet<NSNumber *> *ECKDown;
static BOOL ECKInstalled;

static NSURL *ECKDirectory(void) {
    const char *home = getenv("HOME");
    NSString *path = home ? [NSString stringWithUTF8String:home] : nil;
    return path ? [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"Library/Caches/EffectCraft/Keyboard9"] isDirectory:YES] : nil;
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
static void ECKSend(id window, SEL selector, UIEvent *event) {
    if (!ECKOriginal) return;
    UIWindow *view = window;
    // A presented UIKit controller (Files, share sheets) owns its keyboard.
    if (!ECKSession || ECKBlocked || !view.isKeyWindow ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        view.rootViewController.presentedViewController || event.type != UIEventTypePresses ||
        ![event isKindOfClass:UIPressesEvent.class]) {
        ECKOriginal(window, selector, event); return;
    }
    NSSet<UIPress *> *presses = ((UIPressesEvent *)event).allPresses;
    if (!presses.count || presses.count > 32) { ECKOriginal(window, selector, event); return; }
    // Never forward a partially handled batch: that would duplicate key/text events.
    for (UIPress *press in presses) {
        UIKey *key = press.key;
        BOOL command = (key.modifierFlags & (UIKeyModifierCommand | UIKeyModifierControl)) != 0;
        if (!key || !ECKKnown(key.keyCode) ||
            (ECKText && ECKPrintable(key.keyCode) && !command && ![ECKDown containsObject:@(key.keyCode)])) {
            ECKOriginal(window, selector, event); return;
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
            if (!ECKInstalled) {
                Class type = NSClassFromString(@"WinitUIWindow");
                SEL selector = @selector(sendEvent:);
                Method original = type ? class_getInstanceMethod(type, selector) : NULL;
                if (original) {
                    ECKOriginal = (void (*)(id, SEL, UIEvent *))method_getImplementation(original);
                    ECKInstalled = class_addMethod(type, selector, (IMP)ECKSend, method_getTypeEncoding(original));
                    if (!ECKInstalled) ECKOriginal = NULL;
                    NSLog(@"EffectCraft keyboard bridge installed=%d", ECKInstalled);
                }
            }
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
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { ECKReset(); }];
    }
}
