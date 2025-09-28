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
- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                                configPath:(NSString *)modelConfigPath
                              espeakNGData:(NSString *)espeakNGData;

- (NSArray<NSNumber *> *__nullable)popSamplesWithMaxLength:(NSUInteger)length;
- (BOOL)completed;
- (BOOL)hasSamplesLeft;
- (BOOL)readyToRead;
- (void)cancel;

#pragma mark - Synthesizion

#pragma mark Text

- (void)synthesize:(NSString *)text;
- (void)synthesize:(NSString *)text
      toFileAtPath:(NSString *)path
        completion:(dispatch_block_t)completion;

#pragma mark SSML

- (void)synthesizeSSML:(NSString *)ssml;
- (void)synthesizeSSML:(NSString *)ssml
          toFileAtPath:(NSString *)path
            completion:(dispatch_block_t)completion;
@end

NS_ASSUME_NONNULL_END
