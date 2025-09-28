//
//  PiperFragment.m
//  piper-objc
//
//  Created by Ihor Shevchuk on 9/28/25.
//

#import "PiperFragment.h"

@implementation PiperFragment

- (instancetype)initWithText:(NSString *)text lengthScale:(CGFloat)lengthScale {
    self = [super init];
    if (self) {
        _text = text;
        _lengthScale = lengthScale;
    }
    return self;
}

@end
