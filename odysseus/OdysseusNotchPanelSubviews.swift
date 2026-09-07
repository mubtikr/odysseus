import AppKit
import SwiftUI

struct OdysseusNotchHeroCard<Content: View>: View {
    @AppStorage(AppBundleConfiguration.userAppFontDefaultsKey) private var appFontRawValue = OdysseusResponseCaptionFont.fallback.rawValue
    @AppStorage(AppBundleConfiguration.userAppBoldTextDefaultsKey) private var appBoldTextEnabled = false
    @AppStorage(AppBundleConfiguration.userAppTitleFontSizeDefaultsKey) private var appTitleFontSize = 26.0
    @AppStorage(AppBundleConfiguration.userAppBodyFontSizeDefaultsKey) private var appBodyFontSize = 13.0
    @AppStorage(AppBundleConfiguration.userAppSubtextFontSizeDefaultsKey) private var appSubtextFontSize = 11.0

    private var typography: OdysseusPanelTypography {
        OdysseusPanelTypography(
            fontRawValue: appFontRawValue,
            boldTextEnabled: appBoldTextEnabled,
            titleFontSize: CGFloat(appTitleFontSize),
            bodyFontSize: CGFloat(appBodyFontSize),
            subtextFontSize: CGFloat(appSubtextFontSize)
        )
    }

    let title: String
    let subtitle: String
    let systemImageName: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                    Image(systemName: systemImageName)
                        .font(typography.font(size: 18, weight: .black))
                        .foregroundColor(accent)
                        .frame(width: 38, height: 38)
                    .background(Circle().fill(accent.opacity(0.15)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(typography.font(size: 15, weight: .black))
                        .foregroundColor(DS.Colors.textPrimary)
                    Text(subtitle)
                        .font(typography.font(size: 10, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.12), Color.white.opacity(0.045)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct OdysseusNotchMetricCard: View {
    @AppStorage(AppBundleConfiguration.userAppFontDefaultsKey) private var appFontRawValue = OdysseusResponseCaptionFont.fallback.rawValue
    @AppStorage(AppBundleConfiguration.userAppBoldTextDefaultsKey) private var appBoldTextEnabled = false
    @AppStorage(AppBundleConfiguration.userAppTitleFontSizeDefaultsKey) private var appTitleFontSize = 26.0
    @AppStorage(AppBundleConfiguration.userAppBodyFontSizeDefaultsKey) private var appBodyFontSize = 13.0
    @AppStorage(AppBundleConfiguration.userAppSubtextFontSizeDefaultsKey) private var appSubtextFontSize = 11.0

    private var typography: OdysseusPanelTypography {
        OdysseusPanelTypography(
            fontRawValue: appFontRawValue,
            boldTextEnabled: appBoldTextEnabled,
            titleFontSize: CGFloat(appTitleFontSize),
            bodyFontSize: CGFloat(appBodyFontSize),
            subtextFontSize: CGFloat(appSubtextFontSize)
        )
    }

    let title: String
    let value: String
    let detail: String
    let color: Color
    let systemImageName: String
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemImageName)
                    .font(typography.font(size: 13, weight: .black))
                    .foregroundColor(isSelected ? .white : color)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(color.opacity(isSelected ? 0.92 : 0.13)))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(value)
                            .font(typography.font(size: 16, weight: .black))
                            .foregroundColor(DS.Colors.textPrimary)
                            .lineLimit(1)
                        Text(title)
                            .font(typography.font(size: 9, weight: .black))
                            .foregroundColor(DS.Colors.textTertiary)
                            .textCase(.uppercase)
                            .lineLimit(1)
                    }
                    Text(detail)
                        .font(typography.font(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? color.opacity(0.14) : Color.white.opacity(0.052))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? color.opacity(0.50) : color.opacity(0.18), lineWidth: isSelected ? 1.2 : 1)
        )
    }
}

struct OdysseusPanelDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> OdysseusPanelDragHandleView {
        OdysseusPanelDragHandleView()
    }

    func updateNSView(_ nsView: OdysseusPanelDragHandleView, context: Context) {}
}

final class OdysseusPanelDragHandleView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.set()
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 1)
        let path = NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15)
        NSColor.white.withAlphaComponent(0.055).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.085).setStroke()
        path.lineWidth = 1
        path.stroke()

        let dotColor = NSColor.white.withAlphaComponent(0.38)
        dotColor.setFill()
        for xOffset in [-3.6, 3.6] {
            for yOffset in [-5.0, 0.0, 5.0] {
                let dotRect = NSRect(
                    x: rect.midX + xOffset - 1.5,
                    y: rect.midY + yOffset - 1.5,
                    width: 3,
                    height: 3
                )
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }
}

private struct OdysseusBottomRoundedRectangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct OdysseusRunningAgentIndicator: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 4.5, height: 4.5)
                    .scaleEffect(isAnimating ? 1.0 : 0.55)
                    .opacity(isAnimating ? 1.0 : 0.45)
                    .animation(
                        .easeInOut(duration: 0.54)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.13),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 18, height: 10)
        .onAppear { isAnimating = true }
        .onDisappear { isAnimating = false }
        .accessibilityLabel("Running")
    }
}

struct OdysseusNotchEmptyState: View {
    @AppStorage(AppBundleConfiguration.userAppFontDefaultsKey) private var appFontRawValue = OdysseusResponseCaptionFont.fallback.rawValue
    @AppStorage(AppBundleConfiguration.userAppBoldTextDefaultsKey) private var appBoldTextEnabled = false
    @AppStorage(AppBundleConfiguration.userAppTitleFontSizeDefaultsKey) private var appTitleFontSize = 26.0
    @AppStorage(AppBundleConfiguration.userAppBodyFontSizeDefaultsKey) private var appBodyFontSize = 13.0
    @AppStorage(AppBundleConfiguration.userAppSubtextFontSizeDefaultsKey) private var appSubtextFontSize = 11.0
    @AppStorage(AppBundleConfiguration.userAppLineSpacingDefaultsKey) private var appLineSpacing = 2.0

    private var typography: OdysseusPanelTypography {
        OdysseusPanelTypography(
            fontRawValue: appFontRawValue,
            boldTextEnabled: appBoldTextEnabled,
            titleFontSize: CGFloat(appTitleFontSize),
            bodyFontSize: CGFloat(appBodyFontSize),
            subtextFontSize: CGFloat(appSubtextFontSize)
        )
    }

    let systemImageName: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: systemImageName)
                .font(typography.font(size: 22, weight: .heavy))
                .foregroundColor(DS.Colors.textSecondary)
            Text(title)
                .font(typography.font(size: 12, weight: .heavy))
                .foregroundColor(DS.Colors.textPrimary)
            Text(subtitle)
                .font(typography.font(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .lineSpacing(CGFloat(appLineSpacing))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}
