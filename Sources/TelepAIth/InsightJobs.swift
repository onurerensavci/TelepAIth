import Foundation

/// Uyarıların arka plan işleri (Windows'ta InsightJobs.cs): push'tan sonra o commit'in CI'sini gh ile izler,
/// tur bitince commit'lenmemiş değişikliğe git ile bakar. gh/git yoksa sessizce vazgeçer.
enum InsightJobs {
    private static let queue = DispatchQueue(label: "telepaith.insights", qos: .utility, attributes: .concurrent)

    static func run(_ job: Insights.Job, insights: Insights, say: @escaping (AgentEvent) -> Void) {
        let deliver: (AgentEvent) -> Void = { e in DispatchQueue.main.async { say(e) } }
        queue.async {
            if job.kind == "ci" { watchCI(job, say: deliver) } else if job.kind == "commit" { checkCommit(job, insights: insights, say: deliver) }
        }
    }

    private static func watchCI(_ job: Insights.Job, say: (AgentEvent) -> Void) {
        guard let sha = exec("git", in: job.dir, ["rev-parse", "HEAD"]).flatMap({ String(data: $0, encoding: .utf8) })?
            .trimmingCharacters(in: .whitespacesAndNewlines), sha.count >= 7 else { return }
        let started = Date()
        Thread.sleep(forTimeInterval: 20)
        while Date().timeIntervalSince(started) < 45 * 60 {
            guard let json = exec("gh", in: job.dir, ["run", "list", "--commit", sha, "--json",
                                                      "status,conclusion,name,url,workflowName", "-L", "30"]) else { return }   // gh yok ya da giriş yapılmamış
            let result = CiStatus.summarize(json)
            if result == nil && Date().timeIntervalSince(started) > 180 { return }   // bu depoda CI yok
            if let r = result, r.done {
                if r.ok { Progress.shared.ci() }
                say(Insights.ciEvent(job, r))
                return
            }
            Thread.sleep(forTimeInterval: 30)
        }
    }

    private static func checkCommit(_ job: Insights.Job, insights: Insights, say: (AgentEvent) -> Void) {
        guard let status = exec("git", in: job.dir, ["status", "--porcelain"]),
              let last = exec("git", in: job.dir, ["log", "-1", "--format=%ct"]).flatMap({ String(data: $0, encoding: .utf8) }),
              let seconds = TimeInterval(last.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let lastCommit = Date(timeIntervalSince1970: seconds)
        let now = Date()
        if insights.nudge.shouldTell(job.dir, dirty: !status.isEmpty, lastCommit: lastCommit, now: now) {
            say(Insights.commitEvent(job, lastCommit: lastCommit, now: now))
        }
    }

    /// Komutu çalıştırır; başarısızsa (çıkış kodu ≠ 0, program yok, 20 sn'de bitmedi) nil.
    private static func exec(_ tool: String, in dir: String, _ args: [String]) -> Data? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { return nil }
        // Menü çubuğu uygulamasının PATH'i kısa: Homebrew'un yerlerini de ekle
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        guard let exe = paths.map({ "\($0)/\(tool)" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (paths + [env["PATH"] ?? ""]).joined(separator: ":")
        env["GH_PROMPT_DISABLED"] = "1"
        env["GIT_OPTIONAL_LOCKS"] = "0"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(20)
        var data = Data()
        let reader = DispatchQueue(label: "telepaith.insights.read")
        let done = DispatchSemaphore(value: 0)
        reader.async {
            data = out.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); return nil }
        _ = done.wait(timeout: .now() + 2)
        return p.terminationStatus == 0 ? data : nil
    }
}
