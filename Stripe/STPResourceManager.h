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

@interface STPResourceManager : NSObject

+ (instancetype)sharedManager;

// TODO: docs here
// name: name of resource
// updateHandler: optional handler called if the object updates. you may receive an empty result if we don't have this file available, you should implement.
- (UIImage *)imageNamed:(NSString *)name;
- (NSDictionary *)jsonNamed:(NSString *)name;
- (UIImage *)imageNamed:(NSString *)name updateHandler:(nullable void (^)(UIImage * _Nullable))updateHandler;
- (NSDictionary *)jsonNamed:(NSString *)name updateHandler:(nullable void (^)(UIImage * _Nullable))updateHandler;

@end

NS_ASSUME_NONNULL_END
