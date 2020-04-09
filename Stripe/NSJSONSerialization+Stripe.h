//
//  NSJSONSerialization+Stripe.h
//  StripeiOS
//
//  Created by David Estes on 4/9/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSJSONSerialization (STPDeserializeDictionary)
+ (NSDictionary * _Nullable)stp_JSONDictionaryWithData:(NSData *)data;
@end

NS_ASSUME_NONNULL_END
