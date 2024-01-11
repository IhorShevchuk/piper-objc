//
//  Piper.m
//
//
//  Created by Ihor Shevchuk on 22.11.2023.
//

#include <queue>

#import <piper.h>

#include "piper.hpp"

typedef enum PiperStatus : NSInteger
{
    PiperStatusCreated,
    PiperStatusRendering,
    PiperStatusCompleted,
    PiperStatusError,
    PiperStatusCanceled
} PiperStatus;

@interface Piper ()
@property (atomic, assign) PiperStatus status;
@end

@interface Piper ()
{
    piper::PiperConfig config;
    piper::Voice voice;

    NSOperationQueue *_operationQueue;
    std::queue<int16_t> _levelsQueue;
}

@end

@implementation Piper

- (instancetype)initWithModelPath:(NSString *)model
                    andConfigPath:(NSString *)modelConfig
{
    self = [super init];
    if (self)
    {
        std::optional<piper::SpeakerId> speakerId;
        loadVoice(config,
                  /// TODO: add NSString <-> std::string converters
                  model.UTF8String,
                  modelConfig.UTF8String,
                  voice,
                  speakerId,
                  false);

        voice.synthesisConfig.lengthScale = 0.2;
        voice.synthesisConfig.sentenceSilenceSeconds = 2;
        if (config.useESpeak)
        {
            config.eSpeakDataPath = [[NSBundle mainBundle] pathForResource:@"espeak-ng-data" ofType:@""].UTF8String;
        }

        piper::initialize(config);
        self.status = PiperStatusCreated;
    }
    return self;
}

- (void)dealloc
{
    piper::terminate(config);
}

- (void)synthesize:(NSString *)text
{
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        [weakSelf doSynthesize:text];
    }];
}

- (void)cancel
{
    [self.operationQueue cancelAllOperations];
    if (self.status == PiperStatusRendering)
    {
        @synchronized(self)
        {
            [self clearQueue];
        }
    }
    self.status = PiperStatusCreated;
}

- (NSArray<NSNumber *> * __nullable)popSamplesWithMaxLength:(NSUInteger)length
{
    if (![self hasSamplesLeft])
    {
        return nil;
    }

    NSUInteger lengthIntenal = MIN(length, [self length]);
    NSMutableArray *result = [[NSMutableArray alloc] initWithCapacity:lengthIntenal];

    @synchronized(self)
    {
        for (int index = 0; index < lengthIntenal; ++index)
        {
            if (_levelsQueue.empty())
            {
                break;
            }
            const auto element = _levelsQueue.front();
            _levelsQueue.pop();
            [result addObject:[NSNumber numberWithShort:element]];
        }
        return [result copy];
    }
}

- (BOOL)hasSamplesLeft
{
    return self.length > 0;
}

- (BOOL)completed
{
    return self.status == PiperStatusCompleted;
}

- (BOOL)readyToRead
{
    return (self.status == PiperStatusRendering || [self completed]) && [self hasSamplesLeft];
}

#pragma mark - Private

- (NSOperationQueue *)operationQueue
{
    @synchronized(self)
    {
        if (_operationQueue == nil)
        {
            _operationQueue = [[NSOperationQueue alloc] init];
            _operationQueue.name = [NSString stringWithFormat:@"%@Queue", NSStringFromClass([self class])];
            _operationQueue.maxConcurrentOperationCount = 1;
            _operationQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        }
        return _operationQueue;
    }
}

- (void)doSynthesize:(NSString *)text
{
    [self clearQueue];
    self.status = PiperStatusRendering;

    piper::SynthesisResult result;
    std::vector<int16_t> audioBuffer;
    bool audioReady = false;

    __weak Piper *weakSelf = self;
    auto audioCallback = [&audioBuffer, &weakSelf]() {
        @synchronized(weakSelf)
        {
            auto strongSelf = weakSelf;
            if (strongSelf == nullptr)
            {
                return;
            }

            if (strongSelf.status != PiperStatusRendering)
            {
                return;
            }

            for (const auto &level : audioBuffer)
            {
                strongSelf->_levelsQueue.push(level);
            }
        }
    };
    piper::textToAudio(config,
                       voice,
                       text.UTF8String,
                       audioBuffer,
                       result,
                       audioCallback);

    self.status = PiperStatusCompleted;
}

- (NSUInteger)length
{
    @synchronized(self)
    {
        return _levelsQueue.size();
    }
}

- (void)clearQueue
{
    @synchronized(self)
    {
        std::queue<int16_t> empty;
        std::swap(_levelsQueue, empty);
    }
}
@end
