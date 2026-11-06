#import <Foundation/Foundation.h>

#include <filesystem>

std::filesystem::path IosDocumentsDirectory() {
    @autoreleasepool {
        NSArray<NSString*>* paths =
            NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (paths.count == 0) return std::filesystem::temp_directory_path();
        return std::filesystem::path(paths.firstObject.UTF8String);
    }
}
