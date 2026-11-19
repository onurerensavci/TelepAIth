import AppKit

if CommandLine.arguments.contains("--mcp") {
    // Anlatıcı modu: Claude'un başlattığı küçük MCP sunucusu (pencere açmaz)
    MCPServer.run()
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // Dock'ta ikon yok, sadece menü çubuğu
    app.run()
}
