//
//  NSObject+AtlantisHelper.h
//  atlantis-proxyman
//
//  Created by Nghia Tran on 10/04/2021.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AtlantisHelper: NSObject

+(id _Nullable) swizzleWebSocketReceiveMessageWithCompleteHandler:(id)handler responseHandler:(void (^_Nullable)(NSString* _Nullable str, NSData* _Nullable data, NSError* _Nullable error)) responseHandler;

@end

NS_ASSUME_NONNULL_END
