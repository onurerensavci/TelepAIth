import AppKit

/// Menü çubuğu ikonu: nokta matris gözlü robot kafası (şablon görsel, açık/koyu temaya uyar).
enum BrandIcon {
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()

            // Yan cıvatalar
            NSBezierPath(roundedRect: NSRect(x: 0.4, y: 7.6, width: 1.8, height: 2.8), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 15.8, y: 7.6, width: 1.8, height: 2.8), xRadius: 0.8, yRadius: 0.8).fill()

            // Kafa, vizör oyuk
            let head = NSBezierPath(roundedRect: NSRect(x: 2, y: 2.5, width: 14, height: 13), xRadius: 4, yRadius: 4)
            head.append(NSBezierPath(roundedRect: NSRect(x: 4, y: 6, width: 10, height: 6.5), xRadius: 2.5, yRadius: 2.5))
            head.windingRule = .evenOdd
            head.fill()

            // Nokta gözler: her göz 2 × 3 nokta
            for x in [6.3, 7.7, 10.3, 11.7] {
                for y in [7.9, 9.25, 10.6] {
                    NSBezierPath(ovalIn: NSRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)).fill()
                }
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
