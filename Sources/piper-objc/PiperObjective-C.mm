//
//  piper.m
//
//
//  Created by Ihor Shevchuk on 22.11.2023.
//

#import "PiperObjective-C.h"

#include <queue>
#include <piper.h>

#include <iostream>
#include <fstream>

#import "NSString+Utils.h"
#import "NSString+stdStringAddtitons.h"

typedef enum PiperStatus : NSInteger
{
    PiperStatusCreated,
    PiperStatusRendering,
    PiperStatusCompleted,
    PiperStatusError,
    PiperStatusCanceled
} PiperStatus;

template<typename T> void write_number(T num, std::ostream& stream)
{
  stream.write(reinterpret_cast<char*>(&num),sizeof(num));
}

static void write_wav_stream_header(std::ostream& stream, int sample_rate) {
    const std::size_t unspec_count = 0x7ffff000;

    // ChunkID
    stream.write("RIFF", 4);
    // ChunkSize = 36 + Subchunk2Size
    write_number<uint32_t>(unspec_count + 36, stream);
    // Format
    stream.write("WAVE", 4);

    // Subchunk1ID
    stream.write("fmt ", 4);
    // Subchunk1Size = 16 for PCM/IEEE_FLOAT
    write_number<uint32_t>(16, stream);
    // AudioFormat = 3 (IEEE float)
    write_number<uint16_t>(3, stream);
    // NumChannels = 1 (mono)
    write_number<uint16_t>(1, stream);
    // SampleRate
    write_number<uint32_t>(sample_rate, stream);
    // ByteRate = SampleRate * NumChannels * BitsPerSample/8
    write_number<uint32_t>(sample_rate * 4, stream);
    // BlockAlign = NumChannels * BitsPerSample/8
    write_number<uint16_t>(4, stream);
    // BitsPerSample = 32
    write_number<uint16_t>(32, stream);

    // Subchunk2ID
    stream.write("data", 4);
    // Subchunk2Size = NumSamples * NumChannels * BitsPerSample/8
    write_number<uint32_t>(unspec_count, stream);
}

@interface Piper ()
@property (atomic, assign) PiperStatus status;
@end

@interface Piper ()
{
    piper_synthesizer *synthesizer;

    NSOperationQueue *_operationQueue;
    std::queue<int16_t> _levelsQueue;
}

@end

@implementation Piper

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                             andConfigPath:(NSString *)modelConfigPath
{
    return [self initWithModelPath:modelPath
                        configPath:modelConfigPath
                      espeakNGData:[[NSBundle mainBundle] pathForResource:@"espeak-ng-data" ofType:@""]];
}

- (nullable instancetype)initWithModelPath:(NSString *)model
                                configPath:(NSString *)modelConfig
                              espeakNGData:(NSString *)espeakNGData
{
    self = [super init];
    if (self)
    {
        synthesizer = piper_create(
                                   StringFromNSString(model).c_str(),
                                   StringFromNSString(modelConfig).c_str(),
                                   StringFromNSString(espeakNGData).c_str()
                                   );
        if (synthesizer == nullptr) {
            return nil;
        }
        self.status = PiperStatusCreated;
    }
    return self;
}

- (void)dealloc
{
    [self cancel];
    piper_free(synthesizer);
}

- (void)synthesize:(NSString *)text
{
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        [weakSelf clearQueue];
        weakSelf.status = PiperStatusRendering;
    }];

    NSArray *sentences = [text sentences];
    for (NSString *sentence in sentences)
    {
        [self.operationQueue addOperationWithBlock:^{
            [weakSelf doSynthesize:text];
        }];
    }

    [self.operationQueue addOperationWithBlock:^{
        weakSelf.status = PiperStatusCompleted;
    }];
}

- (void)synthesize:(NSString *)text
      toFileAtPath:(NSString *)path
        completion:(dispatch_block_t)completion
{
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        [weakSelf clearQueue];
        weakSelf.status = PiperStatusRendering;
    }];

    [self.operationQueue addOperationWithBlock:^{
        [weakSelf doSynthesize:text
                  toFileAtPath:path];
    }];


    [self.operationQueue addOperationWithBlock:^{
        weakSelf.status = PiperStatusCompleted;
        if (completion)
        {
            completion();
        }
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

- (NSArray<NSNumber *> *__nullable)popSamplesWithMaxLength:(NSUInteger)length
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
    piper_synthesize_options options = piper_default_synthesize_options(synthesizer);
    piper_synthesize_start(synthesizer,
                           StringFromNSString(text).c_str(),
                           &options /* NULL for defaults */);
    
    piper_audio_chunk chunk;
    while (piper_synthesize_next(synthesizer, &chunk) != PIPER_DONE) {
        const size_t size = chunk.num_samples;
        if (size == 0) {
            break;
        }
        
        for (size_t i = 0; i < size; ++i) {
            _levelsQueue.push(static_cast<int16_t>(static_cast<unsigned char>(chunk.samples[i])));
        }
    }
}

- (void)doSynthesize:(NSString *)text
        toFileAtPath:(NSString *)path
{
    @synchronized (self)
    {
        std::ofstream::openmode mode= std::ofstream::out | std::ofstream::binary;
        std::ofstream file;
        piper_synthesize_options options = piper_default_synthesize_options(synthesizer);
        piper_synthesize_start(synthesizer,
                               StringFromNSString(text).c_str(),
                               &options /* NULL for defaults */);
        bool is_header_writen = false;
        piper_audio_chunk chunk;
        while (piper_synthesize_next(synthesizer, &chunk) != PIPER_DONE) {
            if (!is_header_writen) {
                file.open(StringFromNSString(path).c_str(), mode);
                write_wav_stream_header(file, chunk.sample_rate);
                is_header_writen = true;
            }
            file.write(reinterpret_cast<const char *>(chunk.samples),
                       chunk.num_samples * sizeof(float));
        }
        file.close();
    }
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
