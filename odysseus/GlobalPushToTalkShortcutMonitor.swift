//
//  GlobalPushToTalkShortcutMonitor.swift
//  odysseus
//
//  Captures push-to-talk keyboard shortcuts while makesomething is running in the
//  background. Uses a listen-only CGEvent tap so modifier-only shortcuts like
//  ctrl + option behave more like a real system-wide voice tool.
//

import AppKit
import Combine
import CoreGraphics
import Foundation

final class GlobalPushToTalkShortcutMonitor: ObservableObject {
    let shortcutTransitionPublisher = PassthroughSubject<BuddyPushToTalkShortcut.ShortcutTransition, Never>()
    let shiftDoubleTapPublisher = PassthroughSubject<CGPoint, Never>()
    let escapeKeyPublisher = PassthroughSubject<Void, Never>()

    @Published private(set) var isActivationShortcutEnabled = true

    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?
    private var isShiftCurrentlyPressed = false
    private var isShiftTapStandaloneCandidate = false
    private var currentShiftTapPressDate: Date?
    private var lastStandaloneShiftTapDate: Date?
    private var isEscapeCurrentlyPressed = false
    private let maximumShiftDoubleTapInterval: TimeInterval = 0.24
    private let maximumStandaloneShiftTapHoldDuration: TimeInterval = 0.18
    /// Mutated exclusively from the CGEvent tap callback, which runs on
    /// `CFRunLoopGetMain()` and therefore always executes on the main thread.
    /// Published so the overlay can hide immediately on key release without
    /// waiting for the async dictation state pipeline to catch up.
    @Published private(set) var isShortcutCurrentlyPressed = false

    deinit {
        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
        }
    }

    func start() {
        // If the event tap is already running, don't restart it.
        // Restarting resets isShortcutCurrentlyPressed, which would kill
        // the waveform overlay mid-press when the permission poller calls
        // refreshAllPermissions → start() every few seconds.
        guard globalEventTap == nil else { return }

        let monitoredEventTypes: [CGEventType] = [.flagsChanged, .keyDown, .keyUp]
        let eventMask = monitoredEventTypes.reduce(CGEventMask(0)) { currentMask, eventType in
            currentMask | (CGEventMask(1) << eventType.rawValue)
        }

        let eventTapCallback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let globalPushToTalkShortcutMonitor = Unmanaged<GlobalPushToTalkShortcutMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            return globalPushToTalkShortcutMonitor.handleGlobalEventTap(
                eventType: eventType,
                event: event
            )
        }

        guard let globalEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("⚠️ Global push-to-talk: couldn't create CGEvent tap")
            return
        }

        guard let globalEventTapRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            globalEventTap,
            0
        ) else {
            CFMachPortInvalidate(globalEventTap)
            print("⚠️ Global push-to-talk: couldn't create event tap run loop source")
            return
        }

        self.globalEventTap = globalEventTap
        self.globalEventTapRunLoopSource = globalEventTapRunLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: globalEventTap, enable: true)
    }

    func stop() {
        isShortcutCurrentlyPressed = false
        resetStandaloneShiftTapState(clearPreviousTap: true)

        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
            self.globalEventTapRunLoopSource = nil
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    func setActivationShortcutEnabled(_ enabled: Bool) {
        guard isActivationShortcutEnabled != enabled else { return }

        isActivationShortcutEnabled = enabled
        if !enabled && isShortcutCurrentlyPressed {
            isShortcutCurrentlyPressed = false
            publishShortcutTransition(.released)
        }
    }

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let globalEventTap {
                CGEvent.tapEnable(tap: globalEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        handleEscapeKeyIfNeeded(eventType: eventType, keyCode: eventKeyCode)

        guard isActivationShortcutEnabled else {
            handleStandaloneShiftTapIfNeeded(eventType: eventType, event: event)
            return Unmanaged.passUnretained(event)
        }

        let shortcutTransition = BuddyPushToTalkShortcut.shortcutTransition(
            for: eventType,
            keyCode: eventKeyCode,
            modifierFlagsRawValue: event.flags.rawValue,
            wasShortcutPreviouslyPressed: isShortcutCurrentlyPressed
        )

        switch shortcutTransition {
        case .none:
            handleStandaloneShiftTapIfNeeded(eventType: eventType, event: event)
        case .pressed:
            isShortcutCurrentlyPressed = true
            publishShortcutTransition(.pressed)
        case .released:
            isShortcutCurrentlyPressed = false
            publishShortcutTransition(.released)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleEscapeKeyIfNeeded(eventType: CGEventType, keyCode: UInt16) {
        let escapeKeyCode: UInt16 = 53
        guard keyCode == escapeKeyCode else { return }

        switch eventType {
        case .keyDown where !isEscapeCurrentlyPressed:
            isEscapeCurrentlyPressed = true
            publishEscapeKeyPress()
        case .keyUp:
            isEscapeCurrentlyPressed = false
        default:
            break
        }
    }

    private func publishShortcutTransition(_ transition: BuddyPushToTalkShortcut.ShortcutTransition) {
        DispatchQueue.main.async { [shortcutTransitionPublisher] in
            shortcutTransitionPublisher.send(transition)
        }
    }

    private func publishShiftDoubleTap(at point: CGPoint) {
        DispatchQueue.main.async { [shiftDoubleTapPublisher] in
            shiftDoubleTapPublisher.send(point)
        }
    }

    private func publishEscapeKeyPress() {
        DispatchQueue.main.async { [escapeKeyPublisher] in
            escapeKeyPublisher.send(())
        }
    }

    private func handleStandaloneShiftTapIfNeeded(eventType: CGEventType, event: CGEvent) {
        if eventType == .keyDown && isShiftCurrentlyPressed {
            // Shift was used as a real typing modifier, not as the standalone
            // double-tap shortcut. Without this guard, typing two capital
            // letters or symbols quickly can open the Odysseus panel.
            resetStandaloneShiftTapState(clearPreviousTap: true)
            return
        }

        guard eventType == .flagsChanged else { return }

        let flags = event.flags
        let isShiftDown = flags.contains(.maskShift)
        let isShiftOnly = isShiftDown
            && !flags.contains(.maskAlternate)
            && !flags.contains(.maskControl)
            && !flags.contains(.maskCommand)

        if isShiftOnly && !isShiftCurrentlyPressed {
            isShiftCurrentlyPressed = true
            isShiftTapStandaloneCandidate = true
            currentShiftTapPressDate = Date()
            return
        }

        if isShiftCurrentlyPressed && !isShiftDown {
            defer {
                isShiftCurrentlyPressed = false
                isShiftTapStandaloneCandidate = false
                currentShiftTapPressDate = nil
            }

            guard isShiftTapStandaloneCandidate else { return }

            let now = Date()
            guard let currentShiftTapPressDate,
                  now.timeIntervalSince(currentShiftTapPressDate) <= maximumStandaloneShiftTapHoldDuration
            else {
                lastStandaloneShiftTapDate = nil
                return
            }

            if let lastStandaloneShiftTapDate,
               now.timeIntervalSince(lastStandaloneShiftTapDate) <= maximumShiftDoubleTapInterval {
                self.lastStandaloneShiftTapDate = nil
                publishShiftDoubleTap(at: NSEvent.mouseLocation)
            } else {
                lastStandaloneShiftTapDate = now
            }
            return
        }

        if isShiftCurrentlyPressed && !isShiftOnly {
            resetStandaloneShiftTapState(clearPreviousTap: true)
        }

        isShiftCurrentlyPressed = isShiftDown
    }

    private func resetStandaloneShiftTapState(clearPreviousTap: Bool) {
        isShiftCurrentlyPressed = false
        isShiftTapStandaloneCandidate = false
        currentShiftTapPressDate = nil
        if clearPreviousTap {
            lastStandaloneShiftTapDate = nil
        }
    }
}
