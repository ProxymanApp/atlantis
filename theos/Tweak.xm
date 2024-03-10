#import <atlantis-Swift.h>
#import <Foundation/Foundation.h>

%ctor {
    NSLog(@"[atlantis] init...");
    NSString *path = @"/var/mobile/Library/Preferences/proxyman.atlantis.settings.plist";
    NSString *enableHostKeyPath = @"shouldEnableHost";
    NSString *hostKeyPath = @"host";
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    NSString *keyPath = [NSString stringWithFormat:@"Settings-%@", bundleIdentifier];
    BOOL enabled = NO;
    if (([[prefs objectForKey:keyPath] boolValue])) {
        enabled = YES;
    }
    NSLog(@"[atlantis] enable for [%@] ? %@", bundleIdentifier, enabled ? @"Y":@"N");
    if (enabled) {
        BOOL enableHost = NO;
        if (([[prefs objectForKey:enableHostKeyPath] boolValue])) {
            enableHost = YES;
        }
        NSString *hostName = [prefs objectForKey:hostKeyPath];
        NSLog(@"[atlantis] enable Customized Host? %@", enableHost ? @"Y":@"N");
        if (enableHost && hostName != nil) {
            NSLog(@"[atlantis] Customized Host %@", hostName);
            [Atlantis startWithHostName:hostName];
        } else {
            NSLog(@"[atlantis] start without Specfic Host");
            [Atlantis startWithHostName:nil];
        }
    }
}
