//
//  STPResourceManager.h
//  StripeiOS
//
//  Created by David Estes on 4/8/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface STPResourceManager : NSObject <NSURLSessionDelegate>

+ (instancetype)sharedManager;

/**
Returns an image resource with the specified name.

@param name This is the full filename, such as `bank.png`. @2x or @3x will be added automatically based on the device resolution.
@param updateHandler If an updated image is available, this optional handler will be called. It won't be called if the originally returned image was already up to date.
*/
- (UIImage *)imageNamed:(NSString *)name updateHandler:(nullable void (^)(UIImage * _Nullable))updateHandler;
- (UIImage *)imageNamed:(NSString *)name;

/**
Returns a dictionary containing the contents of a JSON resource.

@param name This is the full filename, such as `banks.json`.
@param updateHandler If an updated dictionary is available, this handler will be called. It won't be called if the originally returned dictionary was already up to date.
*/
- (NSDictionary *)jsonNamed:(NSString *)name updateHandler:(nullable void (^)(NSDictionary * _Nullable))updateHandler;
- (NSDictionary *)jsonNamed:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
