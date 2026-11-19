import AppKit

/// İsteğe bağlı kostümler (GPT'nin çizdiği görseller).
///
/// ~/.telepaith/skins/<kaynak>/sheet.png  → 5 sütun × 2 satır karakter tablosu:
///   1. satır: idle, thinking, reading, searching, editing
///   2. satır: running, waiting, done, error, sleeping
/// ~/.telepaith/skins/<kaynak>/<durum>.png → tek tek görseller (tablodakini ezer)
/// <kaynak> klasörü yoksa ~/.telepaith/skins/default/ kullanılır. Hiçbiri yoksa robot kodla çizilir.
final class SkinStore {
    static let shared = SkinStore()

    static let sheetOrder: [RobotState] = [
        .idle, .thinking, .reading, .searching, .editing,
        .running, .waiting, .done, .error, .sleeping,
    ]

    private var cache: [String: [RobotState: NSImage]] = [:]

    func reload() {
        cache = [:]
    }

    func image(source: String, state: RobotState) -> NSImage? {
        let images = load(source)
        if let img = images[state] { return img }
        switch state {
        case .delegating: return images[.thinking] ?? images[.idle]
        default: return images[.idle]
        }
    }

    func hasSkin(source: String) -> Bool {
        !load(source).isEmpty
    }

    private func load(_ source: String) -> [RobotState: NSImage] {
        if let cached = cache[source] { return cached }
        var result = loadFolder(AppInfo.skinsDir.appendingPathComponent(source, isDirectory: true))
        if result.isEmpty {
            result = loadFolder(AppInfo.skinsDir.appendingPathComponent("default", isDirectory: true))
        }
        cache[source] = result
        return result
    }

    private func loadFolder(_ folder: URL) -> [RobotState: NSImage] {
        var result: [RobotState: NSImage] = [:]
        let sheetURL = folder.appendingPathComponent("sheet.png")
        if let sheet = NSImage(contentsOf: sheetURL) {
            result = slice(sheet)
        }
        for state in RobotState.allCases {
            let url = folder.appendingPathComponent("\(state.rawValue).png")
            if let img = NSImage(contentsOf: url) { result[state] = img }
        }
        return result
    }

    private func slice(_ sheet: NSImage) -> [RobotState: NSImage] {
        guard let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [:] }
        let columns = 5
        let rows = 2
        let cellW = cg.width / columns
        let cellH = cg.height / rows
        guard cellW > 0, cellH > 0 else { return [:] }
        var result: [RobotState: NSImage] = [:]
        for (index, state) in SkinStore.sheetOrder.enumerated() {
            let col = index % columns
            let row = index / columns
            let rect = CGRect(x: col * cellW, y: row * cellH, width: cellW, height: cellH)
            if let piece = cg.cropping(to: rect) {
                result[state] = NSImage(cgImage: piece, size: NSSize(width: cellW, height: cellH))
            }
        }
        return result
    }
}
