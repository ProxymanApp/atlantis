#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(AtlantisReactNative, NSObject)

RCT_EXTERN_METHOD(start:(NSString *)hostName)

RCT_EXTERN_METHOD(stop)

RCT_EXTERN_METHOD(isRunning:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

@end
