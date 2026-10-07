// A cover of the user's own for a file from the Files app: picked in Mod Settings, kept in the app's
// own Library, keyed by the file's Spotify URI (spotify:local:artist:album:title:seconds), and drawn
// in place of the one Spotify shows wherever the mod can reach it: the redesigned player's cover
// (Redesigned/Player/PlayerArtwork.x) and the lock screen's and Control Center's (LocalCoversHook.x).
// Stays on this phone; nothing is sent anywhere.
#import <UIKit/UIKit.h>

// Posted on the main queue when a cover is set or removed.
extern NSNotificationName const SGLocalCoverDidChangeNotification;

BOOL SGIsLocalURI(NSString *uri);
// The cover chosen for this URI, nil for none and for any URI that is not a local file. Any thread.
UIImage *SGLocalCoverFor(NSString *uri);
void SGLocalCoverSet(NSString *uri, UIImage *image);
void SGLocalCoverRemove(NSString *uri);

// The Local file covers page, and how many files have one.
UIViewController *SGLocalCoversPage(void);
NSString *SGLocalCoversSummary(void);
