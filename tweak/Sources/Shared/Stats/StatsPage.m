// The Listening stats page: the totals, then the top songs, artists and albums, ranked by plays and
// by time listened. Built when the page is opened, so it shows what was recorded up to then.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Stats.h"

static const NSUInteger kTop = 10;

static NSString *durationText(long long ms) {
    long long minutes = ms / 60000;
    if (minutes < 60) return [NSString stringWithFormat:@"%lld min", minutes];
    return [NSString stringWithFormat:@"%lldh %lldm", minutes / 60, minutes % 60];
}

static NSArray<NSDictionary *> *ranked(NSArray<NSDictionary *> *items) {
    return [items sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSInteger pa = [a[@"plays"] integerValue], pb = [b[@"plays"] integerValue];
        if (pa != pb) return pa > pb ? NSOrderedAscending : NSOrderedDescending;
        long long ma = [a[@"ms"] longLongValue], mb = [b[@"ms"] longLongValue];
        if (ma != mb) return ma > mb ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
}

// Tracks folded into one entry per artist or album: name, sub (the line under it), plays, ms.
static NSArray<NSDictionary *> *grouped(NSDictionary *tracks, NSString *nameKey, NSString *uriKey, NSString *subKey) {
    NSMutableDictionary<NSString *, NSMutableDictionary *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *track in tracks.allValues) {
        NSString *name = track[nameKey];
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        NSString *uri = track[uriKey];
        NSString *sub = subKey ? track[subKey] : nil;
        NSString *key = uri.length ? uri : [NSString stringWithFormat:@"%@\n%@", name, sub ?: @""];
        NSMutableDictionary *group = groups[key];
        if (!group) {
            group = [@{@"name": name, @"sub": sub ?: @"", @"plays": @0, @"ms": @0} mutableCopy];
            groups[key] = group;
        }
        group[@"plays"] = @([group[@"plays"] integerValue] + [track[@"plays"] integerValue]);
        group[@"ms"] = @([group[@"ms"] longLongValue] + [track[@"ms"] longLongValue]);
    }
    return groups.allValues;
}

static SGModSection *topSection(NSString *title, NSArray<NSDictionary *> *items) {
    if (!items.count) return nil;
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    NSArray<NSDictionary *> *top = ranked(items);
    for (NSUInteger i = 0; i < top.count && i < kTop; i++) {
        NSDictionary *item = top[i];
        NSInteger plays = [item[@"plays"] integerValue];
        NSString *value = [NSString stringWithFormat:@"%ld %@ · %@", (long)plays, plays == 1 ? @"play" : @"plays",
                           durationText([item[@"ms"] longLongValue])];
        SGModRow *row = SGStatRow([NSString stringWithFormat:@"%lu. %@", (unsigned long)i + 1, item[@"name"]],
                                  ^NSString *{ return value; });
        row.subtitle = item[@"sub"];
        [rows addObject:row];
    }
    return SGSection(title, rows);
}

static void confirmReset(void) {
    UIViewController *top = SGTopController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset stats?"
        message:@"This deletes every play and minute recorded on this phone."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGStatsReset();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

UIViewController *SGStatsPage(void) {
    NSDictionary *snapshot = SGStatsSnapshot();
    NSDictionary *tracks = snapshot[@"tracks"];
    NSString *minutes = durationText([snapshot[@"totalMs"] longLongValue]);
    NSString *plays = [snapshot[@"plays"] stringValue];
    NSTimeInterval since = [snapshot[@"since"] doubleValue];
    NSString *date = since > 0
        ? [NSDateFormatter localizedStringFromDate:[NSDate dateWithTimeIntervalSince1970:since]
                                         dateStyle:NSDateFormatterMediumStyle timeStyle:NSDateFormatterNoStyle]
        : @"-";

    NSMutableArray<SGModSection *> *sections = [NSMutableArray array];
    [sections addObject:SGSection(nil, @[
        SGSwitchRow(@"Track listening stats", @"Kept on this phone only", SGKeyStats),
        SGStatRow(@"Time listened", ^NSString *{ return minutes; }),
        SGStatRow(@"Plays", ^NSString *{ return plays; }),
        SGStatRow(@"Counting since", ^NSString *{ return date; }),
    ])];

    NSMutableArray<NSDictionary *> *songs = [NSMutableArray array];
    for (NSDictionary *track in tracks.allValues) {
        if (![track[@"title"] length]) continue;
        [songs addObject:@{@"name": track[@"title"], @"sub": track[@"artist"] ?: @"",
                           @"plays": track[@"plays"] ?: @0, @"ms": track[@"ms"] ?: @0}];
    }
    SGModSection *topSongs = topSection(@"Top songs", songs);
    SGModSection *topArtists = topSection(@"Top artists", grouped(tracks, @"artist", @"artistURI", nil));
    SGModSection *topAlbums = topSection(@"Top albums", grouped(tracks, @"album", @"albumURI", @"artist"));
    for (SGModSection *section in @[topSongs ?: NSNull.null, topArtists ?: NSNull.null, topAlbums ?: NSNull.null]) {
        if ([section isKindOfClass:SGModSection.class]) [sections addObject:section];
    }
    [sections addObject:SGSection(nil, @[SGWarningRow(@"Reset stats", @"Deletes everything recorded", ^{ confirmReset(); })])];

    return [[SGModPage alloc] initWithTitle:@"Listening stats"
                                      intro:nil
                                   sections:sections
                                     footer:@"A play counts after 30 seconds of listening. Only time spent playing is counted, "
                                             "and everything stays on this phone."];
}
