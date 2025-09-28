//
//  PiperFragment.h
//  piper-objc
//
//  Created by Ihor Shevchuk on 9/28/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PiperFragment : NSObject

@property (nonatomic, readonly) NSString *text;
@property (nonatomic, readonly) CGFloat lengthScale;

- (instancetype)initWithText:(NSString *)text lengthScale:(CGFloat)lengthScale;

@end

NS_ASSUME_NONNULL_END
