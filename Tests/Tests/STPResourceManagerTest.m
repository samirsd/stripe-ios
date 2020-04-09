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

@interface STPResourceManagerTest : XCTestCase

@end

@implementation STPResourceManagerTest

- (void)testDownload140Files {
    [STPResourceManager sharedManager];
}
/*
- (void)testValidUSPostalCodes {
    NSArray *codes = @[
                       @"10002",
                       @"10002-1234",
                       @"100021234",
                       @"21218",
                       ];
    for (NSString *code in codes) {
        XCTAssertEqual([STPPostalCodeValidator validationStateForPostalCode:code
                                                                countryCode:@"US"],
                       STPCardValidationStateValid,
                       @"Valid US postal code test failed for code: %@", code);
    }
}

- (void)testInvalidUSPostalCodes {
    NSArray *codes = @[
                       @"100A03",
                       @"12345-12345",
                       @"1234512345",
                       @"$$$$$",
                       @"foo",
                       ];
    for (NSString *code in codes) {
        XCTAssertEqual([STPPostalCodeValidator validationStateForPostalCode:code
                                                                countryCode:@"US"],
                       STPCardValidationStateInvalid,
                       @"Invalid US postal code test failed for code: %@", code);
    }
}

- (void)testIncompleteUSPostalCodes {
    NSArray *codes = @[
                       @"",
                       @"123",
                       @"12345-",
                       @"12345-12",
                       ];
    for (NSString *code in codes) {
        XCTAssertEqual([STPPostalCodeValidator validationStateForPostalCode:code
                                                                countryCode:@"US"],
                       STPCardValidationStateIncomplete,
                       @"Incomplete US postal code test failed for code: %@", code);
    }
}

- (void)testValidGenericPostalCodes {
    NSArray *codes = @[
                       @"ABC10002",
                       @"10002-ABCD",
                       @"ABCDE",
                       ];
    for (NSString *code in codes) {
        XCTAssertEqual([STPPostalCodeValidator validationStateForPostalCode:code
                                                                countryCode:@"UK"],
                       STPCardValidationStateValid,
                       @"Valid generic postal code test failed for code: %@", code);
    }
}

- (void)testIncompleteGenericPostalCodes {
    NSArray *codes = @[
                       @"",
                       ];
    for (NSString *code in codes) {
        XCTAssertEqual([STPPostalCodeValidator validationStateForPostalCode:code
                                                                countryCode:@"UK"],
                       STPCardValidationStateIncomplete,
                       @"Incomplete generic postal code test failed for code: %@", code);
    }
}*/

@end
