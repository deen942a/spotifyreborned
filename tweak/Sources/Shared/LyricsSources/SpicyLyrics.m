// Spicy Lyrics, through its official Developer API (https://developers.spicylyrics.org). Syllable
// timed for a large catalogue, with a second voice and background vocals.
//
// It needs a key of the user's own: create an application on the developer dashboard, enable client
// access for it, and paste the publishable key (sl_pk_...) on the Lyrics page. The mod is a native
// app and sends no Origin header, so the application's client access must allow requests without
// one ("No origin header" in the dashboard). A secret key (sl_sk_...) is refused: it is not meant to
// live in an app on someone's phone.
//
// The source asks by Spotify's track id and sends only that and the key; never the user's account.
//
// The API's terms ask that the provider be shown and, when the source is Spicy Lyrics, that the
// uploader and maker be linked. This file reads those names but the credit line the mod draws is the
// provider's name only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsSources.h"

static NSString *const kEndpoint = @"https://api.spicylyrics.org/v1/lyrics/";
// Under "spotifyglass." like every setting, so the reset sweeps it.
static NSString *const kKeyDefaults = @"spotifyglass.spicyLyricsKey";

#pragma mark - the key

static NSString *storedKey(void) {
    NSString *key = [NSUserDefaults.standardUserDefaults stringForKey:kKeyDefaults];
    return key.length ? key : nil;
}

static void say(UIViewController *owner, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}

static void promptForKey(void) {
    UIViewController *top = SGTopController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Spicy Lyrics key"
        message:@"Get one at developers.spicylyrics.org: sign in, create an application, enable client access "
                 "and turn on “No origin header”, then copy the key that starts with sl_pk_ and paste it here."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"sl_pk_…";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *typed = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!typed.length) return;
        if ([typed hasPrefix:@"sl_sk_"]) {
            say(top, @"That is a secret key", @"A secret key must not live in an app on your phone. Create client access for your "
                                               "application and paste the sl_pk_ key instead.");
        } else if (![typed hasPrefix:@"sl_pk_"]) {
            say(top, @"Not a client key", @"A Spicy Lyrics client key starts with sl_pk_.");
        } else {
            [NSUserDefaults.standardUserDefaults setObject:typed forKey:kKeyDefaults];
            say(top, @"Saved", @"Restart Spotify so tracks it already asked about are asked again.");
        }
    }]];
    if (storedKey()) {
        [alert addAction:[UIAlertAction actionWithTitle:@"Remove key" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:kKeyDefaults];
        }]];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

// The row on the Lyrics page that takes the key.
SGModRow *SGSpicyLyricsKeyRow(void) {
    return SGStatActionRow(@"Spicy Lyrics key", @"From developers.spicylyrics.org",
                           ^NSString *{ return storedKey() ? @"Set" : @"Not set"; },
                           ^{ promptForKey(); });
}

#pragma mark - lyrics out of the reply

static NSString *textOf(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

// Spicy Lyrics times in seconds, the mod in milliseconds.
static NSInteger msOf(id value) {
    return [value isKindOfClass:NSNumber.class] ? (NSInteger)llround([value doubleValue] * 1000.0) : 0;
}

static BOOL flag(id value) {
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}

static NSArray<SGKaraokeWord *> *wordsFrom(id syllables) {
    if (![syllables isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<SGKaraokeWord *> *words = [NSMutableArray array];
    for (id entry in syllables) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *text = [textOf(entry[@"Text"]) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!text.length) continue;
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = text;
        word.start = msOf(entry[@"StartTime"]);
        word.end = MAX(word.start, msOf(entry[@"EndTime"]));
        // A syllable that carries on a word sits flush against the one before it.
        word.joined = words.count > 0 && flag(entry[@"IsPartOfWord"]);
        [words addObject:word];
    }
    return words;
}

static SGKaraokeLine *lineFrom(NSArray<SGKaraokeWord *> *words, NSInteger start, NSInteger end) {
    SGKaraokeLine *line = [SGKaraokeLine new];
    line.words = words;
    line.start = start > 0 || words.count == 0 ? start : words.firstObject.start;
    line.end = end > line.start ? end : words.lastObject.end;
    line.timing = SGKaraokeTimingWords;
    return line;
}

static NSArray<SGKaraokeLine *> *syllableLines(NSArray *content) {
    NSMutableArray<SGKaraokeLine *> *lines = [NSMutableArray array];
    if (![content isKindOfClass:NSArray.class]) return lines;
    for (id group in content) {
        if (![group isKindOfClass:NSDictionary.class] || ![group[@"Type"] isEqual:@"Vocal"]) continue;
        NSDictionary *lead = [group[@"Lead"] isKindOfClass:NSDictionary.class] ? group[@"Lead"] : nil;
        NSArray<SGKaraokeWord *> *words = wordsFrom(lead[@"Syllables"]);
        if (!words.count) continue;
        SGKaraokeLine *line = lineFrom(words, msOf(lead[@"StartTime"]), msOf(lead[@"EndTime"]));
        line.voice = flag(group[@"OppositeAligned"]) ? @"v2" : @"v1";

        // A line can carry several background vocals; the mod hangs them off the line as one.
        NSMutableArray<SGKaraokeWord *> *backing = [NSMutableArray array];
        id backgrounds = group[@"Background"];
        if ([backgrounds isKindOfClass:NSArray.class]) {
            for (id background in backgrounds) {
                if ([background isKindOfClass:NSDictionary.class]) [backing addObjectsFromArray:wordsFrom(background[@"Syllables"])];
            }
        }
        if (backing.count) line.backing = lineFrom(backing, 0, 0);
        [lines addObject:line];
    }
    return lines;
}

static SGLyricsResult *resultFrom(id body, SGLyricsQuery *query) {
    if (![body isKindOfClass:NSDictionary.class]) return nil;
    NSString *type = textOf(body[@"Type"]);
    SGLyricsResult *result = [SGLyricsResult new];

    if ([type isEqualToString:@"Syllable"]) {
        NSArray<SGKaraokeLine *> *lines = syllableLines(body[@"Content"]);
        if (!lines.count) return nil;
        SGKaraokeAlignVoices(lines);
        result.synced = YES;
        result.wordTimed = YES;
        result.karaokeLines = lines;
    } else if ([type isEqualToString:@"Line"]) {
        NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        id content = body[@"Content"];
        for (id group in [content isKindOfClass:NSArray.class] ? content : @[]) {
            if (![group isKindOfClass:NSDictionary.class] || ![group[@"Type"] isEqual:@"Vocal"]) continue;
            NSString *text = textOf(group[@"Text"]);
            if (!text.length) continue;
            [starts addObject:@(msOf(group[@"StartTime"]))];
            [texts addObject:text];
        }
        if (!texts.count) return nil;
        result.synced = YES;
        result.wordTimed = NO;
        result.karaokeLines = SGKaraokeEstimatedLines(starts, texts);
    } else if ([type isEqualToString:@"Static"]) {
        NSMutableArray<NSString *> *texts = [NSMutableArray array];
        id rows = body[@"Lines"];
        for (id line in [rows isKindOfClass:NSArray.class] ? rows : @[]) {
            NSString *text = [line isKindOfClass:NSDictionary.class] ? textOf(line[@"Text"]) : @"";
            if (text.length) [texts addObject:text];
        }
        if (!texts.count) return nil;
        NSMutableArray<NSNumber *> *zeros = [NSMutableArray arrayWithCapacity:texts.count];
        for (NSUInteger i = 0; i < texts.count; i++) [zeros addObject:@0];
        result.synced = NO;
        result.wordTimed = NO;
        result.starts = zeros;
        result.texts = texts;
        result.karaokeLines = SGKaraokeStaticLines(texts);
        return result;
    } else {
        SGLog(@"spicylyrics: unknown lyrics type '%@' for %@", type, query.trackID);
        return nil;
    }

    NSArray<NSNumber *> *starts;
    NSArray<NSString *> *texts;
    SGLyricsPageLines(result.karaokeLines, &starts, &texts);
    result.starts = starts;
    result.texts = texts;
    return result;
}

#pragma mark - the source

// A Spotify track id is 22 base62 characters; anything else is not worth a request.
static BOOL isTrackID(NSString *value) {
    if (value.length != 22) return NO;
    NSCharacterSet *base62 = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"];
    return [value rangeOfCharacterFromSet:base62.invertedSet].location == NSNotFound;
}

SGLyricsAsk SGSpicyLyricsAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    NSString *key = storedKey();
    if (!key) {
        SGLog(@"spicylyrics: no key set");
        done(nil);
        return;
    }
    if (!isTrackID(query.trackID)) {
        SGLog(@"spicylyrics: '%@' is not a track id", query.trackID);
        done(nil);
        return;
    }
    NSURL *url = [NSURL URLWithString:[kEndpoint stringByAppendingString:query.trackID]];
    NSDictionary *headers = @{@"Authorization": [@"Bearer " stringByAppendingString:key]};
    SGLyricsGetJSON(url, headers, ^(id root) {
        NSDictionary *body = [root isKindOfClass:NSDictionary.class] ? root[@"Body"] : nil;
        if (![body isKindOfClass:NSDictionary.class]) {
            // 401 or 403 mean the key was refused (wrong key, or the origin rule); 404 no lyrics; 429 a limit.
            id status = [root isKindOfClass:NSDictionary.class] ? root[@"Status"] : nil;
            SGLog(@"spicylyrics: no lyrics for %@ (status %@)", query.trackID, status ?: @"none");
            done(nil);
            return;
        }
        SGLyricsResult *result = resultFrom(body, query);
        if (!result) {
            SGLog(@"spicylyrics: nothing usable in the lyrics for %@", query.trackID);
            done(nil);
            return;
        }
        NSDictionary *credit = [body[@"UploadAttribution"] isKindOfClass:NSDictionary.class] ? body[@"UploadAttribution"] : nil;
        SGLog(@"spicylyrics: %@ has %lu %@ lines, source %@, uploader %@, maker %@", query.trackID,
              (unsigned long)result.karaokeLines.count,
              result.wordTimed ? @"word timed" : (result.synced ? @"line timed" : @"unsynced"),
              body[@"source"], credit[@"Uploader"][@"username"], credit[@"Maker"][@"username"]);
        done(result);
    });
};