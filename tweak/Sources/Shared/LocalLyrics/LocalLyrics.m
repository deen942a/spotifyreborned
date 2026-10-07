// Lyrics for a file from the Files app. Spotify asks for no lyrics of a local file, so no reply carries any
// to the player's page for one; this asks the mod's own sources the moment a local file is the track, and
// the page, the lock screen and the Live Activity read the lines like any track's (Shared/Lyrics).
// The sources that search by name (BiniLyrics, Unison, NetEase, LRCLIB) answer it; Musixmatch and Spicy
// Lyrics match by Spotify's id and are passed over (Shared/LyricsSources). Needs a source switched on.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"

@interface SGLocalLyrics : NSObject <SGPlayerStateObserver>
@end

@implementation SGLocalLyrics
- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *uri = SGURIString(state.track.URI);
    if (![uri hasPrefix:@"spotify:local:"]) return;
    // The same id Shared/Lyrics gives the track: the URI without "spotify:".
    SGKaraokeRequestLyrics([uri substringFromIndex:@"spotify:".length]);
}
@end

static SGLocalLyrics *sg_localLyrics;

// Registered always; the request is asked only for a local file, and does nothing without a source on.
__attribute__((constructor)) static void sgLocalLyricsInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_localLyrics = [SGLocalLyrics new];
        SGAddPlayerStateObserver(sg_localLyrics);
    });
}
