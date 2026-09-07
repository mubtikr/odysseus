//
//  OdysseusJSONFileStore.swift
//  Odysseus
//
//  The generic JSON-file persistence helpers now live in the OCFoundation
//  package. This file keeps the one product-specific member — the shared
//  "Odysseus" directory under Application Support — in the app, where the
//  product name belongs.
//

import Foundation
import OCFoundation

extension OdysseusJSONFileStore {
    /// The shared "Odysseus" directory under Application Support, with an
    /// optional relative subpath appended (e.g. ["Logs"], ["agents"]).
    nonisolated static func odysseusDirectory(fileManager: FileManager = .default, subpath: [String] = []) -> URL {
        var url = applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("Odysseus", isDirectory: true)
        for component in subpath {
            url = url.appendingPathComponent(component, isDirectory: true)
        }
        return url
    }
}
