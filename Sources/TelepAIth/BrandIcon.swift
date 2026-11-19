import AppKit

/// Menü çubuğu ikonu: büyücü şapkalı robot kafası (şablon görsel, açık/koyu temaya uyar).
enum BrandIcon {
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()

            // Şapka konisi (ucu sağa kıvrık)
            let hat = NSBezierPath()
            hat.move(to: NSPoint(x: 4, y: 8.5))
            hat.curve(to: NSPoint(x: 11.5, y: 0.5),
                      controlPoint1: NSPoint(x: 6.5, y: 6),
                      controlPoint2: NSPoint(x: 9, y: 2.5))
            hat.curve(to: NSPoint(x: 14, y: 8.5),
                      controlPoint1: NSPoint(x: 12.8, y: 3),
                      controlPoint2: NSPoint(x: 13.2, y: 6))
            hat.close()
            hat.fill()

            // Siper
            NSBezierPath(roundedRect: NSRect(x: 1.5, y: 7.5, width: 15, height: 2), xRadius: 1, yRadius: 1).fill()

            // Kafa, gözler oyuk
            let head = NSBezierPath(roundedRect: NSRect(x: 3.5, y: 10.5, width: 11, height: 7), xRadius: 2.5, yRadius: 2.5)
            head.append(NSBezierPath(roundedRect: NSRect(x: 6, y: 12.2, width: 1.8, height: 3.2), xRadius: 0.9, yRadius: 0.9))
            head.append(NSBezierPath(roundedRect: NSRect(x: 10.2, y: 12.2, width: 1.8, height: 3.2), xRadius: 0.9, yRadius: 0.9))
            head.windingRule = .evenOdd
            head.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
