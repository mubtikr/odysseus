//
//  OdysseusManagedWindowController.swift
//  odysseus
//
//  Shared create/show/center/front boilerplate for Odysseus's floating
//  utility windows (log viewer, 3D viewer, and similar single-window
//  managers). Each manager still owns its own lifecycle and SwiftUI content;
//  this controller only captures the repeated NSWindow plumbing.
//

import AppKit
import SwiftUI

@MainActor
final class OdysseusManagedWindowController<Content: View> {
    struct Configuration {
        var title: String = ""
        var titleVisibility: NSWindow.TitleVisibility = .visible
        var size: NSSize
        var minSize: NSSize?
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        var cornerRadius: CGFloat = 22
        var frameAutosaveName: String?

        init(
            title: String = "",
            titleVisibility: NSWindow.TitleVisibility = .visible,
            size: NSSize,
            minSize: NSSize? = nil,
            styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            cornerRadius: CGFloat = 22,
            frameAutosaveName: String? = nil
        ) {
            self.title = title
            self.titleVisibility = titleVisibility
            self.size = size
            self.minSize = minSize
            self.styleMask = styleMask
            self.cornerRadius = cornerRadius
            self.frameAutosaveName = frameAutosaveName
        }
    }

    private(set) var window: NSWindow?
    private var hostingView: NSHostingView<Content>?
    private let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// Creates the window on first call; on later calls refreshes the hosted
    /// SwiftUI content in place. Always brings the window to the front.
    /// Pass `recenter: false` for windows that should keep their last
    /// position across repeat shows instead of snapping back to center.
    func show(
        targetScreen: NSScreen? = nil,
        recenter: Bool = true,
        makeContent: () -> Content
    ) {
        let resolvedTargetScreen = targetScreen ?? NSScreen.odysseusActiveInteractionScreen()
        if window == nil {
            createWindow(content: makeContent(), targetScreen: resolvedTargetScreen)
        } else {
            hostingView?.rootView = makeContent()
        }

        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        bringToFront(window, targetScreen: resolvedTargetScreen, recenter: recenter)
    }

    func close() {
        window?.close()
    }

    private func createWindow(content: Content, targetScreen: NSScreen?) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: configuration.size),
            styleMask: configuration.styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = configuration.title
        window.titleVisibility = configuration.titleVisibility
        if let minSize = configuration.minSize {
            window.minSize = minSize
        }
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        if let frameAutosaveName = configuration.frameAutosaveName {
            window.setFrameAutosaveName(frameAutosaveName)
        }
        OdysseusWindowLevels.applyPanelDialogLevel(to: window)
        center(window, on: targetScreen)

        let hostingView = NSHostingView(rootView: content)
        OdysseusLiquidGlassWindowSurface.install(
            hostingView: hostingView,
            in: window,
            frame: NSRect(origin: .zero, size: configuration.size),
            cornerRadius: configuration.cornerRadius,
            strength: .expanded
        )

        self.hostingView = hostingView
        self.window = window
    }

    private func bringToFront(_ window: NSWindow, targetScreen: NSScreen?, recenter: Bool) {
        OdysseusWindowLevels.applyPanelDialogLevel(to: window)
        if recenter {
            center(window, on: targetScreen)
        }
        window.deminiaturize(nil)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }

    private func center(_ window: NSWindow, on targetScreen: NSScreen?) {
        guard let targetScreen else {
            window.center()
            return
        }
        window.setFrame(
            NSScreen.centerFrame(size: window.frame.size, on: targetScreen),
            display: true,
            animate: false
        )
    }
}
