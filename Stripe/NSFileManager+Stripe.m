//
//  NSFileManager+Stripe.m
//  StripeiOS
//
//  Created by David Estes on 4/9/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

#import "NSFileManager+Stripe.h"

@implementation NSFileManager (STPOverwriting)
- (BOOL)stp_destructivelyMoveItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError **)error {
    NSError *moveError;
    BOOL didMove = [[NSFileManager defaultManager] moveItemAtURL:srcURL toURL:dstURL error:&moveError];
    // The file may already exist, in which case we'd like to replace it:
    if (moveError.code == NSFileWriteFileExistsError) {
        [[NSFileManager defaultManager] removeItemAtURL:dstURL error:nil];
        didMove = [[NSFileManager defaultManager] moveItemAtURL:srcURL toURL:dstURL error:&moveError];
    }
    
    if (error) {
        *error = moveError;
    }
    return didMove;
}
@end
