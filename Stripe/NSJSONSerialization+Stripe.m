//
//  NSJSONSerialization+Stripe.m
//  StripeiOS
//
//  Created by David Estes on 4/9/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

#import "NSJSONSerialization+Stripe.h"

@implementation NSJSONSerialization (STPDeserializeDictionary)
+ (NSDictionary * _Nullable)stp_JSONDictionaryWithData:(NSData *)data {
    if (data == nil) {
        return nil;
    }
    NSError *jsonError;
    NSDictionary *json = nil;

    // This can throw exceptions internally if we give it bad data.
    // Wrap it in a try/catch block and return nil on failures. We can't do anything sensible if the JSON isn't valid.
    @try {
        json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    } @catch (NSException *exception) {
        return nil;
    }

    if (jsonError == nil && json != nil && [json isKindOfClass:[NSDictionary class]]) {
        return json;
    }
    
    return nil;
}

@end
