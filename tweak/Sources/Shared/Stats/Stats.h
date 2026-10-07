// Listening stats: the minutes each song, artist and album has played on this phone, counted from the
// player's state (Shared/Player/PlayerState.h) and kept in a file in the app's own Library. Nothing
// is sent anywhere. Off until switched on; the observer is always registered and asks the switch on
// every change, so flipping it needs no restart.
#import <UIKit/UIKit.h>

#define SGKeyStats @"spotifyglass.stats"

// The Stats page: the switch, the totals, Top songs / artists / albums and the reset.
UIViewController *SGStatsPage(void);
// What sits beside the Stats row's chevron: "Off", or the minutes so far.
NSString *SGStatsSummary(void);
