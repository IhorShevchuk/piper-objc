//
//  NSString+stdStringAddtitons.m
//  
//
//  Created by Ihor Shevchuk on 16.02.2024.
//

#import "NSString+stdStringAddtitons.h"

NSString *_Nullable NSSringFromString(const std::string &string)
{
    const char *cString = string.c_str();
    if (cString == NULL)
    {
        return @"";
    }
    return [NSString stringWithUTF8String:cString];
}


std::string StringFromNSString(NSString * _Nullable nsString)
{
    if (nsString == nil)
    {
        return std::string();
    }

    const char *utfString = nsString.UTF8String;
    if (utfString == NULL)
    {
        return std::string();
    }

    return utfString;
}

