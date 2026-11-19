import Foundation

/// Anlatıcı: TelepAIth'i `--mcp` ile çalıştırınca küçük bir MCP sunucusu olur (stdio, JSON-RPC).
/// Claude masaüstü ya da Claude Code bu sunucunun `telepaith_say` aracını çağırarak robota
/// o an ne yaptığını kendi ağzından söyler. Mesaj, çalışan TelepAIth uygulamasına yerel olarak iletilir.
enum MCPServer {
    static let toolName = "telepaith_say"

    static func run() {
        let args = CommandLine.arguments
        var source = "claude"
        if let i = args.firstIndex(of: "--source"), i + 1 < args.count { source = args[i + 1] }

        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8),
                  let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let id = message["id"]
            let method = message["method"] as? String ?? ""
            let params = message["params"] as? [String: Any] ?? [:]

            switch method {
            case "initialize":
                let version = params["protocolVersion"] as? String ?? "2025-06-18"
                reply(id, result: [
                    "protocolVersion": version,
                    "capabilities": ["tools": [String: Any]()],
                    "serverInfo": ["name": "telepaith", "version": appVersion],
                    "instructions": instructions,
                ])
            case "ping":
                reply(id, result: [String: Any]())
            case "tools/list":
                reply(id, result: ["tools": [toolSpec]])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                if name == toolName {
                    let delivered = send(arguments, source: source)
                    let text = delivered ? "ok" : "TelepAIth is not running; message not shown."
                    reply(id, result: ["content": [["type": "text", "text": text]], "isError": false])
                } else {
                    replyError(id, code: -32602, message: "Unknown tool: \(name)")
                }
            default:
                // Bildirimlere (id'siz) cevap verilmez
                if id != nil && !(id is NSNull) && !method.hasPrefix("notifications/") {
                    replyError(id, code: -32601, message: "Method not found: \(method)")
                }
            }
        }
    }

    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private static let instructions = """
    TelepAIth is a small robot on the user's screen. Call telepaith_say at the start of each meaningful step \
    (reading, searching, editing, running commands, testing) with a very short sentence in the user's language, \
    and once at the end with state "done". Keep it under ~8 words.
    """

    private static var toolSpec: [String: Any] {
        [
            "name": toolName,
            "description": """
            Show what you are doing right now in the speech bubble of the user's desktop robot (TelepAIth). \
            Call it when you start a meaningful step (e.g. "Dosyaları inceliyorum", "Testleri çalıştırıyorum") \
            and once when you finish (state "done"). Keep the text very short and in the user's language. \
            It only displays the text; it has no other effect.
            """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Short sentence (max ~8 words) in the user's language."],
                    "state": [
                        "type": "string",
                        "enum": ["thinking", "reading", "searching", "editing", "running", "waiting", "done", "error"],
                        "description": "What kind of step this is. Use 'done' when the whole task is finished.",
                    ],
                    "emoji": ["type": "string", "description": "Optional single emoji that fits the step."],
                ],
                "required": ["text"],
            ],
        ]
    }

    /// Mesajı çalışan TelepAIth'e iletir (yerel HTTP).
    private static func send(_ arguments: [String: Any], source: String) -> Bool {
        let portFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(AppInfo.supportDirName).appendingPathComponent("port")
        let port = (try? String(contentsOf: portFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "\(AppInfo.defaultPort)"
        guard let url = URL(string: "http://127.0.0.1:\(port)/event?source=\(source)") else { return false }

        var body: [String: Any] = ["session": "mcp", "text": (arguments["text"] as? String) ?? ""]
        body["state"] = (arguments["state"] as? String) ?? "thinking"
        if let emoji = arguments["emoji"] as? String, !emoji.isEmpty { body["emoji"] = emoji }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 2

        final class Result { var ok = false }
        let result = Result()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            result.ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 3)
        return result.ok
    }

    private static func reply(_ id: Any?, result: [String: Any]) {
        write(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private static func replyError(_ id: Any?, code: Int, message: String) {
        write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
    }

    private static func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

/// Anlatıcıyı Claude masaüstünün MCP ayarına ekler/kaldırır.
enum NarratorInstaller {
    static var claudeDesktopConfig: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    static var executablePath: String {
        Bundle.main.executablePath ?? "/Applications/TelepAIth.app/Contents/MacOS/TelepAIth"
    }

    /// Claude Code'a eklemek için Terminal komutu
    static var claudeCodeCommand: String {
        "claude mcp add --scope user telepaith -- \"\(executablePath)\" --mcp --source claude"
    }

    static let suggestedInstruction = loc(
        "Çalışırken her önemli adımın başında telepaith_say aracıyla ne yaptığını kısa Türkçe bir cümleyle söyle, iş bitince state \"done\" ile haber ver.",
        "While working, call the telepaith_say tool with a very short sentence at the start of each meaningful step, and once with state \"done\" when you finish.")

    static func isInstalled() -> Bool {
        guard let root = load(), let servers = root["mcpServers"] as? [String: Any] else { return false }
        return servers["telepaith"] != nil
    }

    static func install() throws {
        var root = load() ?? [:]
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["telepaith"] = ["command": executablePath, "args": ["--mcp", "--source", "claude"]]
        root["mcpServers"] = servers
        try save(root)
    }

    static func uninstall() throws {
        guard var root = load() else { return }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers.removeValue(forKey: "telepaith")
        root["mcpServers"] = servers
        try save(root)
    }

    private static func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: claudeDesktopConfig), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func save(_ root: [String: Any]) throws {
        let fm = FileManager.default
        let url = claudeDesktopConfig
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.appendingPathExtension("telepaith-backup")
        if fm.fileExists(atPath: url.path) && !fm.fileExists(atPath: backup.path) {
            try? fm.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
