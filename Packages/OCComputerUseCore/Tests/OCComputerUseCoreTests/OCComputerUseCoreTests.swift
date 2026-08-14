import CoreGraphics
import Foundation
import Testing
@testable import OCComputerUseCore

struct OdysseusComputerUseTests {
    @Test func nativeComputerUseStatusSummarizesReadiness() throws {
        let permissions = OdysseusComputerUsePermissionStatus(
            accessibilityGranted: true,
            screenRecordingGranted: true,
            skyLightKeyboardPathAvailable: true
        )
        let focusedWindow = OdysseusComputerUseWindowInfo(
            id: 42, pid: 1234, owner: "Safari", name: "Odysseus Test",
            bounds: OdysseusComputerUseWindowBounds(x: 10, y: 20, width: 800, height: 600),
            zIndex: 9, isOnScreen: true, layer: 0
        )
        let status = OdysseusComputerUseStatus(
            enabled: true, permissions: permissions, runningAppCount: 4,
            visibleWindowCount: 7, focusedWindow: focusedWindow, lastErrorMessage: nil
        )
        #expect(status.isReadyForComputerUse)
        #expect(status.summary == "Enabled · AX ready · screen ready · SkyLight keyboard ready · Full Disk Access not detected · Safari")
        #expect(status.focusedTargetSummary == "Safari — Odysseus Test · pid 1234 · window 42")
    }

    @Test func nativeComputerUseStatusCallsOutDisabledMode() throws {
        let status = OdysseusComputerUseStatus(
            enabled: false,
            permissions: OdysseusComputerUsePermissionStatus(
                accessibilityGranted: true, screenRecordingGranted: true, skyLightKeyboardPathAvailable: false
            ),
            runningAppCount: 0, visibleWindowCount: 0, focusedWindow: nil, lastErrorMessage: nil
        )
        #expect(!status.isReadyForComputerUse)
        #expect(status.summary == "Disabled · enable in Odysseus settings")
    }

    @Test func visualGuidanceRectFromNegativeSizeCGRectIsStandardized() {
        // Regression for the origin/extent mismatch fixed during extraction.
        let rect = OdysseusVisualGuidanceRect(CGRect(x: 120, y: 90, width: -80, height: -60))
        #expect(rect == OdysseusVisualGuidanceRect(x: 40, y: 30, width: 80, height: 60))
    }

    @Test func nativeComputerUseWindowNotesIncludeStableAgentMetadata() throws {
        let window = OdysseusComputerUseWindowInfo(
            id: 77, pid: 2468, owner: "Xcode", name: "ContentView.swift",
            bounds: OdysseusComputerUseWindowBounds(x: 12.5, y: 40.0, width: 900.0, height: 700.0),
            zIndex: 20, isOnScreen: true, layer: 0
        )
        #expect(window.agentContextNote == "CUA Swift target window id 77, pid 2468, owner Xcode, title ContentView.swift, bounds x:12 y:40 width:900 height:700, z-index 20.")
        #expect(window.captureLabel == "CUA Swift focused window (Xcode - ContentView.swift)")
    }

    @Test func nativeComputerUseCaptureNoteExplainsDownsampleMapping() throws {
        let window = OdysseusComputerUseWindowInfo(
            id: 77, pid: 2468, owner: "Xcode", name: "ContentView.swift",
            bounds: OdysseusComputerUseWindowBounds(x: 12.5, y: 40.0, width: 1606.0, height: 1089.0),
            zIndex: 20, isOnScreen: true, layer: 0
        )
        let capture = OdysseusComputerUseWindowCapture(
            imageData: Data(), window: window,
            screenshotWidthInPixels: 1280, screenshotHeightInPixels: 867
        )
        #expect(capture.agentContextNote.contains("xScale 1.2547"))
        #expect(capture.agentContextNote.contains("yScale 1.2561"))
    }
}

struct OdysseusVisualGuidanceOverlayTests {
    @Test func rectangleNormalizesClampsAndSerializes() throws {
        let overlay = OdysseusVisualGuidanceOverlay.rectangle(
            rect: CGRect(x: 120, y: 90, width: -80, height: 60),
            accentHex: "#60A5FA", lineWidth: 200, fillOpacity: 2,
            caption: "  Target  ", duration: 120
        )
        #expect(overlay.rect == OdysseusVisualGuidanceRect(x: 40, y: 90, width: 80, height: 60))
        #expect(overlay.style.lineWidth == 48)
        #expect(overlay.style.fillOpacity == 0.65)
        #expect(overlay.style.caption == "Target")
        #expect(overlay.duration == 60)
        #expect(overlay.isRenderable)
        let encoded = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(OdysseusVisualGuidanceOverlay.self, from: encoded)
        #expect(decoded == overlay)
        let clamped = overlay.clamped(to: CGRect(x: 50, y: 100, width: 40, height: 40))
        #expect(clamped.rect == OdysseusVisualGuidanceRect(x: 50, y: 100, width: 40, height: 40))
    }

    @Test func scribbleRequiresAtLeastTwoPointsAndClampsPoints() throws {
        let overlay = OdysseusVisualGuidanceOverlay.scribble(
            points: [CGPoint(x: -10, y: 20), CGPoint(x: 100, y: 120), CGPoint(x: 300, y: 10)],
            accentHex: "#F59E0B", lineWidth: 0, duration: 0.01
        )
        #expect(overlay.isRenderable)
        #expect(overlay.style.lineWidth == 1)
        #expect(overlay.duration == 0.2)
        let clamped = overlay.clamped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(clamped.points.map(\.cgPoint) == [
            CGPoint(x: 0, y: 20), CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 10),
        ])
        let singlePoint = OdysseusVisualGuidanceOverlay.scribble(points: [CGPoint(x: 1, y: 1)])
        #expect(!singlePoint.isRenderable)
    }
}

struct CircleSelectSnapGeometryTests {
    @Test func circleSelectPathContainmentHandlesDescendingEdges() {
        let diamond: [CGPoint] = [
            CGPoint(x: 10, y: 0), CGPoint(x: 20, y: 10),
            CGPoint(x: 10, y: 20), CGPoint(x: 0, y: 10)
        ]
        #expect(CircleSelectSnapGeometry.pathContains(CGPoint(x: 10, y: 10), points: diamond))
        #expect(CircleSelectSnapGeometry.pathContains(CGPoint(x: 10, y: 10), points: Array(diamond.reversed())))
        #expect(!CircleSelectSnapGeometry.pathContains(CGPoint(x: 25, y: 10), points: diamond))
    }

    @Test func circleSelectAXCoordinatesUseMenuBarScreenOrigin() {
        #expect(CircleSelectSnapGeometry.appKitY(fromAXY: 120, height: 30, menuBarScreenMaxY: 900) == 750)
    }
}
