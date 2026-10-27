import AppKit

/// NoSleep's cat: a round head with two pointed ears. Asleep, its eyes are
/// closed curves; awake, they are wide open with slit pupils.
///
/// Drawn as paths on a 230 × 200 grid, so it stays sharp from the menu bar up
/// to the app icon. Kept free of the rest of the app: `make icon` compiles this
/// file on its own to draw the icon's layers.
enum CatGlyph {
    case asleep
    case awake

    static let size = NSSize(width: 230, height: 200)
    static let brown = NSColor(srgbRed: 0.36, green: 0.27, blue: 0.19, alpha: 1)
    static let yellow = NSColor(srgbRed: 1.0, green: 0.82, blue: 0.24, alpha: 1)

    /// For the menu bar, `points` tall. A template either way, coloured like
    /// every other menu bar icon: the eyes say which state it is in, and a
    /// colour on the menu bar's grey would only cost contrast.
    func menuBarImage(points: CGFloat = 16) -> NSImage {
        image(points: points, template: true) { rect in
            self.draw(in: rect, head: .black, pupils: .black)
        }
    }

    /// For the panel's round button: a template asleep, brown and yellow awake.
    func badgeImage(points: CGFloat) -> NSImage {
        image(points: points, template: self == .asleep) { rect in
            switch self {
            case .asleep: self.draw(in: rect, head: .black)
            case .awake: self.draw(in: rect, head: Self.brown, eyes: Self.yellow, pupils: Self.brown)
            }
        }
    }

    private func image(points: CGFloat, template: Bool, _ draw: @escaping (NSRect) -> Void) -> NSImage {
        let size = NSSize(width: points * Self.size.width / Self.size.height, height: points)
        // Drawn when shown, not now, so `labelColor` resolves against the
        // menu bar's appearance at that moment.
        let image = NSImage(size: size, flipped: true) { rect in
            draw(rect)
            return true
        }
        image.isTemplate = template
        return image
    }

    /// Draws into the current context, top-down, filling `rect`. Without
    /// `eyes`, open eyes are cut out of the head, showing what is behind.
    func draw(in rect: NSRect, head: NSColor, eyes: NSColor? = nil, pupils: NSColor? = nil) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        Self.transform(to: rect).concat()

        head.setFill()
        Self.head.fill()

        switch self {
        case .asleep:
            cut(context) {
                for eye in Self.eyes {
                    let lid = NSBezierPath()
                    lid.move(to: NSPoint(x: eye.midX - 25, y: eye.midY + 2))
                    lid.curve(to: NSPoint(x: eye.midX + 25, y: eye.midY + 2),
                              controlPoint1: NSPoint(x: eye.midX - 12, y: eye.midY + 22),
                              controlPoint2: NSPoint(x: eye.midX + 12, y: eye.midY + 22))
                    lid.lineWidth = 14
                    lid.lineCapStyle = .round
                    lid.stroke()
                }
            }
        case .awake:
            for eye in Self.eyes {
                if let eyes {
                    eyes.setFill()
                    NSBezierPath(ovalIn: eye).fill()
                } else {
                    cut(context) { NSBezierPath(ovalIn: eye).fill() }
                }
                if let pupils {
                    pupils.setFill()
                    Self.pupil(in: eye).fill()
                }
            }
        }
    }

    // MARK: - Shape

    static func transform(to rect: NSRect) -> NSAffineTransform {
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / size.width, yBy: rect.height / size.height)
        return transform
    }

    static let eyes = [NSRect(x: 41, y: 62, width: 58, height: 90), NSRect(x: 131, y: 62, width: 58, height: 90)]

    /// A tall lens, pointed at both ends, like a cat's pupil in the dark.
    static func pupil(in eye: NSRect) -> NSBezierPath {
        let x = eye.midX, top = eye.minY + 12, bottom = eye.maxY - 12
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: top))
        path.curve(to: NSPoint(x: x, y: bottom), controlPoint1: NSPoint(x: x + 8, y: top + 22), controlPoint2: NSPoint(x: x + 8, y: bottom - 22))
        path.curve(to: NSPoint(x: x, y: top), controlPoint1: NSPoint(x: x - 8, y: bottom - 22), controlPoint2: NSPoint(x: x - 8, y: top + 22))
        path.close()
        return path
    }

    /// Ears up top, a wide round jaw below, and a small point at each cheek.
    static var head: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: 120))
        path.line(to: NSPoint(x: 12, y: 116))
        path.curve(to: NSPoint(x: 42, y: 0), controlPoint1: NSPoint(x: 12, y: 70), controlPoint2: NSPoint(x: 28, y: 10))
        path.curve(to: NSPoint(x: 80, y: 46), controlPoint1: NSPoint(x: 54, y: 8), controlPoint2: NSPoint(x: 66, y: 36))
        path.curve(to: NSPoint(x: 150, y: 46), controlPoint1: NSPoint(x: 102, y: 36), controlPoint2: NSPoint(x: 128, y: 36))
        path.curve(to: NSPoint(x: 188, y: 0), controlPoint1: NSPoint(x: 164, y: 36), controlPoint2: NSPoint(x: 176, y: 8))
        path.curve(to: NSPoint(x: 218, y: 116), controlPoint1: NSPoint(x: 202, y: 10), controlPoint2: NSPoint(x: 218, y: 70))
        path.line(to: NSPoint(x: 230, y: 120))
        path.curve(to: NSPoint(x: 115, y: 200), controlPoint1: NSPoint(x: 226, y: 172), controlPoint2: NSPoint(x: 178, y: 200))
        path.curve(to: NSPoint(x: 0, y: 120), controlPoint1: NSPoint(x: 52, y: 200), controlPoint2: NSPoint(x: 4, y: 172))
        path.close()
        return path
    }

    /// Whatever `draw` paints is erased instead.
    private func cut(_ context: NSGraphicsContext, _ draw: () -> Void) {
        context.saveGraphicsState()
        context.compositingOperation = .destinationOut
        NSColor.black.set()
        draw()
        context.restoreGraphicsState()
    }
}
