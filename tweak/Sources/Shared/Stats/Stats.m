// Counts the time a track is actually playing, between one state change and the next, and adds it to
// that track's entry: URI -> {title, artist, album, seconds, plays}. Artists and albums are summed
// from the tracks when a page asks, so there is one thing to store. A play is counted once a track
// has run 30 seconds in one go. Saved a few seconds after a change, every 30 s while playing, and on
// leaving the front.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/PlayerState.h"
#import "Stats.h"

static NSString *const kSeconds = @"s", *kPlays = @"p", *kTitle = @"t", *kArtist = @"a", *kAlbum = @"b";
static const double kPlayAfter = 30;

typedef NS_ENUM(NSInteger, SGStatsKind) { SGStatsSongs, SGStatsArtists, SGStatsAlbums };

@interface SGStatsStore : NSObject <SGPlayerStateObserver>
+ (instancetype)shared;
@property (nonatomic, readonly) NSDictionary<NSString *, NSDictionary *> *tracks;
- (double)totalSeconds;
- (NSArray<NSDictionary *> *)top:(SGStatsKind)kind limit:(NSUInteger)limit;
- (void)reset;
@end

@implementation SGStatsStore {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_tracks;
    NSString *_uri;          // the track being counted
    CFTimeInterval _since;   // when the open stretch began, 0 when nothing is playing
    double _session;         // seconds of this track in one go
    BOOL _counted;           // its play is already added
    BOOL _savePending;
    dispatch_source_t _tick;
}

+ (instancetype)shared {
    static SGStatsStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ store = [SGStatsStore new]; });
    return store;
}

static NSURL *fileURL(void) {
    NSURL *base = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask
                                              appropriateForURL:nil create:YES error:nil];
    NSURL *dir = [base URLByAppendingPathComponent:@"spotifyglass" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir URLByAppendingPathComponent:@"stats.json"];
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _tracks = [NSMutableDictionary dictionary];
    NSData *data = [NSData dataWithContentsOfURL:fileURL()];
    id stored = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    if ([stored isKindOfClass:NSDictionary.class]) [_tracks addEntriesFromDictionary:stored];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(leavingFront) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(leavingFront) name:UIApplicationWillTerminateNotification object:nil];
    return self;
}

- (NSDictionary<NSString *, NSDictionary *> *)tracks { return _tracks; }

// Adds the open stretch to the track and opens the next one from now.
- (void)commit {
    if (_since <= 0 || !_uri) return;
    CFTimeInterval now = CACurrentMediaTime();
    double elapsed = MAX(0, now - _since);
    _since = now;
    if (elapsed <= 0) return;
    NSMutableDictionary *entry = _tracks[_uri];
    if (!entry) entry = _tracks[_uri] = [NSMutableDictionary dictionary];
    entry[kSeconds] = @([entry[kSeconds] doubleValue] + elapsed);
    _session += elapsed;
    if (!_counted && _session >= kPlayAfter) {
        _counted = YES;
        entry[kPlays] = @([entry[kPlays] integerValue] + 1);
    }
    [self scheduleSave];
}

- (void)scheduleSave {
    if (_savePending) return;
    _savePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self save]; });
}

- (void)save {
    _savePending = NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:_tracks options:0 error:nil];
    if (data) [data writeToURL:fileURL() options:NSDataWritingAtomic error:nil];
}

- (void)leavingFront {
    [self commit];
    [self save];
}

// The state changes on the main thread (PlayerState.h), so nothing here is locked.
- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self commit];
    if (!SGHidden(SGKeyStats)) {
        _since = 0;
        return;
    }
    NSString *uri = SGURIString(state.track.URI);
    if (uri && ![uri isEqualToString:_uri]) {
        _session = 0;
        _counted = NO;
    }
    _uri = uri;
    BOOL playing = uri && state.isPlaying && !state.isPaused && !state.isLoading;
    _since = playing ? CACurrentMediaTime() : 0;
    if (!uri) return;
    NSMutableDictionary *entry = _tracks[uri];
    if (!entry) entry = _tracks[uri] = [NSMutableDictionary dictionary];
    NSString *title = state.track.trackTitle, *artist = state.track.artistName;
    id album = state.track.metadata[@"album_title"];
    if (title.length) entry[kTitle] = title;
    if (artist.length) entry[kArtist] = artist;
    if ([album isKindOfClass:NSString.class] && [album length]) entry[kAlbum] = album;
    [self armTick:playing];
}

// A checkpoint every 30 s while playing, so a long listen that ends with the app killed is not lost.
- (void)armTick:(BOOL)on {
    if (!on) {
        if (_tick) dispatch_source_cancel(_tick);
        _tick = nil;
        return;
    }
    if (_tick) return;
    _tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_tick, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), 30 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(_tick, ^{ [self commit]; });
    dispatch_resume(_tick);
}

- (double)totalSeconds {
    [self commit];
    double total = 0;
    for (NSDictionary *entry in _tracks.allValues) total += [entry[kSeconds] doubleValue];
    return total;
}

// {name, detail, seconds}, longest first. Artists and albums are the tracks added up by name.
- (NSArray<NSDictionary *> *)top:(SGStatsKind)kind limit:(NSUInteger)limit {
    [self commit];
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *entry in _tracks.allValues) {
        double seconds = [entry[kSeconds] doubleValue];
        NSString *title = entry[kTitle], *artist = entry[kArtist], *album = entry[kAlbum];
        NSString *name = kind == SGStatsSongs ? title : kind == SGStatsArtists ? artist : album;
        if (!name.length || seconds <= 0) continue;
        NSString *key = kind == SGStatsAlbums ? [NSString stringWithFormat:@"%@\n%@", album, artist ?: @""] : name;
        NSMutableDictionary *group = groups[key];
        if (!group) group = groups[key] = [@{@"name": name, @"seconds": @0} mutableCopy];
        if (kind != SGStatsArtists && artist.length) group[@"detail"] = artist;
        group[@"seconds"] = @([group[@"seconds"] doubleValue] + seconds);
    }
    NSArray *sorted = [groups.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"seconds"] compare:a[@"seconds"]];
    }];
    return sorted.count > limit ? [sorted subarrayWithRange:NSMakeRange(0, limit)] : sorted;
}

- (void)reset {
    [_tracks removeAllObjects];
    _session = 0;
    _counted = NO;
    [self save];
}
@end

#pragma mark - pages

static NSString *minutes(double seconds) {
    NSInteger m = (NSInteger)llround(seconds / 60);
    NSNumberFormatter *f = [NSNumberFormatter new];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    return [NSString stringWithFormat:@"%@ min", [f stringFromNumber:@(m)]];
}

NSString *SGStatsSummary(void) {
    return SGHidden(SGKeyStats) ? minutes([SGStatsStore.shared totalSeconds]) : @"Off";
}

static UIViewController *topPage(NSString *title, SGStatsKind kind) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    NSUInteger rank = 0;
    for (NSDictionary *item in [SGStatsStore.shared top:kind limit:50]) {
        double seconds = [item[@"seconds"] doubleValue];
        SGModRow *row = SGStatRow([NSString stringWithFormat:@"%lu. %@", (unsigned long)++rank, item[@"name"]], ^NSString *{ return minutes(seconds); });
        row.subtitle = item[@"detail"];
        [rows addObject:row];
    }
    NSString *empty = @"Nothing counted yet. Play something with the switch on.";
    return [[SGModPage alloc] initWithTitle:title intro:nil sections:@[SGSection(nil, rows)] footer:rows.count ? nil : empty];
}

static void confirmReset(void) {
    UIViewController *top = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) top = window.rootViewController;
    }
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset stats?" message:@"The listening list on this phone is deleted."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) { [SGStatsStore.shared reset]; }]];
    [top presentViewController:alert animated:YES completion:nil];
}

UIViewController *SGStatsPage(void) {
    SGModRow *minutesRow = SGStatRow(@"Minutes listened", ^NSString *{ return minutes([SGStatsStore.shared totalSeconds]); });
    SGModRow *songs = SGStatRow(@"Songs", ^NSString *{ return @([SGStatsStore.shared top:SGStatsSongs limit:100000].count).stringValue; });
    return [[SGModPage alloc] initWithTitle:@"Stats" intro:nil sections:@[
        SGSection(nil, @[SGOptionRow(@"Count my listening", @"Minutes per song, artist and album, kept on this phone only", SGKeyStats)]),
        SGSection(nil, @[minutesRow, songs]),
        SGSection(nil, @[
            SGPageRow(@"Top songs", ^UIViewController *{ return topPage(@"Top songs", SGStatsSongs); }),
            SGPageRow(@"Top artists", ^UIViewController *{ return topPage(@"Top artists", SGStatsArtists); }),
            SGPageRow(@"Top albums", ^UIViewController *{ return topPage(@"Top albums", SGStatsAlbums); }),
        ]),
        SGSection(nil, @[SGWarningRow(@"Reset stats", @"Deletes the list on this phone", ^{ confirmReset(); })]),
    ] footer:nil];
}

// Registered always, so the switch needs no restart; the observer reads it on every change.
__attribute__((constructor)) static void sgStatsInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ SGAddPlayerStateObserver(SGStatsStore.shared); });
}