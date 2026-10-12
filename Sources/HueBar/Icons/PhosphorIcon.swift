import AppKit
import SwiftUI

enum PhosphorWeight: Sendable {
    case regular
    case bold
    case fill
    /// The regular outline over a 20% opacity fill.
    case duotone
}

/// A Phosphor icon (https://phosphoricons.com) on its 256×256 grid. The icons themselves are
/// generated into PhosphorIcons.swift; only the weights the app uses are included.
struct PhosphorIcon: @unchecked Sendable {
    let regular: Path?
    let bold: Path?
    let fill: Path?
    let duotoneBackground: Path?

    init(regular: String? = nil, bold: String? = nil, fill: String? = nil, duotone: String? = nil) {
        self.regular = regular.map(Self.path)
        self.bold = bold.map(Self.path)
        self.fill = fill.map(Self.path)
        duotoneBackground = duotone.map(Self.path)
    }

    /// The outline for a weight, falling back to another generated weight if it wasn't included.
    func outline(_ weight: PhosphorWeight) -> Path {
        let preferred: Path? =
            switch weight {
            case .regular, .duotone: regular
            case .bold: bold
            case .fill: fill
            }
        return preferred ?? regular ?? bold ?? fill ?? Path()
    }

    /// A template image for the menu bar, which macOS tints to match the bar's appearance.
    func templateImage(_ weight: PhosphorWeight, size: CGFloat = 18) -> NSImage {
        let outline = outline(weight).cgPath
        let background = weight == .duotone ? duotoneBackground?.cgPath : nil
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: rect.width / 256, y: rect.height / 256)
            if let background {
                context.setFillColor(NSColor.black.withAlphaComponent(0.2).cgColor)
                context.addPath(background)
                context.fillPath()
            }
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(outline)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func path(_ data: String) -> Path {
        var path = Path()
        for command in PathData.parse(data) {
            switch command {
            case .move(let point): path.move(to: point)
            case .line(let point): path.addLine(to: point)
            case .cubic(let control1, let control2, let point):
                path.addCurve(to: point, control1: control1, control2: control2)
            case .quad(let control, let point): path.addQuadCurve(to: point, control: control)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// Draws a Phosphor icon in the current foreground style.
struct Ph: View {
    let icon: PhosphorIcon
    let weight: PhosphorWeight
    let size: CGFloat

    init(_ icon: PhosphorIcon, _ weight: PhosphorWeight = .regular, size: CGFloat = 16) {
        self.icon = icon
        self.weight = weight
        self.size = size
    }

    var body: some View {
        ZStack {
            if weight == .duotone, let background = icon.duotoneBackground {
                PhosphorShape(glyph: background)
                    .opacity(0.2)
            }
            PhosphorShape(glyph: icon.outline(weight))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct PhosphorShape: Shape {
    let glyph: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 256
        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 128 * scale, ty: rect.midY - 128 * scale
        )
        return glyph.applying(transform)
    }
}
