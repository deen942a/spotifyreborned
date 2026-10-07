// The custom cover of a local file on the lock screen and in Control Center: Spotify gives the system its
// cover through MPNowPlayingInfoCenter, so the picture in that dictionary is swapped for the user's.
// Only while the dictionary is the playing track's; it can still be the last track's for a moment.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "LocalCovers.h"

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    SPTPlayerState *state = SGPlayerState();
    UIImage *cover = info ? SGLocalCoverFor(SGURIString(state.track.URI)) : nil;
    if (!cover || ![state.track.trackTitle isEqualToString:info[MPMediaItemPropertyTitle]]) {
        %orig;
        return;
    }
    NSMutableDictionary *copy = [info mutableCopy];
    copy[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:cover.size
                                                                       requestHandler:^UIImage *(CGSize size) { return cover; }];
    %orig(copy);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"MPNowPlayingInfoCenter"]);
}
