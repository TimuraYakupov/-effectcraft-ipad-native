// MIT OR Apache-2.0. UIKit audio session and suspension protection.
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#include <unistd.h>
#include <stdlib.h>

static UIBackgroundTaskIdentifier ECTask;
static void ECEndTask(void) {
    if (ECTask != UIBackgroundTaskInvalid) {
        UIBackgroundTaskIdentifier task = ECTask;
        ECTask = UIBackgroundTaskInvalid;
        [UIApplication.sharedApplication endBackgroundTask:task];
    }
}
static void ECState(BOOL active) {
    const char *value = getenv("HOME");
    NSString *home = value ? [NSString stringWithUTF8String:value] : nil;
    if (!home) return;
    NSString *folder = [home stringByAppendingPathComponent:@"Library/Caches/EffectCraft/DocumentBridge8"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *state = [NSString stringWithFormat:@"%d:%@", getpid(), active ? @"active" : @"inactive"];
    [state writeToFile:[folder stringByAppendingPathComponent:@"lifecycle.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
static void ECActivate(void) {
    NSError *error = nil;
    AVAudioSession *audio = AVAudioSession.sharedInstance;
    BOOL ok = [audio setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    if (ok) ok = [audio setActive:YES error:&error];
    if (!ok) NSLog(@"EffectCraft audio session: %@", error.localizedDescription);
    ECState(YES);
    ECEndTask();
}
__attribute__((constructor,used)) static void ECInstallAudio(void) {
    @autoreleasepool {
        ECTask = UIBackgroundTaskInvalid;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { ECActivate(); }];
        [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            ECState(NO);
            if (ECTask == UIBackgroundTaskInvalid) {
                ECTask = [UIApplication.sharedApplication beginBackgroundTaskWithName:@"EffectCraft recovery" expirationHandler:^{ ECEndTask(); }];
                UIBackgroundTaskIdentifier task = ECTask;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ if (ECTask == task) ECEndTask(); });
            }
        }];
        [center addObserverForName:AVAudioSessionInterruptionNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSNumber *type = note.userInfo[AVAudioSessionInterruptionTypeKey];
            if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) ECState(NO);
            else if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) ECActivate();
        }];
        [center addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { ECActivate(); }];
    }
}
