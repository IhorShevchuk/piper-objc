//
//  PiperSSMLParser.h
//  piper-objc
//
//  Created by Ihor Shevchuk on 9/28/25.
//

#import <Foundation/Foundation.h>

#import "PiperFragment.h"

NS_ASSUME_NONNULL_BEGIN

@interface PiperSSMLParser : NSObject

- (NSArray<PiperFragment *> *)parse:(NSString *)ssml;

@end

NS_ASSUME_NONNULL_END
