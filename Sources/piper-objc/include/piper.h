//
//  piper.h
//
//
//  Created by Ihor Shevchuk on 22.11.2023.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Piper : NSObject
- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                             andConfigPath:(NSString *)modelConfigPath;
- (void)synthesize:(NSString *)text;
- (NSArray<NSNumber *> *__nullable)popSamplesWithMaxLength:(NSUInteger)length;
- (BOOL)completed;
- (BOOL)hasSamplesLeft;
- (BOOL)readyToRead;
- (void)cancel;

- (void)synthesize:(NSString *)text
      toFileAtPath:(NSString *)path
        completion:(dispatch_block_t)completion;
@end

NS_ASSUME_NONNULL_END
