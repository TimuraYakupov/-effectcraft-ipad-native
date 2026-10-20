// MIT OR Apache-2.0. Tests the production UIKit bridge inside an iPad simulator.
#import "../../platform/EffectCraftKeyboard.m"

static UIWindow *TestWindow;
static NSURL *TestRoot;
static NSString *TestSession;
static NSMutableArray<NSString *> *Checks;
static NSUInteger NativeTouches[4];
static IMP NativeTouchMethods[4];
static NSSet *LastNativeTouches;
static UIEvent *LastNativeEvent;

@interface WinitUIView : UIView <UIKeyInput>
@end
@implementation WinitUIView
- (BOOL)canBecomeFirstResponder { return YES; }
- (BOOL)hasText { return YES; }
- (void)insertText:(NSString *)text { (void)text; }
- (void)deleteBackward {}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { NativeTouches[0]++; LastNativeTouches=touches; LastNativeEvent=event; }
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { NativeTouches[1]++; LastNativeTouches=touches; LastNativeEvent=event; }
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { NativeTouches[2]++; LastNativeTouches=touches; LastNativeEvent=event; }
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { NativeTouches[3]++; LastNativeTouches=touches; LastNativeEvent=event; }
@end
@interface WinitUIViewController : UIViewController
@end
@implementation WinitUIViewController
- (void)loadView { self.view = [WinitUIView new]; }
@end

// Deliberately public-API test doubles; no private event injection APIs.
@interface TestKey : NSObject
@property(nonatomic) NSInteger keyCode;
@property(nonatomic) UIKeyModifierFlags modifierFlags;
@property(nonatomic,copy) NSString *characters;
@property(nonatomic,copy) NSString *charactersIgnoringModifiers;
@end
@implementation TestKey
@end
@interface TestPress : NSObject
@property(nonatomic,strong) TestKey *key;
@property(nonatomic) UIPressPhase phase;
@end
@implementation TestPress
@end
@interface TestPointer : NSObject
@property(nonatomic) UIGestureRecognizerState state;
@property(nonatomic) CGPoint point;
- (CGPoint)locationInView:(UIView *)view;
@end
@implementation TestPointer
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
@end

static void Finish(NSString *error) {
    NSDictionary *result = @{@"ok":@(!error), @"error":error ?: @"", @"checks":Checks};
    NSURL *file = [[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"result.json"];
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:NULL];
    [data writeToURL:file options:NSDataWritingAtomic error:NULL];
    exit(error ? 1 : 0);
}
static BOOL Check(BOOL value, NSString *name) {
    if (!value) { Finish(name); return NO; }
    [Checks addObject:name]; return YES;
}
static void State(BOOL text, BOOL blocked) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"pid":@(getpid()), @"session":TestSession, @"text":@(text), @"blocked":@(blocked)} options:0 error:NULL];
    [data writeToURL:[TestRoot URLByAppendingPathComponent:@"state.json"] options:NSDataWritingAtomic error:NULL];
}
static NSSet<UIPress *> *Press(NSInteger code, BOOL down, UIKeyModifierFlags flags) {
    TestKey *key = [TestKey new]; key.keyCode=code; key.modifierFlags=flags;
    key.characters = code == 44 ? @" " : @"s"; key.charactersIgnoringModifiers=key.characters;
    TestPress *press = [TestPress new]; press.key=key; press.phase=down ? UIPressPhaseBegan : UIPressPhaseEnded;
    return (NSSet<UIPress *> *)[NSSet setWithObject:press];
}
static NSArray<NSDictionary *> *Records(void) {
    NSMutableArray *out = [NSMutableArray new];
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:TestRoot includingPropertiesForKeys:nil options:0 error:NULL];
    files = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [a.lastPathComponent compare:b.lastPathComponent]; }];
    for (NSURL *file in files) if ([file.pathExtension isEqual:@"key"]) {
        NSData *data = [NSData dataWithContentsOfURL:file];
        NSDictionary *value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (value) [out addObject:value];
    }
    return out;
}
static void After(double seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds*NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}
// Assert that keyboard installation cannot replace the native touch delivery path.
// These responder doubles test routing, not physical pointer behavior.
@interface TestTouch : NSObject
@property(nonatomic) UITouchType type;
@end
@implementation TestTouch
@end
@interface TestMouseEvent : NSObject
@property(nonatomic) UIEventButtonMask buttonMask;
@end
@implementation TestMouseEvent
@end
static SEL NativeTouchSelector(NSUInteger phase) {
    switch (phase) {
        case 0: return @selector(touchesBegan:withEvent:);
        case 1: return @selector(touchesMoved:withEvent:);
        case 2: return @selector(touchesEnded:withEvent:);
        default: return @selector(touchesCancelled:withEvent:);
    }
}
static void TestNativeTouchDelivery(UIView *view) {
    ECKInstall(); ECKInstall();
    for (NSUInteger phase=0; phase<4; phase++) {
        Check(class_getMethodImplementation(WinitUIView.class, NativeTouchSelector(phase)) == NativeTouchMethods[phase],
            @"repeated keyboard installation preserves original native touch implementations");
        NativeTouches[phase]=0;
    }
    TestTouch *touch=[TestTouch new]; TestMouseEvent *event=[TestMouseEvent new];
    for (NSNumber *type in @[@(UITouchTypeIndirectPointer), @(UITouchTypeDirect), @(UITouchTypeStylus)]) {
        touch.type=type.integerValue;
        for (NSNumber *button in @[@(UIEventButtonMaskPrimary), @(UIEventButtonMaskSecondary)]) {
            event.buttonMask=button.unsignedIntegerValue;
            NSSet *touches=[NSSet setWithObject:touch];
            for (NSUInteger phase=0; phase<4; phase++) {
                switch (phase) {
                    case 0: [view touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)(id)event]; break;
                    case 1: [view touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)(id)event]; break;
                    case 2: [view touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)(id)event]; break;
                    default: [view touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)(id)event]; break;
                }
                Check(LastNativeTouches==touches && LastNativeEvent==(UIEvent *)(id)event,
                    @"native responder receives unchanged touch set and event");
            }
        }
    }
    for (NSUInteger phase=0; phase<4; phase++) Check(NativeTouches[phase]==6,
        @"mouse finger and Pencil retain begin move end and cancellation");
}

// No delegate.window property and no scene manifest, matching winit's legacy lifecycle.
@interface TestDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation TestDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)app; (void)options;
    Checks=[NSMutableArray new]; TestRoot=ECKDirectory(); TestSession=[NSString stringWithFormat:@"%d-11",getpid()];
    [NSFileManager.defaultManager createDirectoryAtURL:TestRoot withIntermediateDirectories:YES attributes:nil error:NULL];
    TestWindow=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    TestWindow.rootViewController=[WinitUIViewController new];
    [TestWindow makeKeyAndVisible];
    Check(!TestWindow.rootViewController.canBecomeFirstResponder, @"controller cannot receive hardware keys before bridge installation");
    for (NSUInteger phase=0; phase<4; phase++) NativeTouchMethods[phase]=class_getMethodImplementation(WinitUIView.class,NativeTouchSelector(phase));
    State(NO, NO);
    After(2.0, ^{
        Check(ECKInstalled[0] && ECKInstalled[1], @"both UIResponder hooks installed");
        TestNativeTouchDelivery(TestWindow.rootViewController.view);
        Check(TestWindow.rootViewController.isFirstResponder, @"hardware controller owns keyboard focus without UIKeyInput");
        Check(![TestWindow.rootViewController conformsToProtocol:@protocol(UIKeyInput)], @"hardware focus does not request software keyboard");
        [TestWindow.rootViewController pressesBegan:Press(44,YES,0) withEvent:nil];
        [TestWindow.rootViewController pressesBegan:Press(44,YES,0) withEvent:nil];
        [TestWindow.rootViewController pressesEnded:Press(44,NO,0) withEvent:nil];
        [TestWindow.rootViewController pressesBegan:Press(22,YES,UIKeyModifierCommand) withEvent:nil];
        [TestWindow.rootViewController pressesEnded:Press(22,NO,UIKeyModifierCommand) withEvent:nil];
        After(0.3, ^{
            NSArray *records=Records();
            Check(records.count==5, @"UIKit responder methods write exactly five key records");
            Check([records[0][@"down"] boolValue] && ![records[0][@"repeat"] boolValue] && [records[1][@"repeat"] boolValue] && ![records[2][@"down"] boolValue], @"Space down repeat up preserved");
            Check([records[3][@"code"] integerValue]==22 && ([records[3][@"flags"] unsignedLongLongValue]&UIKeyModifierCommand), @"Cmd S modifiers delivered");
            State(YES,NO);
            After(0.3, ^{
                Check(TestWindow.rootViewController.view.isFirstResponder, @"IME state automatically restores text focus");
                After(0.3, ^{
                    Check(TestWindow.rootViewController.view.isFirstResponder, @"hardware controller does not steal text focus");
                    Check(!ECKHandle(TestWindow.rootViewController.view,Press(44,YES,0)), @"ordinary text is left to UIKit UIKeyInput");
                    State(NO,YES);
                    After(0.3, ^{
                        Check(!ECKHandle(TestWindow.rootViewController,Press(44,YES,0)), @"file dialog blocks editor key capture");
                        State(NO,NO);
                        [TestWindow.rootViewController.view resignFirstResponder];
                        After(0.3, ^{
                            Check(TestWindow.rootViewController.isFirstResponder, @"hardware focus recovers after text and file dialogs");
                            NSData *data=[NSData dataWithContentsOfURL:[TestRoot URLByAppendingPathComponent:@"native.status"]];
                            NSDictionary *status=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
                            Check([status[@"native_presses"] unsignedLongLongValue]>=5 && [status[@"state"] isEqual:@"Ready"], @"live native diagnostics reports focus and key delivery");
                            UIViewController *guest=TestWindow.rootViewController;
                            UIViewController *host=[UIViewController new];
                            TestWindow.rootViewController=host;
                            [host presentViewController:guest animated:NO completion:^{
                                After(0.5, ^{
                                    Check(guest.isFirstResponder && ECKGuest==guest, @"guest presented inside a host retains hardware focus");
                                    TestNativeTouchDelivery(guest.view);
                                    Check(ECKHandle(guest,Press(44,YES,0)), @"host presentation does not block guest key capture");
                                    Check(ECKMouse.view==guest.view && ECKMouse.secondary.buttonMaskRequired==UIEventButtonMaskSecondary, @"hover and secondary click are installed on the guest view");
                                    TestPointer *pointer=[TestPointer new];pointer.point=CGPointMake(120,200);pointer.state=UIGestureRecognizerStateChanged;
                                    [ECKMouse hovering:(UIHoverGestureRecognizer *)(id)pointer];
                                    pointer.state=UIGestureRecognizerStateRecognized;[ECKMouse rightClick:(UITapGestureRecognizer *)(id)pointer];
                                    After(0.3, ^{
                                        NSMutableArray *pointerRecords=[NSMutableArray new];
                                        for (NSDictionary *record in Records()) if ([record[@"kind"] isEqual:@"pointer"]) [pointerRecords addObject:record];
                                        Check(pointerRecords.count==3, @"hover and right click produce three ordered pointer records");
                                        Check([pointerRecords[0][@"x"] doubleValue]==120 && [pointerRecords[1][@"down"] boolValue] && ![pointerRecords[2][@"down"] boolValue], @"secondary down/up preserve hover coordinates");
                                        [guest presentViewController:[UIViewController new] animated:NO completion:^{
                                            After(0.5, ^{
                                                Check(!ECKHandle(guest,Press(44,YES,0)), @"guest system modal still blocks editor keys");
                                                Finish(nil);
                                            });
                                        }];
                                    });
                                });
                            }];
                        });
                    });
                });
            });
        });
    });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TestDelegate.class)); }
}
