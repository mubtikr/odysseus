//
//  OdysseusComputerUseModels+AppKit.swift
//  Odysseus
//
//  Live-process conveniences on the OCComputerUseCore data contracts. These
//  query NSRunningApplication, so they stay in the app rather than the
//  Foundation-only models package.
//

import AppKit
import OCComputerUseCore

extension OdysseusComputerUseWindowInfo {
    var bundleIdentifier: String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}

extension OdysseusBackgroundComputerUseWindowCapture {
    var appName: String {
        let localizedName = NSRunningApplication(processIdentifier: pid)?.localizedName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return localizedName?.isEmpty == false ? localizedName ?? bundleID : bundleID
    }
}
