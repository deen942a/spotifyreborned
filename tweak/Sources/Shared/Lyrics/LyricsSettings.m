// The Lyrics page's parts; App/Pages.m assembles the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Lyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

SGModSection *SGLyricsSourcesSection(BOOL namingSource) {
    SGModRow *sources = SGPageRow(@"Sources", ^UIViewController *{ return SGLyricsSourcesPage(); });
    sources.value = ^NSString *{
        NSMutableArray<NSString *> *names = [NSMutableArray array];
        for (NSString *key in SGLyricsOrder()) [names addObject:SGLyricsProviderFor(key).name];
        return names.count ? [names componentsJoinedByString:@", "] : @"Off";
    };
    // Spicy Lyrics only answers to a key of the user's own: one row opens the page that makes it,
    // the next takes it, and the footer says how.
    SGModRow *getKey = SGLinkRow(@"Get a Spicy Lyrics key", @"developers.spicylyrics.org",
                                 @"https://developers.spicylyrics.org/dashboard");
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObjects:sources, getKey, SGSpicyLyricsKeyRow(),
        SGOptionRow(@"Lyrics for every track", @"Even where Spotify has none", SGKeyLyricsAllTracks), nil];
    if (namingSource) [rows addObject:SGOptionRow(@"Show source", nil, SGKeyLyricsCredit)];
    return SGNotedSection(@"Sources", rows,
        @"Spicy Lyrics needs a key of your own. Tap Get a Spicy Lyrics key, sign in, create an application, "
         "enable client access with “No origin header” turned on, then copy the key that starts with sl_pk_ "
         "and paste it into Spicy Lyrics key. Restart Spotify afterwards.");
}

SGModRow *SGLockScreenLyricsRow(void) {
    return SGOptionRow(@"Lock screen lyrics", @"Current line in place of the artist", SGKeyLockScreenLyrics);
}

SGModRow *SGLyricsTranslationLanguageRow(void) {
    SGModRow *row = SGChoiceRow(@"Translation language", nil, SGKeyLyricsTranslationLanguage, SGLyricsTranslationLanguageNames(), 0);
    row.choiceFooter = @"Used when the lyrics come with translations. Any shows the first.";
    return row;
}

// Only the redesign's lyrics view sweeps words.
SGModRow *SGLyricsWordTimingRow(void) {
    return SGOptionRow(@"Simulate word timing", nil, SGKeyLyricsSimulateWords);
}