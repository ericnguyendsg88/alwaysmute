import AppKit

enum Artwork {
    static let ink = NSColor(calibratedRed: 0.17, green: 0.145, blue: 0.13, alpha: 1)
    static let coral = NSColor(calibratedRed: 0.90, green: 0.48, blue: 0.34, alpha: 1)
    static let blue = NSColor(calibratedRed: 0.79, green: 0.85, blue: 0.85, alpha: 1)
    static let sky = NSColor(calibratedRed: 0.84, green: 0.895, blue: 0.945, alpha: 1)
    static let paper = NSColor(calibratedRed: 0.965, green: 0.953, blue: 0.918, alpha: 1)
    static let sheet = NSColor(calibratedRed: 0.985, green: 0.978, blue: 0.955, alpha: 1)
    static let band = NSColor(calibratedRed: 0.905, green: 0.878, blue: 0.81, alpha: 1)
    static let footer = NSColor(calibratedRed: 0.915, green: 0.908, blue: 0.885, alpha: 1)
    static let sun = NSColor(calibratedRed: 0.93, green: 0.77, blue: 0.29, alpha: 1)
    static func grain(in rect: NSRect, count: Int, opacity: CGFloat, seed: UInt64 = 42) {
        var state = seed
        func random() -> CGFloat { state = state &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(state >> 33) / CGFloat(UInt32.max >> 1) }
        for _ in 0..<count {
            let x = rect.minX + random() * rect.width, y = rect.minY + random() * rect.height
            let alpha = opacity * (0.3 + random() * 0.7)
            ink.withAlphaComponent(alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 0.25 + random() * 0.65, height: 0.25 + random() * 0.9)).fill()
        }
    }
    static func hatch(in rect: NSRect, opacity: CGFloat = 0.15, spacing: CGFloat = 4, width: CGFloat = 0.55) {
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: rect).addClip()
        ink.withAlphaComponent(opacity).setStroke()
        for i in stride(from: -rect.height, through: rect.width + rect.height, by: spacing) {
            let p = NSBezierPath(); p.move(to: NSPoint(x: rect.minX + i, y: rect.minY)); p.line(to: NSPoint(x: rect.minX + i + rect.height, y: rect.maxY)); p.lineWidth = width; p.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    /// Seamless paper tile: fine tooth, soft mottling, sparse specks and a few fibers. Transparent so it can sit on any fill.
    static let texture: NSColor = {
        let pixels = 320
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var state: UInt64 = 7
        func random() -> Double { state = state &* 6364136223846793005 &+ 1442695040888963407; return Double(state >> 33) / Double(UInt32.max >> 1) }
        let data = rep.bitmapData!, row = rep.bytesPerRow
        let tau = Double.pi * 2 / Double(pixels)
        for y in 0..<pixels {
            for x in 0..<pixels {
                // Periodic waves keep the mottling seamless when tiled.
                let mottle = sin(Double(x) * tau * 2 + 1.3) * sin(Double(y) * tau * 3 + 0.4) * 0.6 + sin(Double(x) * tau * 5 + 2) * sin(Double(y) * tau * 4) * 0.4
                var tone = (random() - 0.5) * 0.9 + mottle * 0.22
                let speck = random()
                if speck < 0.0025 { tone = -3.5 } else if speck > 0.9965 { tone = 2.6 }
                let light = tone > 0
                let alpha = min(1, abs(tone) * (light ? 0.055 : 0.07))
                let value: UInt8 = light ? 255 : 38
                let i = y * row + x * 4
                // Premultiplied RGBA.
                let premultiplied = UInt8(Double(value) * alpha)
                data[i] = premultiplied; data[i + 1] = UInt8(Double(light ? 255 : 32) * alpha); data[i + 2] = UInt8(Double(light ? 250 : 26) * alpha); data[i + 3] = UInt8(alpha * 255)
            }
        }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for _ in 0..<26 {
            let start = NSPoint(x: random() * Double(pixels - 40) + 20, y: random() * Double(pixels - 40) + 20)
            let angle = random() * .pi, length = 8 + random() * 22
            let end = NSPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
            let bend = NSPoint(x: (start.x + end.x) / 2 + (random() - 0.5) * 8, y: (start.y + end.y) / 2 + (random() - 0.5) * 8)
            let fiber = NSBezierPath(); fiber.move(to: start); fiber.curve(to: end, controlPoint1: bend, controlPoint2: bend)
            fiber.lineWidth = 0.6 + random() * 0.6; fiber.lineCapStyle = .round
            ink.withAlphaComponent(0.035 + random() * 0.04).setStroke(); fiber.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pixels / 2, height: pixels / 2)); rep.size = image.size; image.addRepresentation(rep)
        return NSColor(patternImage: image)
    }()
    static func paperGrain(_ rect: NSRect, strength: CGFloat = 1) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(strength)
        texture.setFill(); rect.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()
    }
    /// Re-traces a path with a slow, seeded wobble so outlines read as inked by hand.
    static func rough(_ path: NSBezierPath, seed: Double, amount: CGFloat = 0.38) -> NSBezierPath {
        let flat = path.flattened, result = NSBezierPath()
        var points = [NSPoint](repeating: .zero, count: 3), travelled: CGFloat = 0, last = NSPoint.zero, first = NSPoint.zero
        func wobble(_ p: NSPoint) -> NSPoint {
            let t = Double(travelled)
            return NSPoint(x: p.x + amount * CGFloat(sin(t * 0.06 + seed) * 0.55 + sin(t * 0.23 + seed * 2.1) * 0.45),
                           y: p.y + amount * CGFloat(sin(t * 0.07 + seed * 1.7) * 0.55 + sin(t * 0.19 + seed * 0.6) * 0.45))
        }
        for index in 0..<flat.elementCount {
            switch flat.element(at: index, associatedPoints: &points) {
            case .moveTo: last = points[0]; first = last; result.move(to: wobble(last))
            case .lineTo, .curveTo, .cubicCurveTo, .quadraticCurveTo:
                let target = points[0], distance = hypot(target.x - last.x, target.y - last.y)
                let steps = max(1, Int(distance / 5))
                for step in 1...steps {
                    let f = CGFloat(step) / CGFloat(steps)
                    travelled += distance / CGFloat(steps)
                    result.line(to: wobble(NSPoint(x: last.x + (target.x - last.x) * f, y: last.y + (target.y - last.y) * f)))
                }
                last = target
            case .closePath:
                let distance = hypot(first.x - last.x, first.y - last.y)
                let steps = max(1, Int(distance / 5))
                for step in 1...steps {
                    let f = CGFloat(step) / CGFloat(steps); travelled += distance / CGFloat(steps)
                    result.line(to: wobble(NSPoint(x: last.x + (first.x - last.x) * f, y: last.y + (first.y - last.y) * f)))
                }
                last = first
            @unknown default: break
            }
        }
        return result
    }
    /// Main ink line plus a faint offset echo, like a pen passing twice.
    static func sketch(_ path: NSBezierPath, width: CGFloat = 1.6, color: NSColor = ink, seed: Double = 1) {
        let main = rough(path, seed: seed); main.lineWidth = width; main.lineJoinStyle = .round; main.lineCapStyle = .round
        color.setStroke(); main.stroke()
        let echo = rough(path, seed: seed + 4.3, amount: 0.7); echo.lineWidth = max(0.5, width * 0.35); echo.lineJoinStyle = .round
        let shift = NSAffineTransform(); shift.translateX(by: 0.7, yBy: 0.5); echo.transform(using: shift as AffineTransform)
        color.withAlphaComponent(0.3).setStroke(); echo.stroke()
    }
    /// Hatched shadow peeking out below and right of a shape, as in the sketch reference.
    static func hatchShadow(_ path: NSBezierPath, offset: NSSize = NSSize(width: 3, height: 5), opacity: CGFloat = 0.42) {
        NSGraphicsContext.saveGraphicsState()
        let shifted = path.copy() as! NSBezierPath
        let t = NSAffineTransform(); t.translateX(by: offset.width, yBy: offset.height); shifted.transform(using: t as AffineTransform)
        let clip = NSBezierPath(); clip.append(shifted); clip.append(path); clip.windingRule = .evenOdd; clip.addClip()
        hatch(in: shifted.bounds.union(path.bounds).insetBy(dx: -2, dy: -2), opacity: opacity, spacing: 3, width: 0.75)
        NSGraphicsContext.restoreGraphicsState()
    }
    /// `lift` (0…1) raises the character off the ground for hops; `wave` raises its right arm.
    static func mascot(size: CGFloat, muted: Bool = true, appIcon: Bool = false, lift: CGFloat = 0, wave: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let transform = NSAffineTransform(); transform.scale(by: size / 128); transform.concat()
            func stroke(_ path: NSBezierPath, _ width: CGFloat = 2.4) { ink.setStroke(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke() }
            func line(_ points: [NSPoint]) { let p = NSBezierPath(); p.move(to: points[0]); for v in points.dropFirst() { p.line(to: v) }; stroke(p) }
            if appIcon {
                let bg = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 126, height: 126), xRadius: 28, yRadius: 28)
                paper.setFill(); bg.fill(); bg.addClip()
                blue.withAlphaComponent(0.7).setFill()
                for x in stride(from: -140, to: 220, by: 48) { let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: 0)); p.line(to: NSPoint(x: x+25, y: 0)); p.line(to: NSPoint(x: x+153, y: 128)); p.line(to: NSPoint(x: x+128, y: 128)); p.close(); p.fill() }
            }
            // Ground line and a dense vertical-hatch shadow under the feet.
            let baseline = NSBezierPath(); baseline.move(to: NSPoint(x: 4, y: 13)); baseline.line(to: NSPoint(x: 124, y: 13.3)); ink.withAlphaComponent(0.22).setStroke(); baseline.lineWidth = 0.6; baseline.stroke()
            // The shadow tightens and fades as the character leaves the ground.
            let shadowWidth = 68 * (1 - 0.3 * lift), shadowHeight = 9 * (1 - 0.2 * lift)
            let shadow = NSBezierPath(ovalIn: NSRect(x: 64 - shadowWidth / 2, y: 12.5 - shadowHeight / 2, width: shadowWidth, height: shadowHeight))
            NSGraphicsContext.saveGraphicsState(); shadow.addClip(); ink.withAlphaComponent(0.4 * (1 - 0.35 * lift)).setStroke()
            for x in stride(from: CGFloat(30), through: 98, by: 1.6) { let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: 8)); p.line(to: NSPoint(x: x + 1.2, y: 17)); p.lineWidth = 0.5; p.stroke() }
            NSGraphicsContext.restoreGraphicsState()
            let hop = NSAffineTransform(); hop.translateX(by: 0, yBy: lift * 8); hop.concat()
            line([NSPoint(x: 49, y: 27), NSPoint(x: 46, y: 16)])
            line([NSPoint(x: 78, y: 27), NSPoint(x: 81, y: 16)])
            ink.setFill(); NSBezierPath(ovalIn: NSRect(x: 39, y: 12, width: 15, height: 8)).fill(); NSBezierPath(ovalIn: NSRect(x: 74, y: 12, width: 15, height: 8)).fill()
            line([NSPoint(x: 28, y: 54), NSPoint(x: 18, y: 34)])
            if wave { line([NSPoint(x: 99, y: 58), NSPoint(x: 113, y: 76)]) } else { line([NSPoint(x: 99, y: 54), NSPoint(x: 111, y: 34)]) }
            for hand in [NSRect(x: 14, y: 29, width: 8, height: 8), wave ? NSRect(x: 110, y: 74, width: 8, height: 8) : NSRect(x: 107, y: 29, width: 8, height: 8)] { let p = NSBezierPath(ovalIn: hand); coral.setFill(); p.fill(); stroke(p, 1.8) }
            if wave {
                // Little motion ticks beside the raised hand.
                for (a, b) in [(NSPoint(x: 120, y: 84), NSPoint(x: 124, y: 88)), (NSPoint(x: 122, y: 78), NSPoint(x: 127, y: 79))] { let p = NSBezierPath(); p.move(to: a); p.line(to: b); ink.withAlphaComponent(0.6).setStroke(); p.lineWidth = 1.4; p.lineCapStyle = .round; p.stroke() }
            }
            line([NSPoint(x: 66, y: 94), NSPoint(x: 73, y: 112)])
            let tip = NSBezierPath(ovalIn: NSRect(x: 68, y: 109, width: 10, height: 10)); sun.setFill(); tip.fill(); stroke(tip)
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 29, y: 80)); body.curve(to: NSPoint(x: 46, y: 97), controlPoint1: NSPoint(x: 30, y: 93), controlPoint2: NSPoint(x: 38, y: 98))
            body.line(to: NSPoint(x: 82, y: 96)); body.curve(to: NSPoint(x: 100, y: 78), controlPoint1: NSPoint(x: 97, y: 95), controlPoint2: NSPoint(x: 99, y: 86))
            body.line(to: NSPoint(x: 101, y: 45)); body.curve(to: NSPoint(x: 83, y: 26), controlPoint1: NSPoint(x: 101, y: 31), controlPoint2: NSPoint(x: 94, y: 26))
            body.line(to: NSPoint(x: 45, y: 27)); body.curve(to: NSPoint(x: 27, y: 46), controlPoint1: NSPoint(x: 29, y: 27), controlPoint2: NSPoint(x: 27, y: 36)); body.close()
            coral.setFill(); body.fill()
            NSGraphicsContext.saveGraphicsState(); body.addClip()
            NSGradient(starting: NSColor(calibratedRed: 1, green: 0.64, blue: 0.47, alpha: 0.7), ending: NSColor(calibratedRed: 0.74, green: 0.32, blue: 0.24, alpha: 0.4))!.draw(in: body.bounds, angle: -50)
            grain(in: body.bounds, count: 1400, opacity: 0.12)
            // A few long pencil strokes for shading, rather than a dense screen.
            let shade = NSBezierPath(); shade.move(to: NSPoint(x: 58, y: 26)); shade.line(to: NSPoint(x: 102, y: 80)); shade.line(to: NSPoint(x: 110, y: 24)); shade.close(); shade.addClip()
            hatch(in: body.bounds, opacity: 0.3, spacing: 7, width: 0.9)
            NSGraphicsContext.restoreGraphicsState(); stroke(body, 3)
            let echo = NSAffineTransform(); echo.translateX(by: 0.65, yBy: -0.45); let second = body.copy() as! NSBezierPath; second.transform(using: echo as AffineTransform); ink.withAlphaComponent(0.28).setStroke(); second.lineWidth = 0.6; second.stroke()
            for x: CGFloat in [38, 81] { NSColor(calibratedRed: 1, green: 0.63, blue: 0.62, alpha: 0.7).setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 61, width: 10, height: 4.5)).fill() }
            NSColor.white.withAlphaComponent(0.6).setFill(); NSBezierPath(roundedRect: NSRect(x: 36, y: 83, width: 11, height: 7), xRadius: 2.5, yRadius: 2.5).fill()
            for x: CGFloat in [46, 76] { ink.setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 67, width: 6, height: 9)).fill(); NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: x+1, y: 72, width: 2, height: 2)).fill() }
            let smile = NSBezierPath(); smile.move(to: NSPoint(x: 60, y: 66)); smile.curve(to: NSPoint(x: 68, y: 66), controlPoint1: NSPoint(x: 62, y: 61), controlPoint2: NSPoint(x: 66, y: 61)); stroke(smile, 1.8)
            // The same speaker-in-shield mark is used on the character and in the menu bar.
            let mark = Style.protectedSpeaker(size: 30, muted: muted)
            let tinted = NSImage(size: mark.size); tinted.lockFocus(); mark.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1); ink.setFill(); NSRect(origin: .zero, size: mark.size).fill(using: .sourceIn); tinted.unlockFocus()
            tinted.draw(in: NSRect(x: 53, y: 34, width: 23, height: 25))
            return true
        }
    }
}
