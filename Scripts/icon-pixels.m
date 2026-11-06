#import <CommonCrypto/CommonDigest.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <dlfcn.h>

// Host audit only: read stored bitmaps without asking IconServices to render the glass stack.
@interface NSObject (IconPixelAudit)
- (id)initWithURL:(NSURL *)url error:(NSError **)error;
- (id)iconImageWithName:(NSString *)name scaleFactor:(double)scale deviceIdiom:(NSInteger)idiom
         deviceSubtype:(NSUInteger)subtype displayGamut:(NSInteger)gamut
       layoutDirection:(NSInteger)direction sizeClassHorizontal:(NSInteger)horizontal
     sizeClassVertical:(NSInteger)vertical desiredSize:(CGSize)size appearanceName:(NSString *)appearance;
- (id)_rendition;
- (NSString *)name;
- (CGImageRef)unslicedImage;
@end

static void fail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    exit(1);
}

static NSDictionary *fingerprint(CGImageRef image, NSString *exportPath) {
    if (!image) fail(@"CoreUI/ImageIO did not return a stored bitmap");
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    if (width != 1024 || height != 1024) fail(@"Expected a 1024-square bitmap");
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width * 4,
        space, kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) fail(@"Could not create sRGB RGBA context");
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    BOOL opaque = YES;
    const uint8_t *bytes = pixels.bytes;
    for (size_t i = 3; i < pixels.length; i += 4) opaque &= bytes[i] == 255;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(pixels.bytes, (CC_LONG)pixels.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (size_t i = 0; i < sizeof(digest); i++) [hex appendFormat:@"%02x", digest[i]];
    if (exportPath) {
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)[NSURL fileURLWithPath:exportPath], CFSTR("public.png"), 1, NULL);
        if (!destination) fail(@"Could not create PNG export");
        CGImageDestinationAddImage(destination, image, NULL);
        BOOL saved = CGImageDestinationFinalize(destination);
        CFRelease(destination);
        if (!saved) fail(@"Could not save PNG export");
    }
    return @{@"width": @(width), @"height": @(height), @"opaque": @(opaque), @"rgbaSHA256": hex};
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2 || argc > 3) fail(@"Usage: icon-pixels <Assets.car|ChronoFlow.appiconset> [export-directory]");
        NSString *path = @(argv[1]);
        NSString *exportDirectory = argc == 3 ? @(argv[2]) : nil;
        if (exportDirectory) {
            NSError *error = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:exportDirectory
                withIntermediateDirectories:YES attributes:nil error:&error]) fail(error.description);
        }
        id catalog = nil;
        if ([path.pathExtension isEqualToString:@"car"]) {
            if (!dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_NOW))
                fail(@(dlerror()));
            Class catalogClass = NSClassFromString(@"CUICatalog");
            SEL lookup = @selector(iconImageWithName:scaleFactor:deviceIdiom:deviceSubtype:displayGamut:
                layoutDirection:sizeClassHorizontal:sizeClassVertical:desiredSize:appearanceName:);
            if (![catalogClass instancesRespondToSelector:lookup]) fail(@"Unsupported host CoreUI lookup API");
            NSError *error = nil;
            catalog = [[catalogClass alloc] initWithURL:[NSURL fileURLWithPath:path] error:&error];
            if (!catalog) fail(error.description ?: @"Could not open catalog");
        } else if (![path.pathExtension isEqualToString:@"appiconset"]) {
            fail(@"Expected an Assets.car or appiconset path");
        }
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        NSArray *appearances = @[@"UIAppearanceAny", @"UIAppearanceDark", @"ISAppearanceTintable"];
        NSArray *filenames = @[@"AppIcon-default.png", @"AppIcon-dark.png", @"AppIcon-tinted.png"];
        for (NSUInteger index = 0; index < appearances.count; index++) {
            NSString *appearance = appearances[index];
            NSString *exportPath = exportDirectory
                ? [exportDirectory stringByAppendingPathComponent:filenames[index]] : nil;
            NSMutableDictionary *record;
            if (catalog) {
                id named = [catalog iconImageWithName:@"ChronoFlow" scaleFactor:1 deviceIdiom:1
                    deviceSubtype:0 displayGamut:1 layoutDirection:0 sizeClassHorizontal:0
                    sizeClassVertical:0 desiredSize:CGSizeMake(1024, 1024) appearanceName:appearance];
                if (![named respondsToSelector:@selector(_rendition)]) fail(@"Missing stored icon rendition");
                id rendition = [named _rendition];
                if (![NSStringFromClass([named class]) isEqualToString:@"CUINamedMultisizeImage"] ||
                    ![NSStringFromClass([rendition class]) isEqualToString:@"_CUIThemePixelRendition"] ||
                    ![rendition respondsToSelector:@selector(unslicedImage)])
                    fail(@"CoreUI did not select a stored multisize pixel rendition; refusing a rendered stack");
                record = [fingerprint([rendition unslicedImage], exportPath) mutableCopy];
                record[@"rendition"] = [rendition name];
                record[@"class"] = NSStringFromClass([rendition class]);
            } else {
                NSURL *url = [NSURL fileURLWithPath:[path stringByAppendingPathComponent:filenames[index]]];
                CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
                if (!source) fail([@"Could not open " stringByAppendingString:url.path]);
                CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
                record = [fingerprint(image, exportPath) mutableCopy];
                CGImageRelease(image);
                CFRelease(source);
            }
            result[appearance] = record;
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted
            | NSJSONWritingSortedKeys error:nil];
        if (!json) fail(@"Could not encode fingerprints");
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
    }
    return 0;
}
