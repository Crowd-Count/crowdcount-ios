#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "LogoRounded" asset catalog image resource.
static NSString * const ACImageNameLogoRounded AC_SWIFT_PRIVATE = @"LogoRounded";

/// The "TransparentLogo" asset catalog image resource.
static NSString * const ACImageNameTransparentLogo AC_SWIFT_PRIVATE = @"TransparentLogo";

/// The "TransparentLogoBlack" asset catalog image resource.
static NSString * const ACImageNameTransparentLogoBlack AC_SWIFT_PRIVATE = @"TransparentLogoBlack";

/// The "mapIcon" asset catalog image resource.
static NSString * const ACImageNameMapIcon AC_SWIFT_PRIVATE = @"mapIcon";

#undef AC_SWIFT_PRIVATE
