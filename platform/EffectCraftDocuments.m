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
@property(nonatomic,strong) NSDictionary *request;
@property(nonatomic) BOOL handlingSelection;
@end

static ECDocuments *ECBridge;
static dispatch_source_t ECTimer;
static dispatch_queue_t ECQueue;

static NSURL *ECProjectCopies(void) {
    const char *home = getenv("HOME");
    NSString *path = home ? [NSString stringWithUTF8String:home] : nil;
    if (!path) return nil;
    NSRange guest = [path rangeOfString:@"/Documents/Data/Application/"];
    if (guest.location != NSNotFound) path = [[path substringToIndex:guest.location] stringByAppendingPathComponent:@"Documents/EffectCraft"];
    else path = [path stringByAppendingPathComponent:@"Documents"];
    return [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"Opened Projects"] isDirectory:YES];
}

static NSURL *ECRoot(void) {
    const char *home = getenv("HOME");
    if (!home) return nil;
    NSString *value = [NSString stringWithUTF8String:home];
    if (!value) return nil;
    return [NSURL fileURLWithPath:[value stringByAppendingPathComponent:@"Library/Caches/EffectCraft/DocumentBridge8"] isDirectory:YES];
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
            NSLog(@"EffectCraft Files: completed %@", self.request[@"action"]);
            ECReply(self.pendingRoot,self.pending,response);
            [[NSFileManager defaultManager] removeItemAtURL:ECFile(self.pendingRoot,[self.pending stringByAppendingString:@".cancel"]) error:nil];
        }
        self.pending = nil;
        self.pendingRoot = nil;
        self.picker = nil;
        self.request = nil;
        self.handlingSelection = NO;
    }
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    if (self.handlingSelection) return;
    [controller dismissViewControllerAnimated:YES completion:nil];
    [self complete:@{@"cancelled":@YES}];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self documentPicker:controller didPickDocumentsAtURLs:url ? @[url] : @[]];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!self.pending || self.handlingSelection) return;
    self.handlingSelection = YES;
    [controller dismissViewControllerAnimated:YES completion:nil];
    NSLog(@"EffectCraft Files: picker returned %lu URLs", (unsigned long)urls.count);
    if (!urls.count || urls.count > 64) { [self complete:@{@"error":@"Select between 1 and 64 files"}]; return; }
    NSDictionary *request = self.request;
    // Provider coordination and resource registration must never stall UIKit's delegate.
    dispatch_async(ECQueue, ^{
        NSMutableArray *paths = [NSMutableArray new];
        NSString *importTo = [request[@"import_to"] isKindOfClass:NSString.class] ? request[@"import_to"] : nil;
        if (!importTo && [request[@"action"] isEqual:@"open"]) importTo = ECProjectCopies().path;
        if ([request[@"action"] isEqual:@"open"] && !importTo) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self complete:@{@"error":@"The app's project folder is unavailable"}]; }); return;
        }
        NSURL *importFolder = importTo ? [[NSURL fileURLWithPath:importTo isDirectory:YES] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES] : nil;
        NSError *error = nil;
        if (importFolder && ![NSFileManager.defaultManager createDirectoryAtURL:importFolder withIntermediateDirectories:YES attributes:nil error:&error]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self complete:@{@"error":error.localizedDescription ?: @"Cannot create import folder"}]; }); return;
        }
        // Rust retains individual project paths. Register their persistent local parent,
        // rather than handing the editor the document picker's temporary import URL.
        if (importFolder && ![request[@"import_to"] isKindOfClass:NSString.class]) {
            @synchronized(self) {
                if (self.grants.count >= 256) {
                    [NSFileManager.defaultManager removeItemAtURL:importFolder error:nil];
                    dispatch_async(dispatch_get_main_queue(), ^{ [self complete:@{@"error":@"Save your work and relaunch before opening more projects"}]; }); return;
                }
                ECFolderPresenter *presenter = [ECFolderPresenter new];
                presenter.presentedItemURL = importFolder;
                presenter.presentedItemOperationQueue = [NSOperationQueue new];
                presenter.presentedItemOperationQueue.maxConcurrentOperationCount = 1;
                [NSFileCoordinator addFilePresenter:presenter];
                [self.grants addObject:@{@"url":importFolder,@"scoped":@NO,@"presenter":presenter}];
            }
        }
        for (NSURL *url in urls) {
            if (!url.isFileURL) { error = [NSError errorWithDomain:@"EffectCraft" code:1 userInfo:@{NSLocalizedDescriptionKey:@"The provider returned an invalid file"}]; break; }
            BOOL scoped = [url startAccessingSecurityScopedResource];
            NSNumber *directory = nil;
            [url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:&error];
            BOOL folderRequest = [request[@"action"] isEqual:@"folder"];
            if (error || !directory || directory.boolValue != folderRequest) {
                if (scoped) [url stopAccessingSecurityScopedResource];
                error = error ?: [NSError errorWithDomain:@"EffectCraft" code:5 userInfo:@{NSLocalizedDescriptionKey:folderRequest ? @"Select a folder" : @"Select a file, not a folder"}]; break;
            }
            if (importFolder) {
                NSURL *destination = [importFolder URLByAppendingPathComponent:url.lastPathComponent];
                NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
                __block NSError *copyError = nil;
                __block BOOL copied = NO;
                [coordinator coordinateReadingItemAtURL:url options:0 error:&error byAccessor:^(NSURL *source) {
                    NSNumber *size = nil; [source getResourceValue:&size forKey:NSURLFileSizeKey error:&copyError];
                    if (!size || size.unsignedLongLongValue > (1ULL << 30)) { copyError = [NSError errorWithDomain:@"EffectCraft" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Imported files must be smaller than 1 GiB"}]; return; }
                    copied = [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:&copyError];
                }];
                if (scoped) [url stopAccessingSecurityScopedResource];
                if (!copied) { error = copyError ?: error ?: [NSError errorWithDomain:@"EffectCraft" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Cannot copy the selected file"}]; break; }
                [paths addObject:destination.path];
            } else {
                @synchronized(self) {
                    if (!ECPresenter(url.path)) {
                        if (self.grants.count >= 256) {
                            if (scoped) [url stopAccessingSecurityScopedResource];
                            error = [NSError errorWithDomain:@"EffectCraft" code:4 userInfo:@{NSLocalizedDescriptionKey:@"Save your work and relaunch before selecting more files"}]; break;
                        }
                        ECFolderPresenter *presenter = [ECFolderPresenter new];
                        presenter.presentedItemURL = url;
                        presenter.presentedItemOperationQueue = [NSOperationQueue new];
                        presenter.presentedItemOperationQueue.maxConcurrentOperationCount = 1;
                        [NSFileCoordinator addFilePresenter:presenter];
                        [self.grants addObject:@{@"url":url,@"scoped":@(scoped),@"presenter":presenter}];
                    } else if (scoped) { [url stopAccessingSecurityScopedResource]; }
                }
                [paths addObject:url.path];
            }
        }
        if (error && importFolder) [NSFileManager.defaultManager removeItemAtURL:importFolder error:nil];
        NSDictionary *response = error ? @{@"error":error.localizedDescription} : @{@"paths":paths};
        dispatch_async(dispatch_get_main_queue(), ^{ [self complete:response]; });
    });
}
- (void)choose:(NSString *)name root:(NSURL *)root request:(NSDictionary *)request {
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
    @synchronized(self) { self.pending = name; self.pendingRoot = root; self.request = request; self.handlingSelection = NO; }
    NSString *action = request[@"action"];
    if ([action isEqual:@"export"]) {
        NSString *path = request[@"path"];
        if (![path isKindOfClass:NSString.class] || ![NSFileManager.defaultManager fileExistsAtPath:path]) { [self complete:@{@"error":@"The file is not ready to save"}]; return; }
        self.picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[[NSURL fileURLWithPath:path]] asCopy:NO];
    } else {
        if ([action isEqual:@"folder"]) {
            self.picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder] asCopy:NO];
        } else {
            NSMutableArray<UTType *> *types = [NSMutableArray arrayWithArray:@[UTTypeData, UTTypeContent]];
            for (NSString *extension in @[@"ecproj", @"ecprojx"]) {
                UTType *type = [UTType typeWithFilenameExtension:extension conformingToType:UTTypeData];
                if (type) [types addObject:type];
            }
            // Import mode asks Files for a local copy, avoiding open-in-place handoff
            // of an unregistered document through LiveContainer's host identity.
            self.picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
        }
    }
    self.picker.delegate = self;
    self.picker.allowsMultipleSelection = [action isEqual:@"open"] && [request[@"many"] boolValue];
    self.picker.modalPresentationStyle = UIModalPresentationFormSheet;
    NSLog(@"EffectCraft Files: presenting %@", action);
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
            if (![name hasPrefix:[NSString stringWithFormat:@"%d-",getpid()]]) { [fm removeItemAtURL:file error:nil]; continue; }
            NSNumber *size = nil; [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
            if (size.unsignedLongLongValue > 16384) { [fm removeItemAtURL:file error:nil]; continue; }
            NSData *bytes = [NSData dataWithContentsOfURL:file];
            NSDictionary *request = bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil] : nil;
            [fm removeItemAtURL:file error:nil];
            if (![request isKindOfClass:NSDictionary.class]) { ECReply(root,name,@{@"error":@"Invalid document request"}); continue; }
            if ([@[@"folder",@"open",@"export"] containsObject:request[@"action"]]) { dispatch_async(dispatch_get_main_queue(), ^{ [ECBridge choose:name root:root request:request]; }); }
            else { ECIO(root,name,request); }
        }
    }
}

__attribute__((constructor,used)) static void ECInstallDocuments(void) {
    @autoreleasepool {
        ECBridge = [ECDocuments new]; ECBridge.grants = [NSMutableArray new];
        ECQueue = dispatch_queue_create("effectcraft.document-access", DISPATCH_QUEUE_SERIAL);
        ECTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,ECQueue);
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
