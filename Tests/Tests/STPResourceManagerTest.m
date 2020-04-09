//
//  STPResourceManagerTest.m
//  StripeiOS Tests
//
//  Created by David Estes on 4/8/20.
//  Copyright © 2020 Stripe, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "STPResourceManager.h"

@interface STPResourceManager (Private)
- (NSURL *)cacheUrlForResource:(NSString *)name;
- (void)resetDiskCache;
- (void)resetMemoryCache;
@end

@interface STPResourceManagerTest : XCTestCase

@end

@implementation STPResourceManagerTest

- (void)testDownloadFiles {
    [[STPResourceManager sharedManager] resetDiskCache];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Update image"];
    UIImage *image1 = [[STPResourceManager sharedManager] imageNamed:@"a1.png"];
    UIImage *image2 = [[STPResourceManager sharedManager] imageNamed:@"a2.png" updateHandler:^(UIImage * _Nullable image) {
        NSLog(@"%@", image);
        XCTAssertNotEqualObjects(image1, image);
        [expectation fulfill];
    }];
    XCTAssertEqualObjects(image1, image2);
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testDoNotUpdateIfFileInCache {
    [[STPResourceManager sharedManager] resetDiskCache];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for initial image download"];
    UIImage *image2 = [[STPResourceManager sharedManager] imageNamed:@"a2.png" updateHandler:^(UIImage * _Nullable image) {
        NSLog(@"%@", image);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    
    [[STPResourceManager sharedManager] resetMemoryCache];
    XCTestExpectation *expectation2 = [[XCTestExpectation alloc] initWithDescription:@"Wait for image to re-download (which shouldn't happen)."];
    image2 = [[STPResourceManager sharedManager] imageNamed:@"a2.png" updateHandler:^(UIImage * _Nullable image) {
        NSLog(@"%@", image);
        [expectation2 fulfill];
    }];
    XCTWaiterResult result = [XCTWaiter waitForExpectations:@[expectation2] timeout:5];
    if (result != XCTWaiterResultTimedOut) {
        XCTFail("We should have timed out: The update handler was called when it shouldn't have been.");
    }
}

- (void)testDoUpdateIfFileIsOutdated {
    [[STPResourceManager sharedManager] resetDiskCache];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Wait for initial image download"];
    UIImage *image2 = [[STPResourceManager sharedManager] imageNamed:@"a2.png" updateHandler:^(UIImage * _Nullable image) {
        NSLog(@"%@", image);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    // manually set back the file's expiration date
    NSURL *cachedFileURL = [[STPResourceManager sharedManager] cacheUrlForResource:@"a2.png"];
    NSDate *oneWeekAgo = [NSDate dateWithTimeIntervalSinceNow:-(60 * 60 * 24 * 7 + 60)]; // one week and 60 seconds ago
    [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate : oneWeekAgo} ofItemAtPath:[cachedFileURL path] error:nil];

    [[STPResourceManager sharedManager] resetMemoryCache];
    XCTestExpectation *expectation2 = [self expectationWithDescription:@"Wait for updated image redownload"];
    image2 = [[STPResourceManager sharedManager] imageNamed:@"a2.png" updateHandler:^(UIImage * _Nullable image) {
        NSLog(@"%@", image);
        [expectation2 fulfill];
    }];
    [self waitForExpectationsWithTimeout:5 handler:nil];
}

@end
