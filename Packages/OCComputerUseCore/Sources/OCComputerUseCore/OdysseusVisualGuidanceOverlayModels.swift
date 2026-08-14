import CoreGraphics
import Foundation

public struct OdysseusVisualGuidancePoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    public func clamped(to rect: CGRect) -> OdysseusVisualGuidancePoint {
        OdysseusVisualGuidancePoint(
            x: min(max(x, Double(rect.minX)), Double(rect.maxX)),
            y: min(max(y, Double(rect.minY)), Double(rect.maxY))
        )
    }
}

public struct OdysseusVisualGuidanceRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        // Standardize first: CGRect.width/height are always positive while
        // origin keeps the raw sign, so a negative-size rect used to produce a
        // rect whose origin did not match its extent.
        let standardized = rect.standardized
        self.x = Double(standardized.origin.x)
        self.y = Double(standardized.origin.y)
        self.width = Double(standardized.width)
        self.height = Double(standardized.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    public var normalized: OdysseusVisualGuidanceRect {
        let minX = min(x, x + width)
        let minY = min(y, y + height)
        return OdysseusVisualGuidanceRect(
            x: minX,
            y: minY,
            width: abs(width),
            height: abs(height)
        )
    }

    public func clamped(to bounds: CGRect) -> OdysseusVisualGuidanceRect {
        let rect = normalized.cgRect.intersection(bounds)
        guard !rect.isNull else {
            return OdysseusVisualGuidanceRect(x: bounds.minX, y: bounds.minY, width: 0, height: 0)
        }
        return OdysseusVisualGuidanceRect(rect)
    }
}

public enum OdysseusVisualGuidanceOverlayKind: String, Codable, Equatable, Sendable {
    case scribble
    case rectangle
}

public struct OdysseusVisualGuidanceStyle: Codable, Equatable, Hashable, Sendable {
    public var accentHex: String?
    public var lineWidth: Double
    public var fillOpacity: Double
    public var caption: String?

    public init(accentHex: String? = nil, lineWidth: Double = 5, fillOpacity: Double = 0.12, caption: String? = nil) {
        self.accentHex = accentHex
        self.lineWidth = max(1, min(lineWidth, 48))
        self.fillOpacity = max(0, min(fillOpacity, 0.65))
        self.caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct OdysseusVisualGuidanceOverlay: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: OdysseusVisualGuidanceOverlayKind
    public var points: [OdysseusVisualGuidancePoint]
    public var rect: OdysseusVisualGuidanceRect?
    public var style: OdysseusVisualGuidanceStyle
    public var duration: TimeInterval
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: OdysseusVisualGuidanceOverlayKind,
        points: [OdysseusVisualGuidancePoint] = [],
        rect: OdysseusVisualGuidanceRect? = nil,
        style: OdysseusVisualGuidanceStyle = OdysseusVisualGuidanceStyle(),
        duration: TimeInterval = 6,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.rect = rect
        self.style = style
        self.duration = max(0.2, min(duration, 60))
        self.createdAt = createdAt
    }

    public var screenBounds: CGRect {
        switch kind {
        case .rectangle:
            return rect?.normalized.cgRect ?? .null
        case .scribble:
            guard let first = points.first else { return .null }
            return points.dropFirst().reduce(CGRect(origin: first.cgPoint, size: .zero)) { partial, point in
                partial.union(CGRect(origin: point.cgPoint, size: .zero))
            }
        }
    }

    public func clamped(to desktopBounds: CGRect) -> OdysseusVisualGuidanceOverlay {
        var overlay = self
        overlay.points = points.map { $0.clamped(to: desktopBounds) }
        overlay.rect = rect?.clamped(to: desktopBounds)
        return overlay
    }

    public var isRenderable: Bool {
        switch kind {
        case .scribble:
            return points.count >= 2
        case .rectangle:
            guard let rect else { return false }
            let normalized = rect.normalized
            return normalized.width > 1 && normalized.height > 1
        }
    }
}

extension OdysseusVisualGuidanceOverlay {
    public static func scribble(
        points: [CGPoint],
        accentHex: String? = nil,
        lineWidth: Double = 5,
        caption: String? = nil,
        duration: TimeInterval = 6
    ) -> OdysseusVisualGuidanceOverlay {
        OdysseusVisualGuidanceOverlay(
            kind: .scribble,
            points: points.map { point in
                OdysseusVisualGuidancePoint(x: Double(point.x), y: Double(point.y))
            },
            style: OdysseusVisualGuidanceStyle(accentHex: accentHex, lineWidth: lineWidth, fillOpacity: 0, caption: caption),
            duration: duration
        )
    }

    public static func rectangle(
        rect: CGRect,
        accentHex: String? = nil,
        lineWidth: Double = 4,
        fillOpacity: Double = 0.05,
        caption: String? = nil,
        duration: TimeInterval = 6
    ) -> OdysseusVisualGuidanceOverlay {
        OdysseusVisualGuidanceOverlay(
            kind: .rectangle,
            rect: OdysseusVisualGuidanceRect(rect).normalized,
            style: OdysseusVisualGuidanceStyle(accentHex: accentHex, lineWidth: lineWidth, fillOpacity: fillOpacity, caption: caption),
            duration: duration
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
