import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Dock'ta ikon yok, sadece menü çubuğu
app.run()
