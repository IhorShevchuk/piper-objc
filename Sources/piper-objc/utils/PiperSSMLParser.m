//
//  PiperSSMLParser.m
//  piper-objc
//
//  Created by Ihor Shevchuk on 9/28/25.
//

#import "PiperSSMLParser.h"

@interface PiperSSMLParser () <NSXMLParserDelegate>

@property (nonatomic, strong) NSMutableArray<PiperFragment *> *fragments;
@property (nonatomic) float currentRate;

@end

@implementation PiperSSMLParser

- (instancetype)init {
    self = [super init];
    if (self) {
        _fragments = [NSMutableArray array];
        _currentRate = 1.0;
    }
    return self;
}

- (NSArray<PiperFragment *> *)parse:(NSString *)ssml {
    [self.fragments removeAllObjects];
    NSData *data = [ssml dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return @[];

    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = self;
    [parser parse];

    return [self.fragments copy];
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser
didStartElement:(NSString *)elementName
  namespaceURI:(nullable NSString *)namespaceURI
 qualifiedName:(nullable NSString *)qName
    attributes:(NSDictionary<NSString *, NSString *> *)attributeDict
{
    if ([elementName isEqualToString:@"prosody"]) {
        NSString *rateStr = attributeDict[@"rate"];
        if (rateStr) {
            self.currentRate = [self parseRate:rateStr];
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length > 0) {
        PiperFragment *fragment = [[PiperFragment alloc] initWithText:trimmed lengthScale:self.currentRate];
        [self.fragments addObject:fragment];
    }
}

- (void)parser:(NSXMLParser *)parser
  didEndElement:(NSString *)elementName
   namespaceURI:(nullable NSString *)namespaceURI
  qualifiedName:(nullable NSString *)qName
{
    if ([elementName isEqualToString:@"prosody"]) {
        self.currentRate = 1.0; // reset after prosody ends
    }
}

#pragma mark - Helper

- (float)parseRate:(NSString *)value {
    if ([value hasSuffix:@"%"]) {
        NSString *numStr = [value substringToIndex:value.length - 1];
        double percent = [numStr doubleValue];
        if (percent != 0) {
            return 100.0 / percent; // Piper lengthScale
        }
    }
    return 1.0;
}

@end
