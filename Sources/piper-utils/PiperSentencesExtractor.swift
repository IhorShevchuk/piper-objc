//  PiperSentencesExtractor.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 2026-05-18.
//

import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public final class PiperSentencesExtractor {
    
    // MARK: - Configuration
    private enum Constants {
        static let maxWordsPerChunk = 22
        static let maxCharactersPerChunk = 160
        static let maxRecursionDepth = 20
        
        /// Hard sentence boundary punctuation (always respected)
        static let sentenceEndPunctuation: CharacterSet = CharacterSet(charactersIn: ".!?")
        
        /// Soft pause punctuation (used to divide long sentences)
        static let softPausePunctuation: CharacterSet = CharacterSet(charactersIn: ",;:—–()[]{}")
    }
    
    // MARK: - Public API
    public static func extract(from text: String) -> AnySequence<String> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AnySequence([])
        }

        return AnySequence {
#if canImport(NaturalLanguage)
            let language = detectLanguage(for: text)
            let tokenizer = NLTokenizer(unit: .sentence)
            tokenizer.string = text
            if let language { tokenizer.setLanguage(language) }

            var tokenRanges: [Range<String.Index>] = []
            tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
                tokenRanges.append(range)
                return true
            }

            // If tokenizer fails, fallback to entire text
            if tokenRanges.isEmpty {
                tokenRanges.append(text.startIndex..<text.endIndex)
            }

            var tokenIterator = tokenRanges.makeIterator()
            var currentChunks: [String] = []

            return AnyIterator<String> {
                while currentChunks.isEmpty {
                    guard let nextRange = tokenIterator.next() else { return nil }
                    let rawSentence = String(text[nextRange])
                    let normalized = normalize(rawSentence)
                    if normalized.isEmpty { continue }
                    currentChunks = processSentence(normalized, recursionDepth: 0)
                }
                return currentChunks.removeFirst()
            }
#else
            // Linux / platforms without NaturalLanguage – simple sentence splitter
            let sentences = naiveSentenceSplit(text)
            var sentenceIterator = sentences.makeIterator()
            var currentChunks: [String] = []

            return AnyIterator<String> {
                while currentChunks.isEmpty {
                    guard let next = sentenceIterator.next() else { return nil }
                    let normalized = normalize(next)
                    if normalized.isEmpty { continue }
                    currentChunks = processSentence(normalized, recursionDepth: 0)
                }
                return currentChunks.removeFirst()
            }
#endif
        }
    }
    
    // MARK: - Sentence Processing (Recursive Breakdown)
    private static func processSentence(_ sentence: String, recursionDepth: Int = 0) -> [String] {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        if recursionDepth > Constants.maxRecursionDepth {
            return [trimmed]
        }
        
        // Base Case: If the text is small enough, stop splitting
        if isValidChunk(trimmed) {
            return [trimmed]
        }
        
        // Try to find a logical split point at a soft punctuation mark near the center
        if let splitIndex = findBestSoftSplitIndex(in: trimmed) {
            let leftSide = String(trimmed[..<splitIndex])
            let rightSide = String(trimmed[splitIndex...])
            
            // Recursively evaluate both halves
            return processSentence(leftSide, recursionDepth: recursionDepth + 1) + processSentence(rightSide, recursionDepth: recursionDepth + 1)
        }
        
        // Fallback: If no soft punctuation exists but it's still too long, split by middle word
        return forceSplitByMiddleWord(trimmed, recursionDepth: recursionDepth + 1)
    }
    
    // MARK: - Core Subdivision Logic
    private static func findBestSoftSplitIndex(in text: String) -> String.Index? {
        let midpoint = text.count / 2
        var bestIndex: String.Index? = nil
        var smallestDistance = Int.max
        
        var currentIndex = text.startIndex
        var characterCount = 0
        
        while currentIndex < text.endIndex {
            let character = text[currentIndex]
            
            if Constants.softPausePunctuation.containsUnicodeScalars(of: character) {
                let distance = abs(characterCount - midpoint)
                if distance < smallestDistance {
                    smallestDistance = distance
                    // Move the index past the punctuation mark so it stays attached to the left chunk
                    bestIndex = text.index(after: currentIndex)
                }
            }
            
            currentIndex = text.index(after: currentIndex)
            characterCount += 1
        }
        
        return bestIndex
    }
    
    private static func forceSplitByMiddleWord(_ text: String, recursionDepth: Int) -> [String] {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count > 1 else { return [text] }
        
        let midIndex = words.count / 2
        let leftSide = words[..<midIndex].joined(separator: " ")
        let rightSide = words[midIndex...].joined(separator: " ")
        
        return processSentence(leftSide, recursionDepth: recursionDepth) + processSentence(rightSide, recursionDepth: recursionDepth)
    }
    
    // MARK: - Validation & Helpers
    private static func isValidChunk(_ text: String) -> Bool {
        if text.count > Constants.maxCharactersPerChunk { return false }
        
#if canImport(NaturalLanguage)
        // Apple platforms – use linguistic word enumeration
        var wordCount = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in
            wordCount += 1
        }
        return wordCount <= Constants.maxWordsPerChunk
#else
        // Linux fallback – naive whitespace split (byWords unavailable in corelibs)
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.count <= Constants.maxWordsPerChunk
#endif
    }
    
    private static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
    }

#if canImport(NaturalLanguage)
    private static func detectLanguage(for text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }
#else
    /// Linux fallback – split on .!? while keeping delimiter
    private static func naiveSentenceSplit(_ text: String) -> [String] {
        var results: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if Constants.sentenceEndPunctuation.containsUnicodeScalars(of: char) {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { results.append(trimmed) }
                current = ""
            }
        }
        let leftover = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !leftover.isEmpty { results.append(leftover) }
        if results.isEmpty { results = [text] }
        return results
    }
#endif
}

// MARK: - CharacterSet Extension
private extension CharacterSet {
    func containsUnicodeScalars(of character: Character) -> Bool {
        return character.unicodeScalars.allSatisfy(contains)
    }
}
