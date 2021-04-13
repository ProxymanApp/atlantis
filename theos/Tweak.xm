#import <atlantis-Swift.h>

%ctor {
    /** modify nil to hostName if you have multiple proxyman in same network **/
    [Atlantis startWithHostName:nil];
}
