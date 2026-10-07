// Listens to the player and counts the time it spends playing. Every two seconds it asks the player
// for its state: while a track plays, the time since the last look goes to that track; once it has
// had SGStatsPlayMs of listening it also counts as a play. Pausing, seeking and skipping need no
// hooks: only time spent playing counts.
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Headers/SPTPlayer.h"
#import "Stats.h"

static NSString *sg_uri;
static NSInteger sg_listenedMs;
static BOOL sg_counted;
static CFTimeInterval sg_lastLook;   // 0 while nothing was playing at the last look

static NSString *stringOf(id value) {
    if ([value isKindOfClass:NSURL.class]) return ((NSURL *)value).absoluteString;
    return [value isKindOfClass:NSString.class] ? value : (value ? [value description] : nil);
}

static void look(void) {
    if (!SGEnabled(SGKeyStats)) { sg_lastLook = 0; return; }
    id player = SGKaraokePlayer();
    SPTPlayerState *state = [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
    SPTPlayerTrack *track = [state respondsToSelector:@selector(track)] ? state.track : nil;
    NSString *uri = stringOf(track.URI);
    if (!uri.length) { sg_lastLook = 0; return; }

    if (![uri isEqualToString:sg_uri]) {
        sg_uri = uri;
        sg_listenedMs = 0;
        sg_counted = NO;
        static BOOL logged;
        if (!logged) {
            logged = YES;
            SGLog(@"stats: first track %@, metadata keys %@", uri, track.metadata.allKeys);
        }
    }

    CFTimeInterval now = CACurrentMediaTime();
    BOOL playing = !state.isPaused && !state.isLoading;
    // Never more than a few seconds a look: a look that came late (the app was busy) is not a long listen.
    NSInteger delta = (playing && sg_lastLook > 0) ? (NSInteger)(MIN(now - sg_lastLook, 6.0) * 1000) : 0;
    sg_lastLook = playing ? now : 0;
    if (delta <= 0) return;

    sg_listenedMs += delta;
    BOOL countsPlay = !sg_counted && sg_listenedMs >= SGStatsPlayMs;
    if (countsPlay) sg_counted = YES;

    NSDictionary<NSString *, NSString *> *metadata = track.metadata;
    SGStatsNote(uri, track.trackTitle, track.artistName, stringOf(track.artistURI),
                metadata[@"album_title"], metadata[@"album_uri"], delta, countsPlay);
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSTimer *timer = [NSTimer timerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) { look(); }];
        // Common modes, so the count goes on while a list is being scrolled.
        [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    });
}
