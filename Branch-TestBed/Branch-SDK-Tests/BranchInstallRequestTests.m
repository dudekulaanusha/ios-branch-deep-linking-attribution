//
//  BranchInstallRequestTests.m
//  Branch-TestBed
//
//  Created by Graham Mueller on 6/24/15.
//  Copyright (c) 2015 Branch Metrics. All rights reserved.
//

#import "BNCTestCase.h"
#import "Branch.h"
#import "BNCApplication.h"
#import "BNCApplication+BNCTest.h"
#import "BranchInstallRequest.h"
#import "BNCPreferenceHelper.h"
#import "BNCSystemObserver.h"
#import "BranchConstants.h"
#import "BNCEncodingUtils.h"
#import <OCMock/OCMock.h>

@interface BranchInstallRequestTests : BNCTestCase
@end

@implementation BranchInstallRequestTests

- (void)setUp {
    [super setUp];
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    preferenceHelper.installParams = nil;
    preferenceHelper.randomizedBundleToken = nil;
    preferenceHelper.checkedAppleSearchAdAttribution = NO;
    [preferenceHelper saveContentAnalyticsManifest:nil];
    [preferenceHelper synchronize];
}

- (void)testRequestBody {
    NSString * const HARDWARE_ID = @"foo-hardware-id";
    NSNumber * const AD_TRACKING_SAFE = @YES;
    NSString * const BUNDLE_ID = @"foo-bundle-id";
    NSString * const APP_VERSION = @"foo-app-version";
    NSString * const OS = @"foo-os";
    NSString * const OS_VERSION = @"foo-os-version";
    NSString * const URI_SCHEME = @"foo-uri-scheme";
    NSString * const LINK_IDENTIFIER = @"foo-link-id";
    NSString * const BRAND = @"foo-brand";
    NSString * const MODEL = @"foo-model";
    NSNumber * const SCREEN_WIDTH = @1;
    NSNumber * const SCREEN_HEIGHT = @2;

    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    preferenceHelper.randomizedBundleToken = nil;
    preferenceHelper.isDebug = YES;
    preferenceHelper.linkClickIdentifier = LINK_IDENTIFIER;
    
    id systemObserverMock = OCMClassMock([BNCSystemObserver class]);
    [[[systemObserverMock stub] andReturnValue:AD_TRACKING_SAFE] adTrackingEnabled];
    [[[systemObserverMock stub] andReturn:BUNDLE_ID] bundleIdentifier];
    [[[systemObserverMock stub] andReturn:APP_VERSION] applicationVersion];
    [[[systemObserverMock stub] andReturn:OS] osName];
    [[[systemObserverMock stub] andReturn:OS_VERSION] osVersion];
    [[[systemObserverMock stub] andReturn:URI_SCHEME] defaultURIScheme];
    [[[systemObserverMock stub] andReturn:BRAND] brand];
    [[[systemObserverMock stub] andReturn:MODEL] model];
    [[[systemObserverMock stub] andReturn:SCREEN_WIDTH] screenWidth];
    [[[systemObserverMock stub] andReturn:SCREEN_HEIGHT] screenHeight];

    NSDate *appDate = [NSDate date];
    [[BNCApplication currentApplication]
        setAppOriginalInstallDate:appDate
        firstInstallDate:appDate
        lastUpdateDate:appDate];
    [preferenceHelper setPreviousAppBuildDate:nil];

    NSMutableDictionary *expectedParams = [NSMutableDictionary dictionaryWithDictionary:@{
        @"app_version":                 @"foo-app-version",
        @"apple_ad_attribution_checked":@0,
        @"debug":                       @1,
        @"facebook_app_link_checked":   @0,
        @"latest_install_time":         BNCWireFormatFromDate(appDate),
        @"ios_bundle_id":               @"foo-bundle-id",
        @"ios_team_id":                 @"R63EM248DP",
        @"lastest_update_time":         BNCWireFormatFromDate(appDate),
        @"link_identifier":             @"foo-link-id",
        @"first_install_time":          BNCWireFormatFromDate(appDate),
        @"uri_scheme":                  @"foo-uri-scheme",
        @"update":                      @0,
        @"apple_testflight":            @0
    }];
    if (!self.class.isApplication) expectedParams[@"ios_team_id"] = nil;

    BranchInstallRequest *request = [[BranchInstallRequest alloc] init];
    id serverInterfaceMock = OCMClassMock([BNCServerInterface class]);
    [[serverInterfaceMock expect]
		postRequest:[OCMArg checkWithBlock:^BOOL(id value) {
            if (![value isKindOfClass:[NSDictionary class]]) {
                XCTFail(@"Expected NSDictionary. Got '%@'.", NSStringFromClass([value class]));
                return YES;
            }
            NSDictionary *dictionary = (NSDictionary*)value;
            XCTAssertEqualObjects(dictionary, expectedParams);
            return YES;
        }]
		url:[OCMArg checkWithBlock:^BOOL(id value) {
            if (![((NSString*)value) containsString:BRANCH_REQUEST_ENDPOINT_INSTALL]) {
                XCTAssertEqualObjects(value, BRANCH_REQUEST_ENDPOINT_INSTALL);
            }
            return YES;
        }]
		key:[OCMArg any]
		callback:[OCMArg any]];

    [request makeRequest:serverInterfaceMock key:nil callback:NULL];
    [serverInterfaceMock verify];
}

- (void)testSuccessWithAllKeysAndIsReferrable {
    NSString * const DEVICE_TOKEN = @"foo-token";
    NSString * const USER_URL = @"http://foo";
    NSString * const DEVELOPER_ID = @"foo";
    NSString * const SESSION_ID = @"foo-session";
    NSString * const SESSION_PARAMS = @"{\"+clicked_branch_link\":1,\"foo\":\"bar\"}";
    NSString * const RANDOMIZED_BUNDLE_TOKEN = @"randomized_bundle_token";
    
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{
        BRANCH_RESPONSE_KEY_RANDOMIZED_DEVICE_TOKEN: DEVICE_TOKEN,
        BRANCH_RESPONSE_KEY_USER_URL: USER_URL,
        BRANCH_RESPONSE_KEY_DEVELOPER_IDENTITY: DEVELOPER_ID,
        BRANCH_RESPONSE_KEY_SESSION_ID: SESSION_ID,
        BRANCH_RESPONSE_KEY_SESSION_DATA: SESSION_PARAMS,
        BRANCH_RESPONSE_KEY_RANDOMIZED_BUNDLE_TOKEN: RANDOMIZED_BUNDLE_TOKEN
    };

    XCTestExpectation *openExpectation = [self expectationWithDescription:@"OpenRequest Expectation"];
    BranchInstallRequest *request = [[BranchInstallRequest alloc] initWithCallback:^(BOOL success, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue(success);
        [self safelyFulfillExpectation:openExpectation];
    }];

    [Branch setBranchKey:@"key_live_foo"];
    [request processResponse:response error:nil];
    [self awaitExpectations];

    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    XCTAssertEqualObjects(preferenceHelper.randomizedDeviceToken, DEVICE_TOKEN);
    XCTAssertEqualObjects(preferenceHelper.userUrl, USER_URL);
    XCTAssertEqualObjects(preferenceHelper.userIdentity, DEVELOPER_ID);
    XCTAssertEqualObjects(preferenceHelper.sessionID, SESSION_ID);
    XCTAssertEqualObjects(preferenceHelper.sessionParams, SESSION_PARAMS);
    XCTAssertEqualObjects(preferenceHelper.installParams, SESSION_PARAMS);
    XCTAssertEqualObjects(preferenceHelper.randomizedBundleToken, RANDOMIZED_BUNDLE_TOKEN);
    XCTAssertNil(preferenceHelper.linkClickIdentifier);
}

- (void)testSuccessWithAllKeysAndIsNotReferrable {
    NSString * const DEVICE_TOKEN = @"foo-token";
    NSString * const USER_URL = @"http://foo";
    NSString * const DEVELOPER_ID = @"foo";
    NSString * const SESSION_ID = @"foo-session";
    NSString * const SESSION_PARAMS = @"{\"foo\":\"bar\"}";
    NSString * const INSTALL_PARAMS = @"{\"bar\":\"foo\"}";
    NSString * const RANDOMIZED_BUNDLE_TOKEN = @"randomized_bundle_token";
    
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{
        BRANCH_RESPONSE_KEY_RANDOMIZED_DEVICE_TOKEN: DEVICE_TOKEN,
        BRANCH_RESPONSE_KEY_USER_URL: USER_URL,
        BRANCH_RESPONSE_KEY_DEVELOPER_IDENTITY: DEVELOPER_ID,
        BRANCH_RESPONSE_KEY_SESSION_ID: SESSION_ID,
        BRANCH_RESPONSE_KEY_SESSION_DATA: SESSION_PARAMS,
        BRANCH_RESPONSE_KEY_RANDOMIZED_BUNDLE_TOKEN: RANDOMIZED_BUNDLE_TOKEN
    };
    
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    preferenceHelper.installParams = INSTALL_PARAMS;
    
    XCTestExpectation *openExpectation = [self expectationWithDescription:@"OpenRequest Expectation"];
    BranchInstallRequest *request = [[BranchInstallRequest alloc] initWithCallback:^(BOOL success, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue(success);
        [self safelyFulfillExpectation:openExpectation];
    }];

    [Branch setBranchKey:@"key_live_foo"];    
    [request processResponse:response error:nil];
    
    [self awaitExpectations];
    
    XCTAssertEqualObjects(preferenceHelper.randomizedDeviceToken, DEVICE_TOKEN);
    XCTAssertEqualObjects(preferenceHelper.userUrl, USER_URL);
    XCTAssertEqualObjects(preferenceHelper.userIdentity, DEVELOPER_ID);
    XCTAssertEqualObjects(preferenceHelper.sessionID, SESSION_ID);
    XCTAssertEqualObjects(preferenceHelper.sessionParams, SESSION_PARAMS);
    XCTAssertEqualObjects(preferenceHelper.installParams, INSTALL_PARAMS);
    XCTAssertEqualObjects(preferenceHelper.randomizedBundleToken, RANDOMIZED_BUNDLE_TOKEN);
    XCTAssertNil(preferenceHelper.linkClickIdentifier);
}

- (void)testSuccessWithNoSessionParamsAndIsNotReferrable {
    NSString * const DEVICE_TOKEN = @"foo-token";
    NSString * const USER_URL = @"http://foo";
    NSString * const DEVELOPER_ID = @"foo";
    NSString * const SESSION_ID = @"foo-session";
    NSString * const INSTALL_PARAMS = @"{\"bar\":\"foo\"}";
    NSString * const RANDOMIZED_BUNDLE_TOKEN = @"randomized_bundle_token";
    
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{
        BRANCH_RESPONSE_KEY_RANDOMIZED_DEVICE_TOKEN: DEVICE_TOKEN,
        BRANCH_RESPONSE_KEY_USER_URL: USER_URL,
        BRANCH_RESPONSE_KEY_DEVELOPER_IDENTITY: DEVELOPER_ID,
        BRANCH_RESPONSE_KEY_SESSION_ID: SESSION_ID,
        BRANCH_RESPONSE_KEY_RANDOMIZED_BUNDLE_TOKEN: RANDOMIZED_BUNDLE_TOKEN
    };
    
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    preferenceHelper.installParams = INSTALL_PARAMS;
    
    XCTestExpectation *openExpectation = [self expectationWithDescription:@"OpenRequest Expectation"];
    BranchInstallRequest *request = [[BranchInstallRequest alloc] initWithCallback:^(BOOL success, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue(success);
        [self safelyFulfillExpectation:openExpectation];
    }];

    [Branch setBranchKey:@"key_live_foo"];
    [request processResponse:response error:nil];
    [self awaitExpectations];
    
    XCTAssertEqualObjects(preferenceHelper.randomizedDeviceToken, DEVICE_TOKEN);
    XCTAssertEqualObjects(preferenceHelper.userUrl, USER_URL);
    XCTAssertEqualObjects(preferenceHelper.userIdentity, DEVELOPER_ID);
    XCTAssertEqualObjects(preferenceHelper.sessionID, SESSION_ID);
    XCTAssertEqualObjects(preferenceHelper.installParams, INSTALL_PARAMS);
    XCTAssertEqualObjects(preferenceHelper.randomizedBundleToken, RANDOMIZED_BUNDLE_TOKEN);
    XCTAssertNil(preferenceHelper.sessionParams);
    XCTAssertNil(preferenceHelper.linkClickIdentifier);
}

- (void)testSuccessWithNoSessionParamsAndIsReferrableAndAllowToBeClearIsNotSet {
    NSString * const DEVICE_TOKEN = @"foo-token";
    NSString * const USER_URL = @"http://foo";
    NSString * const DEVELOPER_ID = @"foo";
    NSString * const SESSION_ID = @"foo-session";
    NSString * const INSTALL_PARAMS = @"{\"bar\":\"foo\"}";
    NSString * const RANDOMIZED_BUNDLE_TOKEN = @"randomized_bundle_token";
    
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{
        BRANCH_RESPONSE_KEY_RANDOMIZED_DEVICE_TOKEN: DEVICE_TOKEN,
        BRANCH_RESPONSE_KEY_USER_URL: USER_URL,
        BRANCH_RESPONSE_KEY_DEVELOPER_IDENTITY: DEVELOPER_ID,
        BRANCH_RESPONSE_KEY_SESSION_ID: SESSION_ID,
        BRANCH_RESPONSE_KEY_RANDOMIZED_BUNDLE_TOKEN: RANDOMIZED_BUNDLE_TOKEN
    };
    
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    preferenceHelper.installParams = INSTALL_PARAMS;
    
    XCTestExpectation *openExpectation = [self expectationWithDescription:@"OpenRequest Expectation"];
    BranchOpenRequest *request = [[BranchOpenRequest alloc] initWithCallback:^(BOOL success, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue(success);
        [self safelyFulfillExpectation:openExpectation];
    }];

    [Branch setBranchKey:@"key_live_foo"];
    [request processResponse:response error:nil];
    [self awaitExpectations];
    
    XCTAssertEqualObjects(preferenceHelper.randomizedDeviceToken, DEVICE_TOKEN);
    XCTAssertEqualObjects(preferenceHelper.userUrl, USER_URL);
    XCTAssertEqualObjects(preferenceHelper.userIdentity, DEVELOPER_ID);
    XCTAssertEqualObjects(preferenceHelper.sessionID, SESSION_ID);
    XCTAssertEqualObjects(preferenceHelper.installParams, INSTALL_PARAMS);
    XCTAssertEqualObjects(preferenceHelper.randomizedBundleToken, RANDOMIZED_BUNDLE_TOKEN);
    XCTAssertNil(preferenceHelper.sessionParams);
    XCTAssertNil(preferenceHelper.linkClickIdentifier);
}

- (void)testSuccessWithNoSessionParamsAndIsReferrableAndAllowToBeClearIsSet {
    NSString * const DEVICE_TOKEN = @"foo-token";
    NSString * const USER_URL = @"http://foo";
    NSString * const DEVELOPER_ID = @"foo";
    NSString * const SESSION_ID = @"foo-session";
    NSString * const RANDOMIZED_BUNDLE_TOKEN = @"randomized_bundle_token";
    
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{
        BRANCH_RESPONSE_KEY_RANDOMIZED_DEVICE_TOKEN: DEVICE_TOKEN,
        BRANCH_RESPONSE_KEY_USER_URL: USER_URL,
        BRANCH_RESPONSE_KEY_DEVELOPER_IDENTITY: DEVELOPER_ID,
        BRANCH_RESPONSE_KEY_SESSION_ID: SESSION_ID,
        BRANCH_RESPONSE_KEY_RANDOMIZED_BUNDLE_TOKEN: RANDOMIZED_BUNDLE_TOKEN
    };

    XCTestExpectation *openExpectation = [self expectationWithDescription:@"OpenRequest Expectation"];
    BranchInstallRequest *request = [[BranchInstallRequest alloc] initWithCallback:^(BOOL success, NSError *error) {
        XCTAssertNil(error);
        XCTAssertTrue(success);
        [self safelyFulfillExpectation:openExpectation];
    } isInstall:YES];

    [Branch setBranchKey:@"key_live_foo"];
    [request processResponse:response error:nil];
    [self awaitExpectations];

    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    XCTAssertEqualObjects(preferenceHelper.randomizedDeviceToken, DEVICE_TOKEN);
    XCTAssertEqualObjects(preferenceHelper.userUrl, USER_URL);
    XCTAssertEqualObjects(preferenceHelper.userIdentity, DEVELOPER_ID);
    XCTAssertEqualObjects(preferenceHelper.sessionID, SESSION_ID);
    XCTAssertEqualObjects(preferenceHelper.randomizedBundleToken, RANDOMIZED_BUNDLE_TOKEN);
    XCTAssertNil(preferenceHelper.sessionParams);
    XCTAssertNil(preferenceHelper.linkClickIdentifier);
    XCTAssertNil(preferenceHelper.installParams);
}

- (void)testInstallWhenReferrableAndNullData {
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];

    XCTestExpectation *expectation = [self expectationWithDescription:@"ReferrableInstall"];
    BranchInstallRequest *request = [[BranchInstallRequest alloc] initWithCallback:^(BOOL changed, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNil(preferenceHelper.installParams);
        [self safelyFulfillExpectation:expectation];
    }];

    [Branch setBranchKey:@"key_live_foo"];
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{};
    [request processResponse:response error:nil];
    [self awaitExpectations];
}

- (void)testInstallWhenReferrableAndNonNullData {
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];

    NSString * const INSTALL_PARAMS = @"{\"+clicked_branch_link\":1,\"foo\":\"bar\"}";
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Request Expectation"];
    BranchInstallRequest *request = [[BranchInstallRequest alloc] initWithCallback:^(BOOL changed, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(preferenceHelper.installParams, INSTALL_PARAMS);
        
        [self safelyFulfillExpectation:expectation];
    }];

    [Branch setBranchKey:@"key_live_foo"];
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{ BRANCH_RESPONSE_KEY_SESSION_DATA: INSTALL_PARAMS };
    [request processResponse:response error:nil];
    [self awaitExpectations];
}

- (void)testInstallWhenReferrableAndNoInstallParamsAndNonLinkClickData {
    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    
    NSString * const OPEN_PARAMS = @"{\"+clicked_branch_link\":0}";
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Request Expectation"];
    BranchInstallRequest *request = [[BranchInstallRequest alloc] initWithCallback:^(BOOL changed, NSError *error) {
        XCTAssertNil(error);
        XCTAssertNil(preferenceHelper.installParams);
        
        [self safelyFulfillExpectation:expectation];
    }];

    [Branch setBranchKey:@"key_live_foo"];
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{ BRANCH_RESPONSE_KEY_SESSION_DATA: OPEN_PARAMS };
    [request processResponse:response error:nil];
    [self awaitExpectations];
}

- (void)testInstallWhenNotReferrable {
    //  'isReferrable' seems to be an empty concept in iOS.
    //  It is in the code but not used. -- Edward.

    BNCPreferenceHelper *preferenceHelper = [BNCPreferenceHelper sharedInstance];
    NSString * const INSTALL_PARAMS = @"{\"+clicked_branch_link\":1,\"foo\":\"bar\"}";
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Request Expectation"];
    BranchInstallRequest *request =
		[[BranchInstallRequest alloc] initWithCallback:^(BOOL changed, NSError *error) {
        	XCTAssertNil(error);
        	XCTAssert([preferenceHelper.installParams isEqualToString:INSTALL_PARAMS]);
        	[self safelyFulfillExpectation:expectation];
    		}];

    [Branch setBranchKey:@"key_live_foo"];
    BNCServerResponse *response = [[BNCServerResponse alloc] init];
    response.data = @{ BRANCH_RESPONSE_KEY_SESSION_DATA: INSTALL_PARAMS };
    [request processResponse:response error:nil];
    
    [self awaitExpectations];
}

@end
