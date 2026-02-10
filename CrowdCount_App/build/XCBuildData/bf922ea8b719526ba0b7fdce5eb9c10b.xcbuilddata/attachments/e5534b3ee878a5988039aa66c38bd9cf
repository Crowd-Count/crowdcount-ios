#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Stripe_Stripe3DS2_SWIFTPM_MODULE_BUNDLER_FINDER : NSObject
@end

@implementation Stripe_Stripe3DS2_SWIFTPM_MODULE_BUNDLER_FINDER
@end

NSBundle* Stripe_Stripe3DS2_SWIFTPM_MODULE_BUNDLE() {
    NSString *bundleName = @"Stripe_Stripe3DS2";

    NSArray<NSURL*> *candidates = @[
        NSBundle.mainBundle.resourceURL,
        [NSBundle bundleForClass:[Stripe_Stripe3DS2_SWIFTPM_MODULE_BUNDLER_FINDER class]].resourceURL,
        NSBundle.mainBundle.bundleURL
    ];

    for (NSURL* candidate in candidates) {
        NSURL *bundlePath = [candidate URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.bundle", bundleName]];

        NSBundle *bundle = [NSBundle bundleWithURL:bundlePath];
        if (bundle != nil) {
            return bundle;
        }
    }

    @throw [[NSException alloc] initWithName:@"SwiftPMResourcesAccessor" reason:[NSString stringWithFormat:@"unable to find bundle named %@", bundleName] userInfo:nil];
}

NS_ASSUME_NONNULL_END