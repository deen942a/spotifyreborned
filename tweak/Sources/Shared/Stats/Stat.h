// Listening stats: what was played, for how long, kept on this phone and nowhere else. The recorder
// (StatsRecorder.x) watches the player and feeds the store (StatsStore.m); the page (StatsPage.m)
// ranks what the store holds.
#import <UIKit/UIKit.h>

// Recording is on until switched off.
#define SGKeyStats @"spotifyglass.stats"

// A play counts once a track has been listened to this long, as on Spotify itself.
#define SGStatsPlayMs 30000

// Adds listening time to a track, and one play when `countsPlay`. Safe from any thread.
void SGStatsNote(NSString *uri, NSString *title, NSString *artist, NSString *artistURI,
                 NSString *album, NSString *albumURI, NSInteger listenedMs, BOOL countsPlay);

// What is recorded: tracks (uri -> title, artist, artistURI, album, albumURI, plays, ms), totalMs,
// plays and since (a Unix time). A copy, safe to read on any thread.
NSDictionary *SGStatsSnapshot(void);
void SGStatsReset(void);

UIViewController *SGStatsPage(void);   // the Listening stats page of Mod Settings