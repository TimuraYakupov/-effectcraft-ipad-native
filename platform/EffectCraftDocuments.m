// MIT OR Apache-2.0. iPadOS document access for the native preview wrapper.
// The Rust editor communicates through bounded local requests, with no Rust FFI.
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <unistd.h>

@interface ECFolderPresenter : NSObject <NSFilePresenter>
@property(nonatomic,strong) NSURL *presentedItemURL;
@property(nonatomic,strong) NSOperationQueue *presentedItemOperationQueue;
@end
@implementation ECFolderPresenter
@end

@interface ECDocuments : NSObject <UIDocumentPickerDelegate>
@property(nonatomic,strong) NSMutableArray<NSDictionary *> *grants;
@property(nonatomic,strong) UIDocumentPickerViewController *picker;
@property(nonatomic,copy) NSString *pending;
@property(nonatomic,strong) NSURL *pendingRoot;
@end

static ECDocuments *ECBridge;
static dispatch_source_t ECTimer;

static NSURL *ECRoot(void) {
    const char *home = getenv("HOME");
    if (!home) return nil;
    NSString *value = [NSString stringWithUTF8String:home];
    if (!value) return nil;
    return [NSURL fileURLWithPath:[value stringByAppendingPathComponent:@"Library/Caches/EffectCraft/DocumentBridge6"] isDirectory:YES];
}
static NSURL *ECFile(NSURL *root, NSString *name) { return [root URLByAppendingPathComponent:name]; }
static void ECReply(NSURL *root, NSString *name, NSDictionary *value) {
    NSData *bytes = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (bytes) [bytes writeToURL:ECFile(root,[name stringByAppendingString:@".response"]) options:NSDataWritingAtomic error:nil];
}
static BOOL ECValidName(NSString *name) {
    return name.length > 0 && name.length < 100 && [name rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789-"] invertedSet]].location == NSNotFound;
}
static ECFolderPresenter *ECPresenter(NSString *path) {
    NSString *candidate = [[NSURL fileURLWithPath:path] URLByResolvingSymlinksInPath].path;
    @synchronized (ECBridge) {
        for (NSDictionary *grant in ECBridge.grants) {
            NSURL *url = grant[@"url"];
            NSString *base = url.URLByResolvingSymlinksInPath.path;
            if ([candidate isEqualToString:base] || [candidate hasPrefix:[base stringByAppendingString:@"/"]]) return grant[@"presenter"];
        }
    }
    return nil;
}

@implementation ECDocuments
- (void)complete:(NSDictionary *)response {
    @synchronized(self) {
        if (self.pending) {
            ECReply(self.pendingRoot,self.pending,response);
            [[NSFileManager defaultManager] removeItemAtURL:ECFile(self.pendingRoot,[self.pending stringByAppendingString:@".cancel"]) error:nil];
        }
        self.pending = nil;
        self.pendingRoot = nil;
        self.picker = nil;
    }
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { [self complete:@{@"cancelled":@YES}]; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url.isFileURL) { [self complete:@{@"error":@"The provider did not return a folder"}]; return; }
    BOOL scoped = [url startAccessingSecurityScopedResource];
    ECFolderPresenter *existing = ECPresenter(url.path);
    if (!existing) {
        @synchronized(self) {
            if (self.grants.count >= 32) {
                if (scoped) [url stopAccessingSecurityScopedResource];
                [self complete:@{@"error":@"Too many folders selected. Save your work and relaunch the app."}]; return;
            }
            ECFolderPresenter *presenter = [ECFolderPresenter new];
            presenter.presentedItemURL = url;
            presenter.presentedItemOperationQueue = [NSOperationQueue new];
            presenter.presentedItemOperationQueue.maxConcurrentOperationCount = 1;
            [NSFileCoordinator addFilePresenter:presenter];
            [self.grants addObject:@{@"url":url,@"scoped":@(scoped),@"presenter":presenter}];
        }
    } else if (scoped) { [url stopAccessingSecurityScopedResource]; }
    [self complete:@{@"path":url.path}];
}
- (void)choose:(NSString *)name root:(NSURL *)root {
    if ([[NSFileManager defaultManager] fileExistsAtPath:ECFile(root,[name stringByAppendingString:@".cancel"]).path]) {
        ECReply(root,name,@{@"cancelled":@YES}); return;
    }
    if (self.picker) { ECReply(root,name,@{@"error":@"A folder picker is already open"}); return; }
    UIViewController *view = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) { view = window.rootViewController; break; }
        }
        if (view) break;
    }
    while (view.presentedViewController && !view.presentedViewController.isBeingDismissed) view = view.presentedViewController;
    if (!view || !view.view.window) { ECReply(root,name,@{@"error":@"No active iPad window. Close the menu and try again."}); return; }
    @synchronized(self) { self.pending = name; self.pendingRoot = root; }
    self.picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
    self.picker.delegate = self;
    self.picker.allowsMultipleSelection = NO;
    self.picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [view presentViewController:self.picker animated:YES completion:nil];
}
@end

static void ECIO(NSURL *root, NSString *name, NSDictionary *request) {
    NSString *path = request[@"path"];
    NSString *action = request[@"action"];
    if (![path isKindOfClass:NSString.class]) { ECReply(root,name,@{@"error":@"Missing path"}); return; }
    ECFolderPresenter *presenter = ECPresenter(path);
    if (!presenter) { ECReply(root,name,@{@"error":@"Select this folder again in Files to grant access"}); return; }
    NSURL *url = [NSURL fileURLWithPath:path];
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:presenter];
    NSError *coordinationError = nil;
    __block NSError *operationError = nil;
    __block BOOL success = NO;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *data = ECFile(root,[name stringByAppendingString:@".data"]);
    if ([action isEqualToString:@"read"]) {
        [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *coordinated) {
            NSNumber *size = nil;
            [coordinated getResourceValue:&size forKey:NSURLFileSizeKey error:&operationError];
            if (operationError || size.unsignedLongLongValue > (1ULL << 30)) return;
            success = [fm copyItemAtURL:coordinated toURL:data error:&operationError];
        }];
    } else if ([action isEqualToString:@"write"]) {
        [coordinator coordinateWritingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *coordinated) {
            NSURL *temporary = [[coordinated URLByDeletingLastPathComponent] URLByAppendingPathComponent:[NSString stringWithFormat:@".effectcraft-%@.tmp",name]];
            if ([fm copyItemAtURL:data toURL:temporary error:&operationError]) {
                if ([fm fileExistsAtPath:coordinated.path]) {
                    success = [fm replaceItemAtURL:coordinated withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:&operationError];
                } else { success = [fm moveItemAtURL:temporary toURL:coordinated error:&operationError]; }
            }
            if (!success) [fm removeItemAtURL:temporary error:nil];
        }];
    }
    NSError *error = operationError ?: coordinationError;
    ECReply(root,name,success ? @{@"ok":@YES} : @{@"error":error.localizedDescription ?: @"The file provider could not complete this operation"});
}

static void ECTick(void) {
    @autoreleasepool {
        NSURL *root = ECRoot(); if (!root) return;
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]) return;
        NSData *ready = [NSJSONSerialization dataWithJSONObject:@{@"pid":@(getpid()),@"version":@1} options:0 error:nil];
        [ready writeToURL:ECFile(root,@"ready.json") options:NSDataWritingAtomic error:nil];
        @synchronized(ECBridge) {
            if (ECBridge.pending && [fm fileExistsAtPath:ECFile(root,[ECBridge.pending stringByAppendingString:@".cancel"]).path]) {
                dispatch_async(dispatch_get_main_queue(), ^{ [ECBridge.picker dismissViewControllerAnimated:YES completion:nil]; [ECBridge complete:@{@"cancelled":@YES}]; });
            }
        }
        NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:root includingPropertiesForKeys:@[NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        NSUInteger count = 0;
        for (NSURL *file in files) {
            if (![file.pathExtension isEqualToString:@"request"] || count++ >= 32) continue;
            NSString *name = file.lastPathComponent.stringByDeletingPathExtension;
            if (!ECValidName(name)) continue;
            NSNumber *size = nil; [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            if (size.unsignedLongLongValue > 16384) { [fm removeItemAtURL:file error:nil]; continue; }
            NSData *bytes = [NSData dataWithContentsOfURL:file];
            NSDictionary *request = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
            [fm removeItemAtURL:file error:nil];
            if (![request isKindOfClass:NSDictionary.class]) { ECReply(root,name,@{@"error":@"Invalid document request"}); continue; }
            if ([request[@"action"] isEqual:@"folder"]) { dispatch_async(dispatch_get_main_queue(), ^{ [ECBridge choose:name root:root]; }); }
            else { ECIO(root,name,request); }
        }
    }
}

__attribute__((constructor,used)) static void ECInstallDocuments(void) {
    @autoreleasepool {
        ECBridge = [ECDocuments new]; ECBridge.grants = [NSMutableArray new];
        dispatch_queue_t queue = dispatch_queue_create("effectcraft.document-access", DISPATCH_QUEUE_SERIAL);
        ECTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
        dispatch_source_set_timer(ECTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),NSEC_PER_SEC/5,NSEC_PER_SEC/20);
        dispatch_source_set_event_handler(ECTimer, ^{ ECTick(); });
        dispatch_resume(ECTimer);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_source_cancel(ECTimer);
            @synchronized(ECBridge) { for (NSDictionary *grant in ECBridge.grants) {
                [NSFileCoordinator removeFilePresenter:grant[@"presenter"]];
                if ([grant[@"scoped"] boolValue]) [grant[@"url"] stopAccessingSecurityScopedResource];
            } [ECBridge.grants removeAllObjects]; }
        }];
    }
}
