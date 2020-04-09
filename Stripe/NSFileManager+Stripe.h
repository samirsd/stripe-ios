//
//  NSFileManager+Stripe.h
//  StripeiOS
//
//  Created by David Estes on 4/9/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSFileManager (STPOverwriting)
- (BOOL)stp_destructivelyMoveItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
