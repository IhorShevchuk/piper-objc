//
//  FileManager+TemporaryFolder.swift.swift
//
//
//  Created by Ihor Shevchuk on 27.03.2024.
//

import Foundation

extension FileManager {
    func createTempFolderIfNeeded(at path: String) throws {
        if !fileExists(atPath: path) {
            try createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: false)
        }
    }

    func removeTempFolderIfNeeded(at path: String) throws {
        if !fileExists(atPath: path) {
            try removeItem(atPath: path)
        }
    }
}
