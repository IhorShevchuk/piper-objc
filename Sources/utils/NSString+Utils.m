//
//  NSString+Utils.m
//
//
//  Created by Ihor Shevchuk on 16.02.2024.
//

#import "NSString+Utils.h"
#import <NaturalLanguage/NaturalLanguage.h>

@implementation NSString (utils)
- (NSArray<NSString *> *)sentences
{
    NSMutableArray *result = [[NSMutableArray alloc] init];
    NLTagger *sentenceTagger = [[NLTagger alloc] initWithTagSchemes:@[NLTagSchemeLexicalClass]];
    sentenceTagger.string = self;

    __weak typeof(self) weakSelf = self;
    [sentenceTagger enumerateTagsInRange:NSMakeRange(0, self.length)
                                    unit:NLTokenUnitSentence
                                  scheme:NLTagSchemeLexicalClass
                                 options:NLTaggerOmitPunctuation
                              usingBlock:^(NLTag _Nullable tag, NSRange tokenRange, BOOL *_Nonnull stop) {
                                  NSString *sentence = [weakSelf substringWithRange:tokenRange];
                                  if (sentence.length > 0)
                                  {
                                      [result addObject:sentence];
                                  }
                              }];

    return [result copy];
}
@end
