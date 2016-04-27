//
//  PPOTConfiguration.m
//  PayPalOneTouch
//
//  Copyright © 2015 PayPal, Inc. All rights reserved.
//

#import "PPOTConfiguration.h"
#import "PPOTJSONHelper.h"
#import "PPOTMacros.h"
#import "PPOTSimpleKeychain.h"
#import "PPOTURLSession.h"
#if __has_include("BraintreeCore.h")
#import "BTLogger_Internal.h"
#else
#import <BraintreeCore/BTLogger_Internal.h>
#endif
#import <libkern/OSAtomic.h>

#include "PPDefaultConfigurationJSON.h"
// `PPDefaultConfigurationJSON.h` is generated by a build script from `otc-config.ios.json`;
// it defines these two variables:
//      unsigned char configuration_otc_config_ios_json[];
//      unsigned int configuration_otc_config_ios_json_len;
// `configuration_otc_config_ios_json` holds the contents of the `otc-config.ios.json` file.

#define PPEnvironmentProduction @"live"

#define kConfigurationFileDownloadURL             CARDIO_STR(@"https://www.paypalobjects.com/webstatic/otc/otc-config.ios.json")
#define kConfigurationFileDownloadTimeout         60
#define kConfigurationFileDownloadRetryInterval   (5 * 60)  // 5 minutes

#define kPPOTConfigurationFileMaximumAcceptableObsolescence   (4 * 60 * 60) // 4 hours

#define kPPOTConfigurationSupportedProtocolVersionsForWallet    @[@1, @2, @3]
#define kPPOTConfigurationSupportedProtocolVersionsForBrowser   @[@0, @3]

#define kPPOTConfigurationKeyOs                         CARDIO_STR(@"os")
#define kPPOTConfigurationKeyFileTimestamp              CARDIO_STR(@"file_timestamp")
#define kPPOTConfigurationKeyTarget                     CARDIO_STR(@"target")
#define kPPOTConfigurationKeyProtocolVersion            CARDIO_STR(@"protocol")
#define kPPOTConfigurationKeySupportedLocales           CARDIO_STR(@"supported_locales")
#define kPPOTConfigurationKeyScope                      CARDIO_STR(@"scope")
#define kPPOTConfigurationKeyURLScheme                  CARDIO_STR(@"scheme")
#define kPPOTConfigurationKeyApplications               CARDIO_STR(@"applications")
#define kPPOTConfigurationKeyEndpoints                  CARDIO_STR(@"endpoints")
#define kPPOTConfigurationKeyURL                        CARDIO_STR(@"url")
#define kPPOTConfigurationKeyCertificateSerialNumber    CARDIO_STR(@"certificate_serial_number")
#define kPPOTConfigurationKeyCertificate                CARDIO_STR(@"certificate")
#define kPPOTConfigurationKeyOAuthRecipes               CARDIO_STR(@"oauth2_recipes_in_decreasing_priority_order")
#define kPPOTConfigurationKeyCheckoutRecipes            CARDIO_STR(@"checkout_recipes_in_decreasing_priority_order")
#define kPPOTConfigurationKeyBillingAgreementRecipes    CARDIO_STR(@"billing_agreement_recipes_in_decreasing_priority_order")

#define kPPOTConfigurationValueWallet                   CARDIO_STR(@"wallet")
#define kPPOTConfigurationValueBrowser                  CARDIO_STR(@"browser")

#define kPPOTCoderKeyConfigurationRecipeTarget                      CARDIO_STR(@"target")
#define kPPOTCoderKeyConfigurationRecipeProtocolVersion             CARDIO_STR(@"protocol")
#define kPPOTCoderKeyConfigurationRecipeSupportedLocales            CARDIO_STR(@"supportedLocales")
#define kPPOTCoderKeyConfigurationRecipeTargetAppURLScheme          CARDIO_STR(@"targetAppURLScheme")
#define kPPOTCoderKeyConfigurationRecipeTargetAppBundleIDs          CARDIO_STR(@"targetAppBundleIDs")
#define kPPOTCoderKeyConfigurationRecipeEndpoints                   CARDIO_STR(@"endpoints")
#define kPPOTCoderKeyConfigurationRecipeScope                       CARDIO_STR(@"scope")
#define kPPOTCoderKeyConfigurationRecipeURL                         CARDIO_STR(@"url")
#define kPPOTCoderKeyConfigurationRecipeCertificateSerialNumber     CARDIO_STR(@"certificate_serial_number")
#define kPPOTCoderKeyConfigurationRecipeCertificate                 CARDIO_STR(@"certificate")

#define kPPOTCoderKeyConfigurationDownloadTime                CARDIO_STR(@"downloadTime")
#define kPPOTCoderKeyConfigurationTimestamp                   CARDIO_STR(@"timestamp")
#define kPPOTCoderKeyConfigurationOAuthRecipes                CARDIO_STR(@"oAuthRecipes")
#define kPPOTCoderKeyConfigurationCheckoutRecipes             CARDIO_STR(@"checkoutRecipes")
#define kPPOTCoderKeyConfigurationBillingAgreementRecipes     CARDIO_STR(@"billingAgreementRecipes")

#define kPPOTKeychainConfiguration              CARDIO_STR(@"PayPal_OTC_Configuration")

#define LOG_ERROR_AND_RETURN_NIL  { PPSDKLog(@"Bad configuration: error %d", __LINE__); return nil; }

#define STRING_FROM_DICTIONARY(STRING, DICTIONARY, KEY) \
NSString *STRING = [PPOTJSONHelper stringFromDictionary:DICTIONARY withKey:KEY]; \
if (!STRING) LOG_ERROR_AND_RETURN_NIL

#define DICTIONARY_FROM_DICTIONARY(DICTIONARY1, DICTIONARY2, KEY, REQUIRED) \
NSDictionary *DICTIONARY1 = [PPOTJSONHelper dictionaryFromDictionary:DICTIONARY2 withKey:KEY]; \
if (REQUIRED && !DICTIONARY1) LOG_ERROR_AND_RETURN_NIL

#define STRING_ARRAY_FROM_DICTIONARY(ARRAY, DICTIONARY, KEY, REQUIRED) \
NSArray *ARRAY = [PPOTJSONHelper stringArrayFromDictionary:DICTIONARY withKey:KEY]; \
if (REQUIRED && !ARRAY) LOG_ERROR_AND_RETURN_NIL

#define DICTIONARY_ARRAY_FROM_DICTIONARY(ARRAY, DICTIONARY, KEY, REQUIRED) \
NSArray *ARRAY = [PPOTJSONHelper dictionaryArrayFromDictionary:DICTIONARY withKey:KEY]; \
if (REQUIRED && !ARRAY) LOG_ERROR_AND_RETURN_NIL

#pragma mark - PPOTConfigurationRecipe

@implementation PPOTConfigurationRecipe

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    STRING_FROM_DICTIONARY(targetString, dictionary, kPPOTConfigurationKeyTarget)
    STRING_FROM_DICTIONARY(protocolVersionString, dictionary, kPPOTConfigurationKeyProtocolVersion)
    NSNumber *protocolVersionNumber = [NSNumber numberWithInteger:[protocolVersionString integerValue]];

    if ((self = [super init])) {
        if ([targetString isEqualToString:kPPOTConfigurationValueWallet]) {
            _target = PPOTRequestTargetOnDeviceApplication;

            if (![kPPOTConfigurationSupportedProtocolVersionsForWallet containsObject:protocolVersionNumber]) {
                LOG_ERROR_AND_RETURN_NIL
            }
            _protocolVersion = protocolVersionNumber;

            STRING_ARRAY_FROM_DICTIONARY(supportedLocalesArray, dictionary, kPPOTConfigurationKeySupportedLocales, NO)
            // protect against capitalization mistakes:
            NSMutableArray *uppercasedSupportedLocalesArray = [NSMutableArray arrayWithCapacity:[supportedLocalesArray count]];
            for (NSString *locale in supportedLocalesArray) {
                [uppercasedSupportedLocalesArray addObject:[locale uppercaseString]];
            }
            _supportedLocales = uppercasedSupportedLocalesArray;

            STRING_FROM_DICTIONARY(targetAppURLScheme, dictionary, kPPOTConfigurationKeyURLScheme)
            if ([targetAppURLScheme rangeOfString:@":"].location != NSNotFound ||
                [targetAppURLScheme rangeOfString:@"/"].location != NSNotFound) {
                LOG_ERROR_AND_RETURN_NIL
            }
            _targetAppURLScheme = targetAppURLScheme;

            STRING_ARRAY_FROM_DICTIONARY(targetsArray, dictionary, kPPOTConfigurationKeyApplications, YES)
            _targetAppBundleIDs = targetsArray;
        }
        else if ([targetString isEqualToString:kPPOTConfigurationValueBrowser]) {
            _target = PPOTRequestTargetBrowser;

            if (![kPPOTConfigurationSupportedProtocolVersionsForBrowser containsObject:protocolVersionNumber]) {
                LOG_ERROR_AND_RETURN_NIL
            }
            _protocolVersion = protocolVersionNumber;
        }
        else {
            LOG_ERROR_AND_RETURN_NIL
        }
    }

    return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [self init])) {
        _target = ((NSNumber *)[aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeTarget]).unsignedIntegerValue;
        _protocolVersion = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeProtocolVersion];

        if (_target == PPOTRequestTargetOnDeviceApplication) {
            _targetAppURLScheme = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeTargetAppURLScheme];
            _targetAppBundleIDs = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeTargetAppBundleIDs];
            _supportedLocales = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeSupportedLocales];
        }
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:@(self.target) forKey:kPPOTCoderKeyConfigurationRecipeTarget];
    [aCoder encodeObject:self.protocolVersion forKey:kPPOTCoderKeyConfigurationRecipeProtocolVersion];
    if (self.target == PPOTRequestTargetOnDeviceApplication) {
        [aCoder encodeObject:self.targetAppURLScheme forKey:kPPOTCoderKeyConfigurationRecipeTargetAppURLScheme];
        [aCoder encodeObject:self.targetAppBundleIDs forKey:kPPOTCoderKeyConfigurationRecipeTargetAppBundleIDs];
        [aCoder encodeObject:self.supportedLocales forKey:kPPOTCoderKeyConfigurationRecipeSupportedLocales];
    }
}

@end

#pragma mark - PPOTConfigurationRecipeEndpoint

@implementation PPOTConfigurationRecipeEndpoint

- (instancetype)initWithURL:(NSString *)url withCertificateSerialNumber:(NSString *)certificateSerialNumber withBase64EncodedCertificate:(NSString *)base64EncodedCertificate {
    if ((self = [super init])) {
        if (![url length] || ![certificateSerialNumber length] || ![base64EncodedCertificate length]) {
            LOG_ERROR_AND_RETURN_NIL
        }

        if (![url hasPrefix:@"https://"] && ![url hasPrefix:@"http://"]) {
            LOG_ERROR_AND_RETURN_NIL
        }

        _url = url;
        _certificateSerialNumber = certificateSerialNumber;
        _base64EncodedCertificate = base64EncodedCertificate;
    }
    return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super init])) {
        _url = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeURL];
        _certificateSerialNumber = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeCertificateSerialNumber];
        _base64EncodedCertificate = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeCertificate];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.url forKey:kPPOTCoderKeyConfigurationRecipeURL];
    [aCoder encodeObject:self.certificateSerialNumber forKey:kPPOTCoderKeyConfigurationRecipeCertificateSerialNumber];
    [aCoder encodeObject:self.base64EncodedCertificate forKey:kPPOTCoderKeyConfigurationRecipeCertificate];
}

@end

#pragma mark - PPOTConfigurationOAuthRecipe

@implementation PPOTConfigurationOAuthRecipe

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    if ((self = [super initWithDictionary:dictionary])) {
        STRING_ARRAY_FROM_DICTIONARY(scopeStrings, dictionary, kPPOTConfigurationKeyScope, YES)
        _scope = [NSSet setWithArray:scopeStrings];

        DICTIONARY_FROM_DICTIONARY(jsonEndpoints, dictionary, kPPOTConfigurationKeyEndpoints,
                                   self.target == PPOTRequestTargetBrowser && [self.protocolVersion isEqual:@(3)])
        if (![jsonEndpoints count]) {
            _endpoints = nil;
        }
        else {
            NSMutableDictionary *endpoints = [NSMutableDictionary dictionaryWithCapacity:[jsonEndpoints count]];
            for (NSString *environment in jsonEndpoints) {
                NSString *url = jsonEndpoints[environment][kPPOTConfigurationKeyURL];
                NSString *certificateSerialNumber = jsonEndpoints[environment][kPPOTConfigurationKeyCertificateSerialNumber];
                NSString *base64EncodedCertificate = jsonEndpoints[environment][kPPOTConfigurationKeyCertificate];

                PPOTConfigurationRecipeEndpoint *endpoint = [[PPOTConfigurationRecipeEndpoint alloc] initWithURL:url
                                                                                     withCertificateSerialNumber:certificateSerialNumber
                                                                                    withBase64EncodedCertificate:base64EncodedCertificate];
                if (!endpoint) {
                    LOG_ERROR_AND_RETURN_NIL
                }

                endpoints[environment] = endpoint;
            }

            if (!endpoints[PPEnvironmentProduction]) {
                LOG_ERROR_AND_RETURN_NIL
            }

            _endpoints = endpoints;
        }
    }
    return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        _scope = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeScope];

        if (self.target == PPOTRequestTargetBrowser) {
            _endpoints = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationRecipeEndpoints];
        }
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    [aCoder encodeObject:self.scope forKey:kPPOTCoderKeyConfigurationRecipeScope];

    if (self.target == PPOTRequestTargetBrowser) {
        [aCoder encodeObject:self.endpoints forKey:kPPOTCoderKeyConfigurationRecipeEndpoints];
    }
}

@end

#pragma mark - PPOTConfigurationCheckoutRecipe

@implementation PPOTConfigurationCheckoutRecipe

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if ((self = [super initWithDictionary:dict])) {
        // no subclass-specific properties, so far
    }
    return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        // no subclass-specific properties, so far
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    // no subclass-specific properties, so far
}

@end

#pragma mark - PPOTConfigurationBillingAgreementRecipe

@implementation PPOTConfigurationBillingAgreementRecipe

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    if ((self = [super initWithDictionary:dict])) {
        // no subclass-specific properties, so far
    }
    return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        // no subclass-specific properties, so far
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [super encodeWithCoder:aCoder];
    // no subclass-specific properties, so far
}

@end

#pragma mark - PPOTConfiguration

typedef void (^PPOTConfigurationFileDownloadCompletionBlock)(NSData *fileData);

@interface PPOTConfiguration ()
@property (nonatomic, strong, readwrite) NSDate *downloadTime;
@end

@implementation PPOTConfiguration

#pragma mark - debug-only stuff

#if DEBUG
static BOOL alwaysUseHardcodedConfiguration = NO;

+ (void)useHardcodedConfiguration:(BOOL)useHardcodedConfiguration {
    alwaysUseHardcodedConfiguration = useHardcodedConfiguration;
}
#endif

#pragma mark - public methods

+ (void)updateCacheAsNecessary {
    // If there is no persisted configuration, or if it's stale,
    // then download a fresh configuration file and persist it.

    static int nobodyIsWorkingOnThisAtTheMoment = 1;

    if (OSAtomicCompareAndSwapInt(1, 0, &nobodyIsWorkingOnThisAtTheMoment)) {

        PPOTConfiguration *currentConfiguration = [PPOTConfiguration fetchPersistentConfiguration];

        if (!currentConfiguration || fabs([currentConfiguration.downloadTime timeIntervalSinceNow]) > kPPOTConfigurationFileMaximumAcceptableObsolescence) {

            static NSDate *lastConfigurationFileDownloadAttemptTime = nil;

            if (!lastConfigurationFileDownloadAttemptTime ||
                fabs([lastConfigurationFileDownloadAttemptTime timeIntervalSinceNow]) > kConfigurationFileDownloadRetryInterval) {
                lastConfigurationFileDownloadAttemptTime = [NSDate date];

                NSURL *url = [NSURL URLWithString:kConfigurationFileDownloadURL];
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
                [request setHTTPMethod:@"GET"];

                // TODO: Can simplify by not specifying timeout interval. This might be better anyway to not specify because of slow networks.
                PPOTURLSession *session = [PPOTURLSession sessionWithTimeoutIntervalForRequest:kConfigurationFileDownloadTimeout];
                [session sendRequest:request
                     completionBlock:^(NSData *data, __attribute__((unused)) NSHTTPURLResponse *response, __attribute__((unused)) NSError *error) {
#if DEBUG
                         NSString *dataString = nil;
                         if (data) {
                             dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                         }
                         else {
                             dataString = @"<no data received>";
                         }
                         [[BTLogger sharedLogger] debug:@"Downloaded JSON config\n-> HTTP status: %ld\n-> file contents:\n%@\n", (long)response.statusCode, dataString];
#endif
                         PPOTConfiguration *configuration = data ? [[PPOTConfiguration alloc] initWithJSON:data] : nil;
                         if (configuration) {
                             configuration.downloadTime = [NSDate date];
                             [PPOTConfiguration storePersistentConfiguration:configuration];
                         }
                         [session finishTasksAndInvalidate];
                     }];
            }
        }

        nobodyIsWorkingOnThisAtTheMoment = 1;
    }
}

+ (PPOTConfiguration *)getCurrentConfiguration {
#if DEBUG
    if (alwaysUseHardcodedConfiguration) {
        return [self defaultConfiguration];
    }
#endif

    PPOTConfiguration *currentConfiguration = [PPOTConfiguration fetchPersistentConfiguration];

    if (!currentConfiguration) {
        currentConfiguration = [self defaultConfiguration];
    }

    return currentConfiguration;
}

+ (PPOTConfiguration *)configurationWithDictionary:(NSDictionary *)dictionary {
    return [[PPOTConfiguration alloc] initWithDictionary:dictionary];
}

#pragma mark - private methods

+ (void)initialize {
#if DEBUG
    NSAssert([PPOTConfiguration defaultConfiguration] != nil, @"otc-config.ios.json is invalid");
#endif
    if (self == [PPOTConfiguration class]) {
        [self updateCacheAsNecessary];
    }
}

+ (PPOTConfiguration *)defaultConfiguration {
    NSData *defaultConfigurationJSON = [NSData dataWithBytes:configuration_otc_config_ios_json
                                                      length:configuration_otc_config_ios_json_len];
#if DEBUG
    NSString *str = [[NSString alloc] initWithData:defaultConfigurationJSON encoding:NSUTF8StringEncoding];
    [[BTLogger sharedLogger] debug:@"Using default JSON config %@\n", str];
#endif

    PPOTConfiguration *defaultConfiguration = [[PPOTConfiguration alloc] initWithJSON:defaultConfigurationJSON];

    return defaultConfiguration;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary {
    STRING_FROM_DICTIONARY(os, dictionary, kPPOTConfigurationKeyOs)

    if (![os isEqualToString:@"iOS"]) {
        LOG_ERROR_AND_RETURN_NIL
    }

    STRING_FROM_DICTIONARY(fileTimestamp, dictionary, kPPOTConfigurationKeyFileTimestamp)

    // Currently we only support config file format 1.0.
    // If we ever need to update the file format, then the code here would presumably
    // first look for sub-dictionary "2.0" (or whatever) and then fallback to "1.0" as needed.
    DICTIONARY_FROM_DICTIONARY(subDictionary, dictionary, @"1.0", YES)

    DICTIONARY_ARRAY_FROM_DICTIONARY(prioritizedOAuthRecipesDictionaries, subDictionary, kPPOTConfigurationKeyOAuthRecipes, NO)
    DICTIONARY_ARRAY_FROM_DICTIONARY(prioritizedCheckoutRecipesDictionaries, subDictionary, kPPOTConfigurationKeyCheckoutRecipes, NO)
    DICTIONARY_ARRAY_FROM_DICTIONARY(prioritizedBillingAgreementRecipesDictionaries, subDictionary, kPPOTConfigurationKeyBillingAgreementRecipes, NO)

    if ((self = [super init])) {
        _downloadTime = [NSDate dateWithTimeIntervalSince1970:0]; // by default, mark file as obsolete
        _fileTimestamp = fileTimestamp;

        _prioritizedOAuthRecipes = [self prioritizedRecipesFromArray:prioritizedOAuthRecipesDictionaries withRecipeAdapter:^PPOTConfigurationRecipe *(NSDictionary *recipeDictionary) {
            return [[PPOTConfigurationOAuthRecipe alloc] initWithDictionary:recipeDictionary];
        }];

        _prioritizedCheckoutRecipes = [self prioritizedRecipesFromArray:prioritizedCheckoutRecipesDictionaries withRecipeAdapter:^PPOTConfigurationRecipe* (NSDictionary* recipeDictionary) {
            return [[PPOTConfigurationCheckoutRecipe alloc] initWithDictionary:recipeDictionary];
        }];

        _prioritizedBillingAgreementRecipes = [self prioritizedRecipesFromArray:prioritizedBillingAgreementRecipesDictionaries withRecipeAdapter:^PPOTConfigurationRecipe* (NSDictionary* recipeDictionary) {
            return [[PPOTConfigurationBillingAgreementRecipe alloc] initWithDictionary:recipeDictionary];
        }];

        if (!_prioritizedOAuthRecipes || !_prioritizedCheckoutRecipes || !_prioritizedBillingAgreementRecipes) {
            return nil;
        }
    }
    return self;
}

- (NSArray*)prioritizedRecipesFromArray:(NSArray*)recipes withRecipeAdapter:(PPOTConfigurationRecipe* (^)(NSDictionary*))recipeAdapter {
    NSMutableArray *prioritizedRecipes = [NSMutableArray arrayWithCapacity:[recipes count]];
    for (NSDictionary *recipeDictionary in recipes) {
        PPOTConfigurationRecipe *recipe = recipeAdapter(recipeDictionary);
        if (!recipe) {
            LOG_ERROR_AND_RETURN_NIL
        }
        [prioritizedRecipes addObject:recipe];
    }
    return prioritizedRecipes;
}

- (instancetype)initWithJSON:(NSData *)jsonData {
    NSError *error = nil;
    id jsonObject = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
    if (error || ![jsonObject isKindOfClass:[NSDictionary class]]) {
        LOG_ERROR_AND_RETURN_NIL
    }

    self = [self initWithDictionary:((NSDictionary *)jsonObject)];
    return self;
}

#pragma mark - description

- (NSString *)description {
    return [NSString stringWithFormat:@"PPOTConfiguration: %ld Authorization recipes, %ld Checkout recipes, %ld Billing Agreement recipes",
            (unsigned long)[self.prioritizedOAuthRecipes count],
            (unsigned long)[self.prioritizedCheckoutRecipes count],
            (unsigned long)[self.prioritizedBillingAgreementRecipes count]];
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [self init])) {
        _downloadTime = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationDownloadTime];
        _fileTimestamp = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationTimestamp];
        _prioritizedOAuthRecipes = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationOAuthRecipes];
        _prioritizedCheckoutRecipes = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationCheckoutRecipes];
        _prioritizedBillingAgreementRecipes = [aDecoder decodeObjectForKey:kPPOTCoderKeyConfigurationBillingAgreementRecipes];
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.downloadTime forKey:kPPOTCoderKeyConfigurationDownloadTime];
    [aCoder encodeObject:self.fileTimestamp forKey:kPPOTCoderKeyConfigurationTimestamp];
    [aCoder encodeObject:self.prioritizedOAuthRecipes forKey:kPPOTCoderKeyConfigurationOAuthRecipes];
    [aCoder encodeObject:self.prioritizedCheckoutRecipes forKey:kPPOTCoderKeyConfigurationCheckoutRecipes];
    [aCoder encodeObject:self.prioritizedBillingAgreementRecipes forKey:kPPOTCoderKeyConfigurationBillingAgreementRecipes];
}

#pragma mark - keychain persistence

+ (PPOTConfiguration *)fetchPersistentConfiguration {
    return (PPOTConfiguration *) [PPOTSimpleKeychain unarchiveObjectWithDataForKey:kPPOTKeychainConfiguration];
}

+ (void)storePersistentConfiguration:(PPOTConfiguration *)configuration {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:configuration];
    [PPOTSimpleKeychain setData:data forKey:kPPOTKeychainConfiguration];
}

@end

@implementation PPConfiguration
@end

@implementation PPConfigurationCheckoutRecipe
@end

@implementation PPConfigurationBillingAgreementRecipe
@end

@implementation PPConfigurationOAuthRecipe
@end

@implementation PPConfigurationRecipeEndpoint
@end

