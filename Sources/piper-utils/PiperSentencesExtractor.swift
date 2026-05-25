//
//  PiperSentencesExtractor.swift
//  piper-objc
//
//  Created by Ihor Shevchuk on 2026-05-18.
//

import Foundation
import NaturalLanguage

public final class PiperSentencesExtractor: NSObject {
    
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
    @objc public static func extract(from text: String) -> [String] {
        let cleaned = normalize(text)
        guard !cleaned.isEmpty else { return [] }
        
        let language = detectLanguage(for: cleaned)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = cleaned
        
        if let language {
            tokenizer.setLanguage(language)
        }
        
        var rawSentences: [String] = []
        tokenizer.enumerateTokens(in: cleaned.startIndex..<cleaned.endIndex) { range, _ in
            let sentence = cleaned[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                rawSentences.append(sentence)
            }
            return true
        }
        
        if rawSentences.isEmpty {
            rawSentences = [cleaned]
        }
        
        var finalChunks: [String] = []
        for sentence in rawSentences {
            let chunks = processSentence(sentence, recursionDepth: 0)
            finalChunks.append(contentsOf: chunks)
        }
        
        return finalChunks
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
        
        // Count words efficiently
        var wordCount = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in
            wordCount += 1
        }
        
        return wordCount <= Constants.maxWordsPerChunk
    }
    
    private static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
    }
    
    private static func detectLanguage(for text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }
}

// MARK: - CharacterSet Extension
private extension CharacterSet {
    func containsUnicodeScalars(of character: Character) -> Bool {
        return character.unicodeScalars.allSatisfy(contains)
    }
}
