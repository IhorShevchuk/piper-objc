//
//  String+TemporaryFiles.swift
//
//
//  Created by Ihor Shevchuk on 27.03.2024.
//

import Foundation

extension String {
    private static let tempFolderName = "piper"
    static var temporaryFolderPath: String {
        return NSTemporaryDirectory().appending("\(tempFolderName)")
    }

    static func temporaryPath(extesnion: String) -> String {
        let uuid = UUID().uuidString
        return temporaryFolderPath.appending("/\(uuid).\(extesnion)")
    }
}
