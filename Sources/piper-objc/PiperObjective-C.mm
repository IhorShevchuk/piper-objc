//
//  piper.m
//
//
//  Created by Ihor Shevchuk on 22.11.2023.
//

#import "PiperObjective-C.h"

#import <espeak-ng/bundle.h>

#include <queue>
#include <shared_mutex>
#include <piper.h>

#include <iostream>
#include <fstream>

#import "PiperSSMLParser.h"
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

typedef void (^PiperAudioChunkReady)(piper_audio_chunk audioChunk);

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

static piper_synthesize_options get_piper_synthesize_options(PiperFragment *fragment, piper_synthesizer *synthesizer)
{
    piper_synthesize_options options = piper_default_synthesize_options(synthesizer);
    options.length_scale = fragment.lengthScale;
    return options;
}

@interface Piper ()
@property (atomic, assign) PiperStatus status;
@end

@interface Piper ()
{
    piper_synthesizer *synthesizer;
    NSOperationQueue *_operationQueue;
    PiperSSMLParser *_ssmlParser;
}

@end

@implementation Piper

+ (NSString *)ensureEspeakLibDataInstalled
{
    NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSError *error = nil;
    [EspeakLib ensureBundleInstalledInRoot:[NSURL fileURLWithPath:documentsPath] error:&error];
    if (error)
    {
        NSLog(@"Error during copying Espeak files: %@", error);
    }
    return documentsPath;
}

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                             andConfigPath:(NSString *)modelConfigPath
{
    NSString *espeakNGData = [Piper ensureEspeakLibDataInstalled];
    return [self initWithModelPath:modelPath
                        configPath:modelConfigPath
                      espeakNGData:espeakNGData];
}

- (nullable instancetype)initWithModelPath:(NSString *)model
                                configPath:(NSString *)modelConfig
                              espeakNGData:(NSString *)espeakNGData
{
    self = [super init];
    if (self)
    {
        NSString *espeakNGDataInternal = espeakNGData;
        if ([espeakNGDataInternal length] == 0)
        {
            espeakNGDataInternal = [Piper ensureEspeakLibDataInstalled];
        }
        synthesizer = piper_create(
                                   StringFromNSString(model).c_str(),
                                   StringFromNSString(modelConfig).c_str(),
                                   StringFromNSString(espeakNGDataInternal).c_str()
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
    [self addClearBeforeStartingOperation];
    
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        [weakSelf doSynthesize:text
                       options:piper_default_synthesize_options(synthesizer)
                  onChunkReady:^(piper_audio_chunk chunk) {
            if (weakSelf == nil) {
                return;
            }
            Piper *strongSelf = weakSelf;
            [strongSelf.delegate piperDidReceiveSamples:chunk.samples
                                               withSize:chunk.num_samples];
        }];
    }];
    
    [self addMarkAsCompleteOperation:nil];
}

- (void)synthesizeSSML:(NSString *)ssml
{
    [self addClearBeforeStartingOperation];
    __weak Piper *weakSelf = self;
    
    [self.operationQueue addOperationWithBlock:^{
        Piper *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        NSArray<PiperFragment *> *fragments = [[strongSelf ssmlParser] parse:ssml];
        for (PiperFragment *fragment in fragments) {
            [strongSelf doSynthesize:fragment.text
                             options:get_piper_synthesize_options(fragment, synthesizer)
                        onChunkReady:^(piper_audio_chunk chunk) {
                if (weakSelf == nil) {
                    return;
                }
                Piper *strongSelf = weakSelf;
                [strongSelf.delegate piperDidReceiveSamples:chunk.samples
                                                   withSize:chunk.num_samples];
            }];
        }
    }];
    
    [self addMarkAsCompleteOperation:nil];
}

- (void)synthesize:(NSString *)text
      toFileAtPath:(NSString *)path
        completion:(dispatch_block_t)completion
{
    [self addClearBeforeStartingOperation];
    
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        std::ofstream file;
        [weakSelf doSynthesize:text
                  toFileAtPath:path
                          file:file
                       options:piper_default_synthesize_options(synthesizer)];
        file.close();
    }];
    
    [self addMarkAsCompleteOperation:completion];
}

- (void)synthesizeSSML:(NSString *)ssml
          toFileAtPath:(NSString *)path
            completion:(dispatch_block_t)completion
{
    [self addClearBeforeStartingOperation];
    
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        Piper *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        std::ofstream file;
        
        NSArray<PiperFragment *> *fragments = [[strongSelf ssmlParser] parse:ssml];
        
        for (PiperFragment *fragment in fragments) {
            [strongSelf doSynthesize:fragment.text
                        toFileAtPath:path
                                file:file
                             options:get_piper_synthesize_options(fragment, synthesizer)];
        }
        file.close();
    }];
    
    [self addMarkAsCompleteOperation:completion];
}

- (void)cancel
{
    [self.operationQueue cancelAllOperations];
    self.status = PiperStatusCreated;
}

- (BOOL)completed
{
    return self.status == PiperStatusCompleted;
}

- (BOOL)readyToRead
{
    return (self.status == PiperStatusRendering || [self completed]);
}

#pragma mark - Private

- (NSOperationQueue *)operationQueue
{
    if (_operationQueue)
    {
        return _operationQueue;
    }
    @synchronized(self)
    {
        _operationQueue = [[NSOperationQueue alloc] init];
        _operationQueue.name = [NSString stringWithFormat:@"%@Queue", NSStringFromClass([self class])];
        _operationQueue.maxConcurrentOperationCount = 1;
        _operationQueue.qualityOfService = NSQualityOfServiceUserInteractive;
        
        return _operationQueue;
    }
}

- (void)doSynthesize:(NSString *)text
             options:(piper_synthesize_options)options
        onChunkReady:(PiperAudioChunkReady)audioChunkReady
{
    piper_synthesize_start(synthesizer,
                           StringFromNSString(text).c_str(),
                           &options /* NULL for defaults */);
    
    __block NSUInteger sentencePosition = 0;
    __block NSUInteger offset = 0;
    const int kEndOfSentencePhonemPosition = 4;
    piper_audio_chunk chunk;
    while (piper_synthesize_next(synthesizer, &chunk) != PIPER_DONE) {
        const size_t size = chunk.num_samples;
        if (size == 0) {
            break;
        }
        if (audioChunkReady) {
            audioChunkReady(chunk);
        }
    }
}

- (void)doSynthesize:(NSString *)text
        toFileAtPath:(NSString *)path
                file:(std::ofstream &)file
             options:(piper_synthesize_options)options
{
    std::ofstream::openmode mode = std::ofstream::out | std::ofstream::binary;
    __block bool is_header_writen = false;
    
    [self doSynthesize:text
               options:options
          onChunkReady:^(piper_audio_chunk chunk) {
        if (!is_header_writen && !file.is_open()) {
            file.open(StringFromNSString(path).c_str(), mode);
            write_wav_stream_header(file, chunk.sample_rate);
            is_header_writen = true;
        }
        file.write(reinterpret_cast<const char *>(chunk.samples),
                   chunk.num_samples * sizeof(float));
    }];
}

- (void)doSynthesize:(NSString *)text
             options:(piper_synthesize_options)options
{
    __weak Piper *weakSelf = self;
    [self doSynthesize:text
               options:options
          onChunkReady:^(piper_audio_chunk chunk) {
        if (weakSelf == nil) {
            return;
        }
        Piper *strongSelf = weakSelf;
        [strongSelf.delegate piperDidReceiveSamples:chunk.samples
                                           withSize:chunk.num_samples];
    }];
}

- (void)addClearBeforeStartingOperation
{
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        weakSelf.status = PiperStatusRendering;
    }];
}

- (void)addMarkAsCompleteOperation:(dispatch_block_t)completion
{
    __weak Piper *weakSelf = self;
    [self.operationQueue addOperationWithBlock:^{
        weakSelf.status = PiperStatusCompleted;
        if (completion) {
            completion();
        }
    }];
}

- (PiperSSMLParser *)ssmlParser
{
    if (_ssmlParser != nil) {
        return _ssmlParser;
    }
    @synchronized(self)
    {
        _ssmlParser = [PiperSSMLParser new];
        return _ssmlParser;
    }
}
@end
