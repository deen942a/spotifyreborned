// The store and the page. A cover is a JPEG in Application Support/spotifyglass/covers named by a hash
// of the URI; covers.json beside them says which URI each belongs to, for the page's list.
#import <CommonCrypto/CommonDigest.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/PlayerState.h"
#import "LocalCovers.h"

NSNotificationName const SGLocalCoverDidChangeNotification = @"spotifyglass.localCoverDidChange";
static const CGFloat kLongestSide = 1024;

BOOL SGIsLocalURI(NSString *uri) {
    return [uri hasPrefix:@"spotify:local:"];
}

static NSObject *lock(void) {
    static NSObject *object;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ object = [NSObject new]; });
    return object;
}

// Covers asked for on every layout and every now playing update, so what was read, or found missing
// (NSNull), is kept.
static NSCache *cache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; });
    return cache;
}

static NSURL *folder(void) {
    NSURL *base = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask
                                              appropriateForURL:nil create:YES error:nil];
    NSURL *dir = [[base URLByAppendingPathComponent:@"spotifyglass" isDirectory:YES] URLByAppendingPathComponent:@"covers" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSString *nameFor(NSString *uri) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    NSData *data = [uri dataUsingEncoding:NSUTF8StringEncoding];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < 16; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSURL *fileFor(NSString *uri) {
    return [folder() URLByAppendingPathComponent:[nameFor(uri) stringByAppendingString:@".jpg"]];
}

static NSURL *indexURL(void) {
    return [folder() URLByAppendingPathComponent:@"covers.json"];
}

static NSMutableDictionary<NSString *, NSString *> *readIndex(void) {
    NSData *data = [NSData dataWithContentsOfURL:indexURL()];
    id stored = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    return [stored isKindOfClass:NSMutableDictionary.class] ? stored : [NSMutableDictionary dictionary];
}

static void writeIndex(NSDictionary *index) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:index options:0 error:nil];
    if (data) [data writeToURL:indexURL() options:NSDataWritingAtomic error:nil];
}

UIImage *SGLocalCoverFor(NSString *uri) {
    if (!SGIsLocalURI(uri)) return nil;
    id hit = [cache() objectForKey:uri];
    if (hit) return hit == NSNull.null ? nil : hit;
    UIImage *image = [UIImage imageWithContentsOfFile:fileFor(uri).path];
    [cache() setObject:image ?: NSNull.null forKey:uri];
    return image;
}

static UIImage *scaled(UIImage *image) {
    CGFloat longest = MAX(image.size.width, image.size.height);
    if (longest <= kLongestSide) return image;
    CGFloat factor = kLongestSide / longest;
    CGSize size = CGSizeMake(round(image.size.width * factor), round(image.size.height * factor));
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:(CGRect){CGPointZero, size}];
    }];
}

static void changed(NSString *uri) {
    [cache() removeObjectForKey:uri];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGLocalCoverDidChangeNotification object:nil];
    });
}

void SGLocalCoverSet(NSString *uri, UIImage *image) {
    if (!SGIsLocalURI(uri) || !image) return;
    NSData *data = UIImageJPEGRepresentation(scaled(image), 0.9);
    if (!data) return;
    @synchronized (lock()) {
        [data writeToURL:fileFor(uri) options:NSDataWritingAtomic error:nil];
        NSMutableDictionary *index = readIndex();
        index[nameFor(uri)] = uri;
        writeIndex(index);
    }
    changed(uri);
}

void SGLocalCoverRemove(NSString *uri) {
    if (!SGIsLocalURI(uri)) return;
    @synchronized (lock()) {
        [NSFileManager.defaultManager removeItemAtURL:fileFor(uri) error:nil];
        NSMutableDictionary *index = readIndex();
        [index removeObjectForKey:nameFor(uri)];
        writeIndex(index);
    }
    changed(uri);
}

#pragma mark - the page

// "spotify:local:artist:album:title:seconds", '+' for a space and percent-encoding for the rest.
static NSString *field(NSString *raw) {
    NSString *spaced = [raw stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    return [spaced stringByRemovingPercentEncoding] ?: spaced;
}

static NSString *titleOf(NSString *uri) {
    NSArray<NSString *> *parts = [uri componentsSeparatedByString:@":"];
    if (parts.count < 6) return uri;
    NSString *title = field(parts[4]), *artist = field(parts[2]);
    if (!title.length) return artist.length ? artist : @"Untitled file";
    return artist.length ? [NSString stringWithFormat:@"%@ - %@", title, artist] : title;
}

static UIViewController *topController(void) {
    UIViewController *top = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) top = window.rootViewController;
    }
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

static void say(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [topController() presentViewController:alert animated:YES completion:nil];
}

@interface SGCoverPicker : NSObject <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, copy) NSString *uri;
@end

static SGCoverPicker *sg_picker;   // the picker holds its delegate weakly

@implementation SGCoverPicker
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    UIImage *image = info[UIImagePickerControllerEditedImage] ?: info[UIImagePickerControllerOriginalImage];
    SGLocalCoverSet(self.uri, image);
    [picker dismissViewControllerAnimated:YES completion:nil];
    sg_picker = nil;
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
    sg_picker = nil;
}
@end

// The square crop the picker offers is the shape of a cover.
static void chooseCover(NSString *uri) {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        say(@"No photo library", @"This phone has no library to pick a picture from.");
        return;
    }
    sg_picker = [SGCoverPicker new];
    sg_picker.uri = uri;
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.allowsEditing = YES;
    picker.delegate = sg_picker;
    [topController() presentViewController:picker animated:YES completion:nil];
}

static void confirmRemove(NSString *uri) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Remove this cover?" message:titleOf(uri) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { SGLocalCoverRemove(uri); }]];
    [topController() presentViewController:alert animated:YES completion:nil];
}

NSString *SGLocalCoversSummary(void) {
    NSUInteger count;
    @synchronized (lock()) { count = readIndex().count; }
    return count ? @(count).stringValue : @"None";
}

UIViewController *SGLocalCoversPage(void) {
    NSString *playing = SGURIString(SGPlayerState().track.URI);
    SGModRow *change = SGActionRow(@"Change the cover of the playing file",
                                   SGIsLocalURI(playing) ? titleOf(playing) : @"Play a local file first", ^{
        NSString *now = SGURIString(SGPlayerState().track.URI);
        if (SGIsLocalURI(now)) chooseCover(now);
        else say(@"No local file playing", @"Start a file from the Files app, then open this page again.");
    });
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[change])];

    NSArray<NSString *> *uris;
    @synchronized (lock()) { uris = readIndex().allValues; }
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    for (NSString *uri in [uris sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        [rows addObject:SGActionRow(titleOf(uri), @"Tap to remove the custom cover", ^{ confirmRemove(uri); })];
    }
    if (rows.count) [sections addObject:SGNotedSection(@"Custom covers", rows, @"Open this page again after removing one.")];
    return [[SGModPage alloc] initWithTitle:@"Local file covers" intro:nil sections:sections
                                     footer:@"The cover shows in the redesigned player and on the lock screen, and stays on this phone."];
}
