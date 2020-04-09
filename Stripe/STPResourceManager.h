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


- (UIImage *)imageNamed:(NSString *)name;
- (NSDictionary *)jsonNamed:(NSString *)name;
- (UIImage *)imageNamed:(NSString *)name updateHandler:(nullable void (^)(UIImage * _Nullable))updateHandler;
- (NSDictionary *)jsonNamed:(NSString *)name updateHandler:(nullable void (^)(NSDictionary * _Nullable))updateHandler;

@end

NS_ASSUME_NONNULL_END
