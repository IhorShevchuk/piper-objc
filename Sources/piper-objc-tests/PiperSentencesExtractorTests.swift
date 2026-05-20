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
        if result.count == 3 {
            #expect(result[0] == "Hello world.")
            #expect(result[1] == "Привіт світе.")
            #expect(result[2] == "こんにちは。")
        }
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
        #expect(result.first == "Hello 👋 world 🌍.")
        #expect(result.last == "This is awesome 🚀!")
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
        if result.count == 3 {
            #expect(result[0] == "First line.")
            #expect(result[1] == "Second line.")
            #expect(result[2] == "Third line.")
        }
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
    
    // MARK: - Sentence Order and Edge Case Ordering

    @Test
    func preservesOrderWithMultiplePunctuationsAndSplits() {
        let text = "First sentence, with a comma, and more; second sentence: with colons, then — a dash! Finally? An end."
        let result = PiperSentencesExtractor.extract(from: text)
        // We expect the output to preserve order, even if splits happen at various punctuation.
        #expect(result.first?.hasPrefix("First sentence") == true)
        #expect(result.last?.hasPrefix("An end") == true)
        // Each chunk must come in left-to-right order from the original text.
        let joined = result.joined(separator: " ")
        #expect(joined.contains("First sentence"))
        #expect(joined.contains("second sentence"))
        #expect(joined.contains("Finally"))
        #expect(joined.range(of: "First sentence")!.lowerBound < joined.range(of: "second sentence")!.lowerBound)
        #expect(joined.range(of: "second sentence")!.lowerBound < joined.range(of: "Finally")!.lowerBound)
    }

    @Test
    func preservesOrderWithSoftSplitAtMidpoint() {
        let text = "Alpha, Beta, Gamma, Delta, Epsilon, Zeta, Eta, Theta, Iota, Kappa, Lambda, Mu, Nu, Xi, Omicron, Pi, Rho, Sigma, Tau, Upsilon, Phi, Chi, Psi, Omega."
        let result = PiperSentencesExtractor.extract(from: text)
        // The first chunk should start with Alpha, the last should end with Omega.
        #expect(result.first?.contains("Alpha") == true)
        #expect(result.last?.contains("Omega.") == true)
        // All chunks should be in original appearance order
        let allJoined = result.joined(separator: " ")
        #expect(allJoined.contains("Alpha"))
        #expect(allJoined.contains("Omega"))
        #expect(allJoined.range(of: "Alpha")!.lowerBound < allJoined.range(of: "Omega")!.lowerBound)
    }

    @Test
    func preservesOrderWithEmojisAndUnicode() {
        let text = "😀 Alpha βeta, 🚀 Gamma — Delta 🎉. 🐍 Python is fun! 🌍"
        let result = PiperSentencesExtractor.extract(from: text)
        #expect(result.count >= 2)
        // Check that emojis and Unicode tokens remain in order
        let resultString = result.joined(separator: " ")
        #expect(resultString.contains("😀 Alpha βeta"))
        #expect(resultString.contains("🚀 Gamma"))
        #expect(resultString.contains("Delta 🎉."))
        #expect(resultString.range(of: "😀")!.lowerBound < resultString.range(of: "🚀")!.lowerBound)
        #expect(resultString.range(of: "🚀")!.lowerBound < resultString.range(of: "🎉")!.lowerBound)
        #expect(resultString.range(of: "🐍")!.lowerBound < resultString.range(of: "🌍")!.lowerBound)
    }

    @Test
    func orderPreservedWithWordLimitChunking() {
        let text = (1...50).map { "word\($0)" }.joined(separator: " ")
        let result = PiperSentencesExtractor.extract(from: text)
        // Must split by word limit, but order should be preserved.
        let reconstructed = result.joined(separator: " ")
        let expected = (1...50).map { "word\($0)" }.joined(separator: " ")
        #expect(reconstructed == expected)
    }
    
    // MARK: - Right-to-Left (RTL) and Mixed Directionality Tests

    @Test
    func handlesBasicArabicSentences() {
        let text = "مرحبا بالعالم. كيف حالك؟ هذا اختبار!"
        let result = PiperSentencesExtractor.extract(from: text)
        #expect(result.count == 3)
        #expect(result[0] == "مرحبا بالعالم.")
        #expect(result[1] == "كيف حالك؟")
        #expect(result[2] == "هذا اختبار!")
    }

    @Test
    func handlesBasicHebrewSentences() {
        let text = "שלום עולם. מה שלומך? זה מבחן."
        let result = PiperSentencesExtractor.extract(from: text)
        #expect(result.count == 3)
        #expect(result[0] == "שלום עולם.")
        #expect(result[1] == "מה שלומך?")
        #expect(result[2] == "זה מבחן.")
    }

    @Test
    func handlesMixedArabicAndEnglish() {
        let text = "مرحبا. Hello. كيف الحال؟ How are you?"
        let result = PiperSentencesExtractor.extract(from: text)
        #expect(result.count == 4)
        #expect(result[0] == "مرحبا.")
        #expect(result[1] == "Hello.")
        #expect(result[2] == "كيف الحال؟")
        #expect(result[3] == "How are you?")
    }

    @Test
    func handlesRTLEmojisAndLTR() {
        let text = "😊 שלום עולם! Hello world! 🌍"
        let result = PiperSentencesExtractor.extract(from: text)
        #expect(result.count == 3)
        #expect(result[0].contains("שלום עולם"))
        #expect(result[1].contains("Hello world"))
        #expect(result[0].contains("😊") || result[1].contains("🌍"))
    }
}
