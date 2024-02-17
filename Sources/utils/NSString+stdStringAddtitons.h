//
//  NSString+stdStringAddtitons.h
//
//
//  Created by Ihor Shevchuk on 16.02.2024.
//

#ifndef NSString_stdStringAddtitons_h
#define NSString_stdStringAddtitons_h

#import <Foundation/Foundation.h>
#include <string>

NSString *_Nullable NSSringFromString(const std::string &string);
std::string StringFromNSString(NSString * _Nullable nsString);

#endif /* NSString_stdStringAddtitons_h */
