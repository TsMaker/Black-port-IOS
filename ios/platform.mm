#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

#include <cstdint>
#include <filesystem>
#include <vector>

std::filesystem::path IosDocumentsDirectory() {
    @autoreleasepool {
        NSArray<NSString*>* paths =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count == 0) return std::filesystem::temp_directory_path();
        return std::filesystem::path(paths.firstObject.UTF8String);
    }
}


bool IosLoadPng(const char* path, std::vector<uint8_t>& rgba, uint32_t& width, uint32_t& height) {
    if (!path || !*path) return false;
    @autoreleasepool {
        NSString* filePath = [NSString stringWithUTF8String:path];
        if (!filePath) return false;
        NSURL* fileURL = [NSURL fileURLWithPath:filePath];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)fileURL, nullptr);
        if (!source) return false;
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
        CFRelease(source);
        if (!image) return false;

        const size_t w = CGImageGetWidth(image);
        const size_t h = CGImageGetHeight(image);
        if (w == 0 || h == 0 || w > UINT32_MAX || h > UINT32_MAX || w > SIZE_MAX / 4 / h) {
            CGImageRelease(image);
            return false;
        }

        rgba.resize(w * h * 4);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (!colorSpace) {
            CGImageRelease(image);
            rgba.clear();
            return false;
        }
        CGContextRef context = CGBitmapContextCreate(
            rgba.data(), w, h, 8, w * 4, colorSpace,
            kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(colorSpace);
        if (!context) {
            CGImageRelease(image);
            rgba.clear();
            return false;
        }
        CGContextDrawImage(context, CGRectMake(0, 0, w, h), image);
        CGContextRelease(context);
        CGImageRelease(image);
        width = static_cast<uint32_t>(w);
        height = static_cast<uint32_t>(h);
        return true;
    }
}
