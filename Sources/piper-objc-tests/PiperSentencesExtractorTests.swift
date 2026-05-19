//
//  PiperSentencesExtractorTests.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 2026-05-18.
//
import Testing
@testable import piper_utils
import Foundation

struct PiperSentencesExtractorTests {

    // MARK: - Basic Sentence Extraction

    @Test
    func extractsBasicSentences() {
        let text = "Hello world. This is a test! How are you?"

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count == 3)
        #expect(result[0] == "Hello world.")
        #expect(result[1] == "This is a test!")
        #expect(result[2] == "How are you?")
    }

    // MARK: - Empty Input

    @Test
    func handlesEmptyInput() {
        let result = PiperSentencesExtractor.extract(from: "")

        #expect(result.isEmpty)
    }

    @Test
    func handlesWhitespaceInput() {
        let result = PiperSentencesExtractor.extract(from: "   \n\t   ")

        #expect(result.isEmpty)
    }

    // MARK: - Comma Chunking

    @Test
    func splitsLongSentenceByComma() {
        // Enforced a sentence layout that goes past 22 words / 160 characters
        // to actively trigger our on-demand recursive comma subdivision.
        let text = """
        Yesterday, after finishing up an incredibly long day at work, I slowly walked over to the neighborhood grocery store, purchased a fresh bottle of milk, and quickly drove back to my house.
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count > 1)
        
        // Verifies chunks split at soft bounds without dropping the punctuation character
        #expect(result.contains(where: { $0.hasSuffix(",") }))
    }

    // MARK: - Word Limit Chunking

    @Test
    func splitsVeryLongChunkByWordLimit() {
        let text = """
        This is a very long sentence that should be automatically split into multiple smaller chunks because it exceeds the configured word limit for speech synthesis processing.
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count >= 2)

        for chunk in result {
            let words = chunk.split(whereSeparator: \.isWhitespace)
            #expect(words.count <= 22) // Adjusted to align with Constants.maxWordsPerChunk
        }
    }

    // MARK: - Character Limit Chunking

    @Test
    func splitsVeryLongChunkByCharacterLimit() {
        let text = String(repeating: "superlongword ", count: 30)

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count >= 2)

        for chunk in result {
            #expect(chunk.count <= 160)
        }
    }

    // MARK: - Unicode / Multilingual

    @Test
    func handlesUkrainianText() {
        let text = """
        Привіт світе. Як справи? Сьогодні гарна погода.
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count == 3)
        #expect(result[0] == "Привіт світе.")
        #expect(result[1] == "Як справи?")
        #expect(result[2] == "Сьогодні гарна погода.")
    }

    @Test
    func handlesJapaneseText() {
        let text = """
        こんにちは世界。今日は元気ですか？これはテストです。
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count >= 2)
    }

    @Test
    func handlesMixedLanguageText() {
        let text = """
        Hello world. Привіт світе. こんにちは。
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count == 3)
    }

    // MARK: - Whitespace Normalization

    @Test
    func normalizesWhitespace() {
        let text = """
        Hello     world.


        This     is     a     test.
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count == 2)
        #expect(result[0] == "Hello world.")
        #expect(result[1] == "This is a test.")
    }

    // MARK: - No Punctuation

    @Test
    func handlesTextWithoutPunctuation() {
        let text = """
        this is text without punctuation and it should still produce output
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(!result.isEmpty)
    }

    // MARK: - Emojis

    @Test
    func handlesEmojiText() {
        let text = """
        Hello 👋 world 🌍. This is awesome 🚀!
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count == 2)
    }

    // MARK: - Newlines

    @Test
    func handlesNewlines() {
        let text = """
        First line.

        Second line.

        Third line.
        """

        let result = PiperSentencesExtractor.extract(from: text)

        #expect(result.count == 3)
    }
    
    // MARK: - New Multi-Layer Split Tests

    @Test
    func forcesWordSplitWhenNoPunctuationFound() {
        // Long continuous sentence structure completely lacking punctuation marks
        let text = "This is an extremely massive run on block of words without any punctuation whatsoever that will definitely trigger the fallback middle word division routine because it passes limits"
        
        let result = PiperSentencesExtractor.extract(from: text)
        
        #expect(result.count >= 2)
        for chunk in result {
            #expect(chunk.count <= 160)
        }
    }
}
