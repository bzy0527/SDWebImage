/*
 * This file is part of the SDWebImage package.
 * (c) Olivier Poitrey <rs@dailymotion.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */

#import "SDAnimatedImage.h"
#import "NSImage+Additions.h"
#import "UIImage+WebCache.h"
#import "SDWebImageCoder.h"
#import "SDWebImageCodersManager.h"
#import "SDWebImageFrame.h"

static CGFloat SDImageScaleFromPath(NSString *string) {
    if (string.length == 0 || [string hasSuffix:@"/"]) return 1;
    NSString *name = string.stringByDeletingPathExtension;
    __block CGFloat scale = 1;
    
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"@[0-9]+\\.?[0-9]*x$" options:NSRegularExpressionAnchorsMatchLines error:nil];
    [pattern enumerateMatchesInString:name options:kNilOptions range:NSMakeRange(0, name.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        if (result.range.location >= 3) {
            scale = [string substringWithRange:NSMakeRange(result.range.location + 1, result.range.length - 2)].doubleValue;
        }
    }];
    
    return scale;
}

@interface SDAnimatedImage ()

@property (nonatomic, strong) id<SDWebImageAnimatedCoder> coder;
@property (nonatomic, assign, readwrite) SDImageFormat animatedImageFormat;
@property (atomic, copy) NSArray<SDWebImageFrame *> *preloadAnimatedImageFrames;
@property (nonatomic, assign) BOOL animatedImageFramesPreloaded;

@end

@implementation SDAnimatedImage

#pragma mark - Dealloc & Memory warning

- (void)dealloc {
#if SD_UIKIT
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    if (self.animatedImageFramesPreloaded) {
        self.preloadAnimatedImageFrames = nil;
        self.animatedImageFramesPreloaded = NO;
    }
}

#pragma mark - UIImage override method
+ (instancetype)imageWithContentsOfFile:(NSString *)path {
    return [[self alloc] initWithContentsOfFile:path];
}

+ (instancetype)imageWithData:(NSData *)data {
    return [[self alloc] initWithData:data];
}

+ (instancetype)imageWithData:(NSData *)data scale:(CGFloat)scale {
    return [[self alloc] initWithData:data scale:scale];
}

- (instancetype)initWithContentsOfFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path];
    return [self initWithData:data scale:SDImageScaleFromPath(path)];
}

- (instancetype)initWithData:(NSData *)data {
    return [self initWithData:data scale:1];
}

- (instancetype)initWithData:(NSData *)data scale:(CGFloat)scale {
    if (!data || data.length == 0) {
        return nil;
    }
    if (scale <= 0) {
        scale = 1;
    }
    data = [data copy]; // avoid mutable data
    id<SDWebImageAnimatedCoder> animatedCoder = nil;
    for (id<SDWebImageCoder>coder in [SDWebImageCodersManager sharedManager].coders) {
        if ([coder conformsToProtocol:@protocol(SDWebImageAnimatedCoder)]) {
            if ([coder canDecodeFromData:data]) {
                animatedCoder = [[[coder class] alloc] initWithAnimatedImageData:data];
                break;
            }
        }
    }
    if (!animatedCoder) {
        return nil;
    }
    UIImage *image = [animatedCoder animatedImageFrameAtIndex:0];
    if (!image) {
        return nil;
    }
#if SD_MAC
    self = [super initWithCGImage:image.CGImage size:NSZeroSize];
#else
    self = [super initWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
#endif
    if (self) {
        _coder = animatedCoder;
#if SD_MAC
        _scale = scale;
#endif
        SDImageFormat format = [NSData sd_imageFormatForImageData:data];
        _animatedImageFormat = format;
    }
    return self;
}

- (instancetype)initWithAnimatedCoder:(id<SDWebImageAnimatedCoder>)animatedCoder scale:(CGFloat)scale {
    if (!animatedCoder) {
        return nil;
    }
    if (scale <= 0) {
        scale = 1;
    }
    UIImage *image = [animatedCoder animatedImageFrameAtIndex:0];
    if (!image) {
        return nil;
    }
#if SD_MAC
    self = [super initWithCGImage:image.CGImage size:NSZeroSize];
#else
    self = [super initWithCGImage:image.CGImage scale:scale orientation:image.imageOrientation];
#endif
    if (self) {
        _coder = animatedCoder;
#if SD_MAC
        _scale = scale;
#endif
        NSData *data = [animatedCoder animatedImageData];
        SDImageFormat format = [NSData sd_imageFormatForImageData:data];
        _animatedImageFormat = format;
    }
    return self;
}

#pragma mark - Preload
- (void)preloadAllFrames {
    if (!self.animatedImageFramesPreloaded) {
        NSMutableArray<SDWebImageFrame *> *frames = [NSMutableArray arrayWithCapacity:self.animatedImageFrameCount];
        for (size_t i = 0; i < self.animatedImageFrameCount; i++) {
            UIImage *image = [self animatedImageFrameAtIndex:i];
            NSTimeInterval duration = [self animatedImageDurationAtIndex:i];
            SDWebImageFrame *frame = [SDWebImageFrame frameWithImage:image duration:duration]; // through the image should be nonnull, used as nullable for `animatedImageFrameAtIndex:`
            [frames addObject:frame];
        }
        self.preloadAnimatedImageFrames = frames;
        self.animatedImageFramesPreloaded = YES;
#if SD_UIKIT
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarning:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
    }
}

#pragma mark - NSSecureCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSNumber *scale = [aDecoder decodeObjectOfClass:[NSNumber class] forKey:NSStringFromSelector(@selector(scale))];
    NSData *animatedImageData = [aDecoder decodeObjectOfClass:[NSData class] forKey:NSStringFromSelector(@selector(animatedImageData))];
    if (animatedImageData) {
        return [self initWithData:animatedImageData scale:scale.doubleValue];
    } else {
        return [super initWithCoder:aDecoder];
    }
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    if (self.animatedImageData) {
        [aCoder encodeObject:self.animatedImageData forKey:NSStringFromSelector(@selector(animatedImageData))];
        [aCoder encodeObject:@(self.scale) forKey:NSStringFromSelector(@selector(scale))];
    } else {
        [super encodeWithCoder:aCoder];
    }
}

+ (BOOL)supportsSecureCoding {
    return YES;
}

#pragma mark - SDAnimatedImage

- (NSData *)animatedImageData {
    return [self.coder animatedImageData];
}

- (NSUInteger)animatedImageLoopCount {
    return [self.coder animatedImageLoopCount];
}

- (NSUInteger)animatedImageFrameCount {
    return [self.coder animatedImageFrameCount];
}

- (UIImage *)animatedImageFrameAtIndex:(NSUInteger)index {
    if (index >= self.animatedImageFrameCount) {
        return nil;
    }
    if (self.animatedImageFramesPreloaded) {
        SDWebImageFrame *frame = [self.preloadAnimatedImageFrames objectAtIndex:index];
        return frame.image;
    }
    return [self.coder animatedImageFrameAtIndex:index];
}

- (NSTimeInterval)animatedImageDurationAtIndex:(NSUInteger)index {
    if (index >= self.animatedImageFrameCount) {
        return 0;
    }
    if (self.animatedImageFramesPreloaded) {
        SDWebImageFrame *frame = [self.preloadAnimatedImageFrames objectAtIndex:index];
        return frame.duration;
    }
    return [self.coder animatedImageDurationAtIndex:index];
}

@end
