import Cocoa
import Foundation

// MARK: - Constants & Configuration

struct Constants {
    static let appName = "DeepSeek Harness Launcher"
    static let version: String = {
        if let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String, !ver.isEmpty {
            return ver
        }
        return "1.0.0"
    }()
    static let windowTitle = "DeepSeek Harness — Control Panel"
    static let bundleIdentifier = "com.deepseek.harness.launcher"
    static let defaultPort = "3080"
    static let defaultProfile = "web"
    static let defaultLaunchCommand = "pnpm dsh web"
    static let launchCommandDefaultsKey = "customLaunchCommand"
    /// How long to wait for the server to advertise its URL before assuming the
    /// default loopback address rather than leaving the UI stuck in "Starting".
    static let startupTimeout: TimeInterval = 90
    static let githubUrl = "https://github.com/deepseek-ai/deepseek-harness"
    static let authorUrl = "https://github.com/deep-blue-dark-red/deepseek-harness-launcher-for-macos"
    static let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DeepSeekHarness")
}

// MARK: - Environment & Workspace Manager

class EnvironmentManager {
    static let shared = EnvironmentManager()
    
    var repoRoot: String
    var pathEnvironment: String
    var nodePath: String?
    var pnpmPath: String?
    
    init() {
        self.pathEnvironment = EnvironmentManager.resolvePath()
        self.repoRoot = EnvironmentManager.detectRepoRoot()
        self.nodePath = EnvironmentManager.findBinary(named: "node", path: self.pathEnvironment)
        self.pnpmPath = EnvironmentManager.findBinary(named: "pnpm", path: self.pathEnvironment)
        
        try? FileManager.default.createDirectory(at: Constants.logsDirectory, withIntermediateDirectories: true)
    }
    
    static func resolvePath() -> String {
        var ordered: [String] = []
        var seen = Set<String>()
        func append(_ dir: String) {
            guard !dir.isEmpty, !seen.contains(dir) else { return }
            seen.insert(dir)
            ordered.append(dir)
        }

        // The login shell's own PATH comes first, in the order the user set it,
        // so version managers keep the precedence they were configured with.
        for dir in loginShellPath() {
            append(dir)
        }

        // Well-known locations follow as a fallback for launches where the shell
        // probe found nothing (a Finder launch with an unusual $SHELL, say).
        for dir in ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            append(dir)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for suffix in [".local/bin", ".cargo/bin", ".proto/shims", ".proto/bin",
                       ".asdf/shims", ".asdf/bin", ".fnm/current/bin", ".volta/bin"] {
            append("\(home)/\(suffix)")
        }

        let nvmDir = "\(home)/.nvm/versions/node"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            for version in contents.sorted().reversed() {
                append("\(nvmDir)/\(version)/bin")
            }
        }

        return ordered.joined(separator: ":")
    }

    /// Reads `$PATH` from a login shell. Bounded by a timeout: a slow or hanging
    /// rc file must not stall app launch indefinitely.
    private static func loginShellPath(timeout: TimeInterval = 3.0) -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }

        // Drain the pipe off the calling thread so a chatty profile that fills the
        // pipe buffer cannot deadlock against waitUntilExit().
        final class Box { var data = Data() }
        let box = Box()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            finished.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            kill(process.processIdentifier, SIGKILL)
            return []
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: box.data, encoding: .utf8) else { return [] }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
    }
    
    static func findBinary(named name: String, path: String) -> String? {
        let candidates = path.components(separatedBy: ":")
        for dir in candidates {
            let fullPath = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        return nil
    }
    
    static func detectRepoRoot() -> String {
        if let saved = UserDefaults.standard.string(forKey: "DSH_REPO_ROOT"),
           FileManager.default.fileExists(atPath: "\(saved)/package.json") {
            return saved
        }
        
        let cwd = FileManager.default.currentDirectoryPath
        if FileManager.default.fileExists(atPath: "\(cwd)/package.json") &&
           FileManager.default.fileExists(atPath: "\(cwd)/apps/cli") {
            return cwd
        }
        
        var candidateURL = Bundle.main.bundleURL
        for _ in 0..<5 {
            candidateURL = candidateURL.deletingLastPathComponent()
            let path = candidateURL.path
            if FileManager.default.fileExists(atPath: "\(path)/package.json") &&
               FileManager.default.fileExists(atPath: "\(path)/apps/cli") {
                return path
            }
        }
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possibleLocations = [
            "\(home)/git/deepseek-harness",
            "\(home)/Projects/deepseek-harness",
            "\(home)/Developer/deepseek-harness",
            "\(home)/code/deepseek-harness",
            "\(home)/deepseek-harness"
        ]
        
        for loc in possibleLocations {
            if FileManager.default.fileExists(atPath: "\(loc)/package.json") {
                return loc
            }
        }
        
        // If not found in standard locations, prompt user for folder
        if let userChosen = promptUserForRepoRoot() {
            return userChosen
        }
        
        return cwd
    }
    
    static func promptUserForRepoRoot() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Locate DeepSeek-Harness Folder"
        panel.message = "Could not automatically locate the DeepSeek-Harness repository folder. Please select your deepseek-harness folder:"
        panel.prompt = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            let chosenPath = url.path
            UserDefaults.standard.set(chosenPath, forKey: "DSH_REPO_ROOT")
            return chosenPath
        }
        return nil
    }
    
    func setRepoRoot(_ newPath: String) {
        self.repoRoot = newPath
        UserDefaults.standard.set(newPath, forKey: "DSH_REPO_ROOT")
    }
    
    // Credentials are deliberately not handled here. DeepSeek Harness owns its own
    // write-only credential store ($DSH_HOME/.credentials.yaml, configurable from the
    // Providers page in the web UI) and also honours an ambient $DEEPSEEK_API_KEY.
    // The launcher reads, writes and forwards no secrets.

    func checkBuildArtifacts() -> Bool {
        let dist = "\(repoRoot)/apps/web/dist/index.html"
        return FileManager.default.fileExists(atPath: dist)
    }
}

// MARK: - Process Manager for DSH Web Server

enum ServerStatus {
    case stopped
    case starting
    case running(url: String)
    case error(message: String)
}

class ServerManager: NSObject {
    static let shared = ServerManager()
    
    private var statusListeners: [(ServerStatus) -> Void] = []
    
    private(set) var status: ServerStatus = .stopped {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for listener in self.statusListeners {
                    listener(self.status)
                }
            }
        }
    }
    
    func addStatusListener(_ listener: @escaping (ServerStatus) -> Void) {
        statusListeners.append(listener)
        listener(status)
    }
    
    var onLogLine: ((String) -> Void)?
    
    private(set) var logHistory: [String] = []
    private let maxLogLines = 5000
    
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var logFileHandle: FileHandle?
    private(set) var currentWebUrl: String?
    private(set) var currentPort: String = Constants.defaultPort

    /// The exact command used to start the harness server, editable in the
    /// control panel and persisted in UserDefaults so it survives relaunches.
    private(set) var launchCommand: String = {
        let saved = UserDefaults.standard.string(forKey: Constants.launchCommandDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let saved, !saved.isEmpty else { return Constants.defaultLaunchCommand }
        return saved
    }()

    func setLaunchCommand(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        launchCommand = trimmed.isEmpty ? Constants.defaultLaunchCommand : trimmed
        UserDefaults.standard.set(launchCommand, forKey: Constants.launchCommandDefaultsKey)
        appendLogLine(">>> Launch command saved: \(launchCommand)")
    }

    /// Splits a command line into tokens, honouring single and double quotes.
    /// Shell operators are intentionally unsupported: the harness must stay a
    /// direct child process so it can be torn down cleanly with the launcher.
    static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        for ch in command {
            if let open = quote {
                if ch == open { quote = nil } else { current.append(ch) }
            } else if ch == "'" || ch == "\"" {
                quote = ch
            } else if ch.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// The `--port N` / `--port=N` value inside a tokenized command, if any.
    private static func portArgument(in tokens: [String]) -> String? {
        for (index, token) in tokens.enumerated() {
            if token == "--port", index + 1 < tokens.count {
                return tokens[index + 1]
            }
            if token.hasPrefix("--port=") {
                return String(token.dropFirst("--port=".count))
            }
        }
        return nil
    }

    /// Trailing partial line from the last pipe read, held until its newline arrives.
    private var pendingOutput = ""
    private var startupTimeoutWork: DispatchWorkItem?
    
    func appendLogLine(_ line: String) {
        logHistory.append(line)
        if logHistory.count > maxLogLines {
            logHistory.removeFirst(logHistory.count - maxLogLines)
        }
        self.onLogLine?(line)
    }
    
    func getLogText() -> String {
        if !logHistory.isEmpty {
            return logHistory.joined(separator: "\n")
        }
        let logFilePath = Constants.logsDirectory.appendingPathComponent("dsh-web.log")
        if let diskContent = try? String(contentsOfFile: logFilePath.path, encoding: .utf8), !diskContent.isEmpty {
            return diskContent
        }
        let env = EnvironmentManager.shared
        return """
        === DeepSeek Harness — Live Logs Console ===
        DSH Folder: \(env.repoRoot)
        Server Status: Stopped
        
        Logs will stream here in real time when the Web server or tasks are started.
        """
    }
    
    static func killLingeringServerProcesses(ports: [String] = [Constants.defaultPort]) {
        // Only the port the server actually serves on. 5173 used to be swept too,
        // but the harness never binds it, so that could only kill an unrelated
        // Vite dev server belonging to the user.
        for port in ports {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            task.arguments = ["-ti", ":\(port)"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            if (try? task.run()) != nil {
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let pids = output.components(separatedBy: .newlines).compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
                    for pid in pids where pid > 0 && pid != ProcessInfo.processInfo.processIdentifier {
                        kill(pid, SIGTERM)
                        kill(pid, SIGKILL)
                    }
                }
            }
        }
    }
    
    func startWebServer() {
        // A previous failure must not wedge the launcher: starting is allowed from
        // .error as well as .stopped, so the "Retry" button actually retries.
        switch status {
        case .starting, .running:
            return
        case .stopped, .error:
            break
        }

        let env = EnvironmentManager.shared

        // Resolve the user-editable launch command from the control panel.
        let tokens = ServerManager.tokenize(launchCommand)
        guard let commandName = tokens.first, !commandName.isEmpty else {
            self.status = .error(message: "Launch command is empty. Set it in the control panel.")
            return
        }

        let executablePath: String
        if commandName.hasPrefix("/") {
            executablePath = commandName
        } else if let resolved = EnvironmentManager.findBinary(named: commandName, path: env.pathEnvironment) {
            executablePath = resolved
        } else {
            self.status = .error(message: "Launch command executable not found in PATH: \(commandName). Check the Launch Command field in the control panel.")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            self.status = .error(message: "Launch command executable is not runnable: \(executablePath)")
            return
        }

        // Clean up any stale process left holding the web port before starting
        let commandPort = ServerManager.portArgument(in: tokens) ?? Constants.defaultPort
        ServerManager.killLingeringServerProcesses(ports: [commandPort])
        usleep(150_000)

        self.status = .starting
        self.currentWebUrl = nil
        self.pendingOutput = ""

        let logFilePath = Constants.logsDirectory.appendingPathComponent("dsh-web.log")
        FileManager.default.createFile(atPath: logFilePath.path, contents: nil)
        self.logFileHandle = try? FileHandle(forWritingTo: logFilePath)
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.currentDirectoryURL = URL(fileURLWithPath: env.repoRoot)
        
        self.currentPort = commandPort
        proc.arguments = Array(tokens.dropFirst())

        // No credentials are injected: the harness resolves its own API key.
        var procEnv = ProcessInfo.processInfo.environment
        procEnv["PATH"] = env.pathEnvironment
        proc.environment = procEnv
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.stdoutPipe = pipe
        self.process = proc
        
        appendLogLine(">>> Starting DeepSeek Harness Web GUI (\(launchCommand)) in \(env.repoRoot)...")
        
        let outHandle = pipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }

            try? self.logFileHandle?.write(contentsOf: data)

            if let text = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.ingestOutput(text)
                }
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.flushPendingOutput()
                self.cancelStartupTimeout()
                TaskMonitor.shared.stop()
                try? self.logFileHandle?.close()
                self.logFileHandle = nil
                self.process = nil
                self.appendLogLine(">>> DeepSeek Harness Web process exited with code \(p.terminationStatus)")
                self.status = .stopped
            }
        }

        do {
            try proc.run()
            scheduleStartupTimeout()
        } catch {
            let errMsg = "Failed to start process: \(error.localizedDescription)"
            appendLogLine(">>> Error: \(errMsg)")
            self.status = .error(message: errMsg)
        }
    }

    // MARK: Output handling

    /// Buffers reads into whole lines. `availableData` splits on arbitrary byte
    /// boundaries, so a URL can otherwise arrive cut in half and never be matched.
    private func ingestOutput(_ chunk: String) {
        pendingOutput += chunk
        while let breakIndex = pendingOutput.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(pendingOutput[pendingOutput.startIndex..<breakIndex])
            pendingOutput = String(pendingOutput[pendingOutput.index(after: breakIndex)...])
            handleOutputLine(line)
        }
        // Servers often print the URL on a line they leave open; match it early
        // without consuming the buffer, so the final newline still logs it once.
        if !pendingOutput.isEmpty {
            parseOutputLine(ServerManager.stripAnsiCodes(pendingOutput))
        }
    }

    private func flushPendingOutput() {
        guard !pendingOutput.isEmpty else { return }
        let remainder = pendingOutput
        pendingOutput = ""
        handleOutputLine(remainder)
    }

    private func handleOutputLine(_ rawLine: String) {
        let line = ServerManager.stripAnsiCodes(rawLine)
        if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            appendLogLine(line)
        }
        parseOutputLine(line)
    }

    /// Removes ANSI CSI/OSC escape sequences. Vite and friends wrap their URLs in
    /// colour codes, which both corrupt the log view and defeat URL parsing.
    static func stripAnsiCodes(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        let chars = Array(text)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            guard chars[i] == "\u{1B}", i + 1 < chars.count else {
                if chars[i] != "\u{1B}" { out.append(chars[i]) }
                i += 1
                continue
            }
            switch chars[i + 1] {
            case "[":
                // CSI: parameter/intermediate bytes, then a final byte in @...~
                var j = i + 2
                while j < chars.count, !("@"..."~").contains(chars[j]) { j += 1 }
                i = min(j + 1, chars.count)
            case "]":
                // OSC: terminated by BEL or ST (ESC \)
                var j = i + 2
                while j < chars.count {
                    if chars[j] == "\u{07}" { j += 1; break }
                    if chars[j] == "\u{1B}", j + 1 < chars.count, chars[j + 1] == "\\" { j += 2; break }
                    j += 1
                }
                i = j
            default:
                i += 2
            }
        }
        return out
    }

    /// Extracts the first loopback URL in a line, tolerating surrounding prose and
    /// trailing punctuation (`➜  Local:   http://127.0.0.1:3080/`).
    static func firstLoopbackURL(in line: String) -> String? {
        let stops: Set<Character> = [" ", "\t", "\"", "'", "<", ">", "(", ")"]
        for host in ["127.0.0.1", "localhost"] {
            for scheme in ["http://", "https://"] {
                guard let range = line.range(of: scheme + host) else { continue }
                var end = range.upperBound
                while end < line.endIndex, !stops.contains(line[end]) {
                    end = line.index(after: end)
                }
                var candidate = String(line[range.lowerBound..<end])
                while let last = candidate.last, ".,;:".contains(last) {
                    candidate.removeLast()
                }
                if URL(string: candidate) != nil { return candidate }
            }
        }
        return nil
    }

    private func parseOutputLine(_ line: String) {
        guard case .starting = status else { return }
        guard let url = ServerManager.firstLoopbackURL(in: line) else { return }
        cancelStartupTimeout()
        self.currentWebUrl = url
        self.status = .running(url: url)
        // The URL carries the one-time token the API needs to authenticate.
        TaskMonitor.shared.start(webUrl: url)
    }

    // MARK: Startup watchdog

    /// Without this, a server whose banner we fail to recognise leaves the UI in
    /// "Starting..." forever. Assume the conventional URL instead of hanging.
    private func scheduleStartupTimeout() {
        cancelStartupTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, case .starting = self.status else { return }
            let assumed = "http://127.0.0.1:\(self.currentPort)"
            self.appendLogLine(">>> No server URL seen after \(Int(Constants.startupTimeout))s; assuming \(assumed). Check the log above if the page does not load.")
            self.currentWebUrl = assumed
            self.status = .running(url: assumed)
        }
        startupTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.startupTimeout, execute: work)
    }

    private func cancelStartupTimeout() {
        startupTimeoutWork?.cancel()
        startupTimeoutWork = nil
    }

    func stopWebServer() {
        cancelStartupTimeout()
        TaskMonitor.shared.stop()
        guard let proc = process, proc.isRunning else {
            ServerManager.killLingeringServerProcesses()
            self.status = .stopped
            return
        }

        appendLogLine(">>> Stopping DeepSeek Harness Web server...")
        let pid = proc.processIdentifier
        kill(-pid, SIGTERM)
        proc.terminate()
        
        DispatchQueue.global().async {
            for _ in 0..<20 {
                if !proc.isRunning { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            if proc.isRunning {
                kill(-pid, SIGKILL)
                kill(pid, SIGKILL)
            }
            ServerManager.killLingeringServerProcesses()
            DispatchQueue.main.async { [weak self] in
                self?.status = .stopped
            }
        }
    }
    
    func openInBrowser() {
        if let urlStr = currentWebUrl, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "http://127.0.0.1:\(currentPort)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Harness API Client

/// Minimal read-only client for the harness's `/api` RPC surface.
///
/// The transport is an internal contract with no stability guarantee; it was
/// derived from the gateway's own validation errors:
///
///   * the launch token is *not* accepted as an `/api` query parameter — fetching
///     the tokenized index URL exchanges it for a session cookie (a 303),
///   * endpoints live at `/api/<endpoint>` and `method` must equal that exact
///     endpoint string (`session/list`, not `session.list`),
///   * arguments nest under `payload.args`, keyed `_request` for `session/list`
///     and `request` for `session/page`.
///
/// Every failure path returns nil rather than throwing: a harness update may
/// change any of the above, and launching/stopping the server must keep working
/// even when monitoring cannot.
final class HarnessAPIClient {
    struct TokenUsage {
        var input = 0
        var output = 0

        static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
            TokenUsage(input: lhs.input + rhs.input, output: lhs.output + rhs.output)
        }
    }

    struct SessionSummary {
        let sessionId: String
        let running: Bool
        let blank: Bool
        let cwd: String?
        let title: String?
        /// Goal continuation phase: `active`, `paused`, `blocked`, or `complete`.
        let goalPhase: String?
        /// Human-readable explanation, present exactly while the goal is blocked.
        let goalBlockedReason: String?
        /// Fallback label when a session has no title yet.
        let goalObjective: String?
        let usage: TokenUsage
    }

    private let baseURL: URL
    private let tokenURL: URL
    private let urlSession: URLSession
    private var authenticated = false

    /// - Parameter webUrl: the tokenized URL the server prints at startup.
    ///   Returns nil when it carries no `token`, since the cookie exchange
    ///   cannot be completed without one.
    init?(webUrl: String) {
        guard let url = URL(string: webUrl),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else { return nil }
        self.tokenURL = url
        components.query = nil
        components.path = "/"
        guard let base = components.url else { return nil }
        self.baseURL = base

        // Ephemeral: an isolated cookie jar, so the launcher never touches the
        // user's shared cookie storage.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 10
        self.urlSession = URLSession(configuration: configuration)
    }

    private func authenticateIfNeeded() async -> Bool {
        if authenticated { return true }
        guard let (_, response) = try? await urlSession.data(from: tokenURL),
              let http = response as? HTTPURLResponse, http.statusCode < 400 else { return false }
        authenticated = true
        return true
    }

    /// Returns the `result` object, whether it reports success or a gateway error.
    private func rpc(_ endpoint: String, args: [String: Any]) async -> [String: Any]? {
        guard await authenticateIfNeeded(),
              let url = URL(string: "api/\(endpoint)", relativeTo: baseURL) else { return nil }
        let body: [String: Any] = [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": endpoint,
            "payload": ["args": args],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, _) = try? await urlSession.data(for: request),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return root["result"] as? [String: Any]
    }

    /// Cold-safe: listing does not activate an agent, so this is cheap to poll.
    func listSessions() async -> [SessionSummary]? {
        guard let result = await rpc("session/list", args: ["_request": [:]]),
              result["ok"] as? Bool == true,
              let value = result["value"] as? [String: Any],
              let items = value["items"] as? [[String: Any]] else { return nil }

        return items.compactMap { item in
            guard let id = item["sessionId"] as? String else { return nil }
            let projections = (item["projections"] as? [String: Any])?["values"] as? [String: Any]
            let goal = projections?["goal"] as? [String: Any]

            // Cache reads and writes are still input the model was billed for, so
            // they belong in the inbound total rather than being dropped.
            var usage = TokenUsage()
            if let raw = projections?["tokenUsage"] as? [String: Any] {
                let uncached = raw["uncachedInputTokens"] as? Int ?? 0
                let cacheRead = raw["cacheReadTokens"] as? Int ?? 0
                let cacheWrite = raw["cacheWriteTokens"] as? Int ?? 0
                usage.input = uncached + cacheRead + cacheWrite
                usage.output = raw["outputTokens"] as? Int ?? 0
            }

            return SessionSummary(
                sessionId: id,
                running: item["running"] as? Bool ?? false,
                blank: item["blank"] as? Bool ?? false,
                cwd: item["cwd"] as? String,
                title: projections?["title"] as? String,
                goalPhase: goal?["phase"] as? String,
                goalBlockedReason: (goal?["blockedReason"] as? [String: Any])?["message"] as? String,
                goalObjective: goal?["objective"] as? String,
                usage: usage
            )
        }
    }

    /// Requests cancellation of a session's active turn. Returns true when the
    /// harness admits the request to the live agent.
    func cancel(sessionId: String) async -> Bool {
        guard let result = await rpc("session/cancel", args: ["request": ["sessionId": sessionId]]) else { return false }
        return result["ok"] as? Bool == true
    }

    /// The `kind` of the session's most recent `turn/end`, or nil when unknown.
    ///
    /// `completed` means the turn finished normally; every other kind
    /// (`aborted`, `blocked`, `error`, `max-tokens`, `interrupted`, or anything a
    /// plugin adds) means it stopped for some other reason and wants attention.
    func lastTurnEndKind(sessionId: String) async -> String? {
        guard let cursor = await pageCursor(sessionId: sessionId),
              let result = await rpc("session/page", args: ["request": [
                  "address": ["kind": "session", "sessionId": sessionId],
                  "throughSeq": cursor,
                  "maxMessages": 4,
              ]]),
              result["ok"] as? Bool == true,
              let value = result["value"] as? [String: Any],
              let records = value["records"] as? [Any] else { return nil }
        return HarnessAPIClient.latestTurnEndKind(in: records)
    }

    /// Discovers the log's current cursor. `session/page` requires a `throughSeq`
    /// no greater than the cursor, and the only way to learn it without opening a
    /// follow stream is to over-request and read the cursor back out of the
    /// rejection message.
    private func pageCursor(sessionId: String) async -> Int? {
        let probe = 2_000_000_000
        guard let result = await rpc("session/page", args: ["request": [
            "address": ["kind": "session", "sessionId": sessionId],
            "throughSeq": probe,
            "maxMessages": 1,
        ]]) else { return nil }

        if result["ok"] as? Bool == true { return probe }
        guard let error = result["error"] as? [String: Any],
              let message = error["message"] as? String,
              let marker = message.range(of: "past cursor ") else { return nil }
        return Int(message[marker.upperBound...].prefix { $0.isNumber })
    }

    /// Finds the highest-`seq` `turn/end` anywhere in a page's records, which
    /// nest events inside chunk runs.
    static func latestTurnEndKind(in records: [Any]) -> String? {
        var bestSeq = Int.min
        var kind: String?

        func walk(_ node: Any) {
            if let dictionary = node as? [String: Any] {
                if dictionary["type"] as? String == "turn/end",
                   let data = dictionary["data"] as? [String: Any],
                   let reason = data["reason"] as? [String: Any],
                   let found = reason["kind"] as? String {
                    let seq = dictionary["seq"] as? Int ?? Int.min + 1
                    if seq >= bestSeq {
                        bestSeq = seq
                        kind = found
                    }
                }
                for value in dictionary.values { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }

        records.forEach(walk)
        return kind
    }
}

// MARK: - Task Monitor

/// Counts of the tasks observed during the current server run.
struct TaskCounts: Equatable {
    var running = 0
    var completed = 0
    var halted = 0

    var total: Int { running + completed + halted }
    var isEmpty: Bool { total == 0 }
}

/// Tracks agent tasks by polling `session/list`.
///
/// Only sessions seen *running* during this server run are counted: the harness
/// persists every session it has ever opened (20 on a typical machine, mostly
/// blank), so counting the whole list would render the badge meaningless.
final class TaskMonitor {
    static let shared = TaskMonitor()

    enum Outcome: Equatable {
        case running
        case done
        /// Stopped for a reason other than completing — wants attention.
        case halted(reason: String?)
        /// The user paused the goal.
        case paused
        /// The goal is blocked; `reason` is the policy's human-readable message.
        case blocked(reason: String?)

        var isRunning: Bool { self == .running }
        var isDone: Bool { self == .done }
        /// Everything that wants the user's attention, badged 🐠.
        var needsAttention: Bool { !isRunning && !isDone }

        /// Menu marker: green tick for done, yellow fish for anything stalled.
        var marker: String {
            switch self {
            case .running: return "🐋"
            case .done: return "✅"
            case .paused: return "⏸"
            case .halted, .blocked: return "🐠"
            }
        }

        var reason: String? {
            switch self {
            case .halted(let reason), .blocked(let reason): return reason
            case .running, .done, .paused: return nil
            }
        }
    }

    struct Task {
        let sessionId: String
        var title: String?
        var cwd: String?
        var outcome: Outcome
        var usage = HarnessAPIClient.TokenUsage()

        /// Shortened label for menu rows.
        var shortName: String {
            let raw = (title?.isEmpty == false ? title : nil) ?? "Untitled task"
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count <= 38 ? trimmed : String(trimmed.prefix(37)) + "…"
        }
    }

    private(set) var counts = TaskCounts()
    private(set) var tasks: [String: Task] = [:]
    /// False once the API contract stops parsing, so the UI can fall back.
    private(set) var isAvailable = false

    var onChange: ((TaskCounts) -> Void)?

    private var client: HarnessAPIClient?
    private var timer: Timer?
    private var polling = false
    private var loggedUnavailable = false
    /// Last published observable state, so notifications fire on any change.
    private var lastSignature = ""

    private static let pollInterval: TimeInterval = 3.0

    func start(webUrl: String) {
        stop()
        guard let client = HarnessAPIClient(webUrl: webUrl) else {
            reportUnavailable("the server URL carried no token, so the API cannot be authenticated")
            return
        }
        self.client = client
        timer = Timer.scheduledTimer(withTimeInterval: TaskMonitor.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        client = nil
        polling = false
        loggedUnavailable = false
        isAvailable = false
        tasks.removeAll()
        lastSignature = ""
        updateCounts()
    }

    private func reportUnavailable(_ detail: String) {
        isAvailable = false
        guard !loggedUnavailable else { return }
        loggedUnavailable = true
        ServerManager.shared.appendLogLine(">>> Task monitoring unavailable: \(detail). Start/stop is unaffected.")
        updateCounts()
    }

    private func poll() {
        guard let client = client, !polling else { return }
        polling = true

        // Snapshot the tracked set here, on the main thread, so the background
        // work never reads `tasks` while the main thread is mutating it.
        let trackedRunning = Set(tasks.values.filter { $0.outcome == .running }.map(\.sessionId))

        _Concurrency.Task { [weak self] in
            // Bind once to a `let`: an optional captured var is not concurrency-safe.
            guard let monitor = self else { return }
            let summaries = await client.listSessions()

            guard let summaries = summaries else {
                await MainActor.run {
                    monitor.polling = false
                    monitor.reportUnavailable("session/list did not return a readable response")
                }
                return
            }

            // Resolve why each task that stopped since the last poll ended. Only
            // transitions are resolved, so the extra call is rare.
            let liveIds = Set(summaries.filter(\.running).map(\.sessionId))
            var outcomes: [String: String?] = [:]
            for id in trackedRunning where !liveIds.contains(id) {
                outcomes[id] = await client.lastTurnEndKind(sessionId: id)
            }

            let resolved = outcomes
            await MainActor.run {
                monitor.apply(summaries: summaries, resolved: resolved)
                monitor.polling = false
            }
        }
    }

    private func apply(summaries: [HarnessAPIClient.SessionSummary], resolved: [String: String?]) {
        isAvailable = true
        loggedUnavailable = false

        for summary in summaries {
            let label = summary.title ?? summary.goalObjective
            if var existing = tasks[summary.sessionId] {
                if let label = label { existing.title = label }
                existing.cwd = summary.cwd ?? existing.cwd
                existing.usage = summary.usage
                if summary.running { existing.outcome = .running }
                tasks[summary.sessionId] = existing
            } else if summary.running {
                tasks[summary.sessionId] = Task(
                    sessionId: summary.sessionId,
                    title: label,
                    cwd: summary.cwd,
                    outcome: .running,
                    usage: summary.usage
                )
            }
        }

        for (id, kind) in resolved {
            guard var task = tasks[id] else { continue }
            // An unresolvable reason counts as done: a spurious "needs attention"
            // badge is worse than a missed one.
            task.outcome = (kind == nil || kind == "completed") ? .done : .halted(reason: kind)
            tasks[id] = task
        }

        // The durable goal phase outranks the turn-end reason: a paused or
        // blocked goal is the state the user acted on, and it survives the turn
        // that happened to end underneath it.
        for summary in summaries {
            guard var task = tasks[summary.sessionId], !summary.running else { continue }
            switch summary.goalPhase {
            case "paused": task.outcome = .paused
            case "blocked": task.outcome = .blocked(reason: summary.goalBlockedReason)
            case "complete": task.outcome = .done
            default: break
            }
            tasks[summary.sessionId] = task
        }

        updateCounts()
    }

    /// Inbound and outbound tokens summed across every tracked task.
    var totalUsage: HarnessAPIClient.TokenUsage {
        tasks.values.reduce(HarnessAPIClient.TokenUsage()) { $0 + $1.usage }
    }

    private func updateCounts() {
        var next = TaskCounts()
        for task in tasks.values {
            if task.outcome.isRunning { next.running += 1 }
            else if task.outcome.isDone { next.completed += 1 }
            else { next.halted += 1 }
        }
        counts = next

        // Notify on any observable change, not just the counts. Availability and
        // per-task usage move while the counts stand still — keying only on
        // counts left the UI rendering whatever it had at server-start time.
        let signature = ([
            "available:\(isAvailable)",
            "counts:\(next.running)/\(next.completed)/\(next.halted)",
        ] + tasks.values
            .sorted { $0.sessionId < $1.sessionId }
            .map { "\($0.sessionId):\($0.outcome.marker):\($0.usage.input):\($0.usage.output)" }
        ).joined(separator: "|")

        guard signature != lastSignature else { return }
        lastSignature = signature
        onChange?(next)
    }

    /// Every tracked task, live first, then stalled, then finished.
    func orderedTasks(limit: Int = 8) -> [Task] {
        func rank(_ task: Task) -> Int {
            if task.outcome.isRunning { return 0 }
            if task.outcome.needsAttention { return 1 }
            return 2
        }
        let sorted = tasks.values.sorted {
            rank($0) != rank($1) ? rank($0) < rank($1) : $0.shortName < $1.shortName
        }
        return Array(sorted.prefix(limit))
    }

    /// Asks the harness to cancel a task's active turn.
    func halt(sessionId: String) {
        guard let client = client else { return }
        _Concurrency.Task {
            let accepted = await client.cancel(sessionId: sessionId)
            await MainActor.run {
                ServerManager.shared.appendLogLine(
                    accepted
                        ? ">>> Halt requested for \(sessionId)."
                        : ">>> Halt request for \(sessionId) was refused by the harness."
                )
            }
        }
    }
}

// MARK: - Headless & Terminal Task Runner

class HeadlessRunner {
    static func runTaskInTerminal(task: String, repoRoot: String, pathEnv: String) {
        let escapedTask = task.replacingOccurrences(of: "\"", with: "\\\"")

        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-task-\(ProcessInfo.processInfo.globallyUniqueString.prefix(8)).command")
        let scriptContent = """
        #!/usr/bin/env bash
        # DeepSeek Harness Headless Task
        cd "\(repoRoot)"
        export PATH="\(pathEnv):$PATH"
        clear
        echo -e "\\033[1;36m===================================================\\033[0m"
        echo -e "\\033[1;36m  🤖 DeepSeek Harness — Headless Task Runner\\033[0m"
        echo -e "\\033[1;36m===================================================\\033[0m"
        echo "Task: \(task)"
        echo "DSH Folder: \(repoRoot)"
        echo "---------------------------------------------------"
        echo ""
        pnpm dsh --profile headless "\(escapedTask)"
        echo ""
        echo "---------------------------------------------------"
        read -rp "Task finished. Press Enter to close..."
        """
        do {
            try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
            launchScriptInTerminal(scriptURL: tempScript)
        } catch {
            print("Error creating task command: \(error)")
        }
    }
    
    static func openInteractiveTerminal(repoRoot: String, pathEnv: String) {
        let tempScript = FileManager.default.temporaryDirectory.appendingPathComponent("dsh-session-\(ProcessInfo.processInfo.globallyUniqueString.prefix(8)).command")
        let scriptContent = """
        #!/usr/bin/env bash
        # DeepSeek Harness Terminal Session
        cd "\(repoRoot)"
        export PATH="\(pathEnv):$PATH"
        clear
        echo -e "\\033[1;36m===================================================\\033[0m"
        echo -e "\\033[1;36m  🐋 DeepSeek Harness — Interactive Terminal Session\\033[0m"
        echo -e "\\033[1;36m===================================================\\033[0m"
        echo "DSH Folder: \(repoRoot)"
        echo ""
        echo "Commands:"
        echo "  • pnpm dsh web                          # Start Web GUI"
        echo "  • pnpm dsh --profile headless \\"<task>\\"  # Run headless task"
        echo "  • pnpm dsh --help                       # All CLI options"
        echo ""
        exec "${SHELL:-/bin/zsh}" -l
        """
        do {
            try scriptContent.write(to: tempScript, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScript.path)
            launchScriptInTerminal(scriptURL: tempScript)
        } catch {
            print("Error creating terminal command: \(error)")
        }
    }
    
    private static func launchScriptInTerminal(scriptURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(scriptURL, configuration: config) { _, error in
            if error != nil {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                proc.arguments = ["-a", "Terminal", scriptURL.path]
                try? proc.run()
            }
        }
    }
}

// MARK: - UI Components & Windows

class LogWindowController: NSWindowController {
    static let shared = LogWindowController()
    
    private var textView: NSTextView!
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness - Live Logs"
        window.minSize = NSSize(width: 500, height: 300)
        window.center()
        self.init(window: window)
        
        setupUI()
    }
    
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }
        
        // Bottom Utility Toolbar (height 40)
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: 40))
        toolbar.autoresizingMask = [.width, .maxYMargin]
        contentView.addSubview(toolbar)
        
        let clearBtn = NSButton(title: "Clear", target: self, action: #selector(clearLogsClicked))
        clearBtn.bezelStyle = .rounded
        clearBtn.frame = NSRect(x: 10, y: 5, width: 80, height: 30)
        toolbar.addSubview(clearBtn)
        
        let copyBtn = NSButton(title: "Copy All", target: self, action: #selector(copyLogsClicked))
        copyBtn.bezelStyle = .rounded
        copyBtn.frame = NSRect(x: 95, y: 5, width: 90, height: 30)
        toolbar.addSubview(copyBtn)
        
        let openFileBtn = NSButton(title: "Open Log File", target: self, action: #selector(openLogFileClicked))
        openFileBtn.bezelStyle = .rounded
        openFileBtn.frame = NSRect(x: 190, y: 5, width: 120, height: 30)
        toolbar.addSubview(openFileBtn)
        
        let logPathLabel = NSTextField(labelWithString: "Log: ~/Library/Logs/DeepSeekHarness/dsh-web.log")
        logPathLabel.font = NSFont.systemFont(ofSize: 11)
        logPathLabel.textColor = .secondaryLabelColor
        logPathLabel.alignment = .right
        logPathLabel.frame = NSRect(x: 320, y: 10, width: contentView.bounds.width - 330, height: 20)
        logPathLabel.autoresizingMask = [.width, .minXMargin]
        toolbar.addSubview(logPathLabel)
        
        // ScrollView + TextView
        let scrollFrame = NSRect(x: 0, y: 40, width: contentView.bounds.width, height: contentView.bounds.height - 40)
        let scrollView = NSScrollView(frame: scrollFrame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        textView = NSTextView(frame: scrollView.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 1.0)
        textView.textColor = NSColor(red: 0.85, green: 0.9, blue: 0.95, alpha: 1.0)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        
        scrollView.documentView = textView
        contentView.addSubview(scrollView)
        
        reloadLogs()
        
        ServerManager.shared.onLogLine = { [weak self] line in
            DispatchQueue.main.async {
                self?.appendLog(line)
            }
        }
    }
    
    func reloadLogs() {
        guard textView != nil else { return }
        let fullText = ServerManager.shared.getLogText()
        textView.string = fullText
        textView.scrollToEndOfDocument(nil)
    }
    
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        reloadLogs()
    }
    
    func appendLog(_ text: String) {
        guard textView != nil else { return }
        let formatted = (textView.string.isEmpty ? "" : "\n") + text
        let attr = NSAttributedString(
            string: formatted,
            attributes: [
                .foregroundColor: NSColor(red: 0.85, green: 0.9, blue: 0.95, alpha: 1.0),
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ]
        )
        textView.textStorage?.append(attr)
        textView.scrollToEndOfDocument(nil)
    }
    
    @objc private func clearLogsClicked() {
        textView.string = ""
    }
    
    @objc private func copyLogsClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
    }
    
    @objc private func openLogFileClicked() {
        let logFilePath = Constants.logsDirectory.appendingPathComponent("dsh-web.log")
        if FileManager.default.fileExists(atPath: logFilePath.path) {
            NSWorkspace.shared.open(logFilePath)
        } else {
            let alert = NSAlert()
            alert.messageText = "No Log File"
            alert.informativeText = "The log file will be created when the server is started."
            alert.runModal()
        }
    }
}

class MainWindowController: NSWindowController {
    static let shared = MainWindowController()
    
    private var statusLabel: NSTextField!
    private var statusEmojiLabel: NSTextField!
    private var webButton: NSButton!
    private var openBrowserButton: NSButton!
    private var terminalButton: NSButton!
    private var taskButton: NSButton!
    private var logsButton: NSButton!
    private var repoPathLabel: NSTextField!
    private var launchCommandField: NSTextField!
    private var jobsTable: NSTableView!
    private var totalsLabel: NSTextField!
    private var haltButton: NSButton!
    /// Snapshot backing the table, so row indices stay stable between reloads.
    private var jobRows: [TaskMonitor.Task] = []
    private var iconImageView: NSImageView!
    private var whaleIconImage: NSImage!
    
    static func imageWithEmoji(_ emoji: String, size: NSSize = NSSize(width: 80, height: 80)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let str = NSString(string: emoji)
        let font = NSFont.systemFont(ofSize: size.height * 0.72)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let strSize = str.size(withAttributes: attrs)
        let rect = NSRect(
            x: (size.width - strSize.width) / 2,
            y: (size.height - strSize.height) / 2,
            width: strSize.width,
            height: strSize.height
        )
        str.draw(in: rect, withAttributes: attrs)
        image.unlockFocus()
        return image
    }
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = Constants.windowTitle
        window.center()
        self.init(window: window)
        
        setupUI()
        
        ServerManager.shared.addStatusListener { [weak self] status in
            self?.updateServerUI(status)
        }

        observeTaskMonitor()
        refreshJobs()
    }

    /// Installed once the window exists, so job rows track the monitor.
    func observeTaskMonitor() {
        let previous = TaskMonitor.shared.onChange
        TaskMonitor.shared.onChange = { [weak self] counts in
            previous?(counts)
            DispatchQueue.main.async { self?.refreshJobs() }
        }
    }
    
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }
        
        let container = NSView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        contentView.addSubview(container)
        
        // Header Title & Version Tag
        let titleLabel = NSTextField(labelWithString: "DeepSeek Harness Launcher")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.frame = NSRect(x: 30, y: 584, width: 335, height: 28)
        container.addSubview(titleLabel)
        
        let versionLabel = NSTextField(labelWithString: "v\(Constants.version)")
        versionLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.frame = NSRect(x: 368, y: 587, width: 75, height: 20)
        container.addSubview(versionLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "A minimal status-bar application for launching, restarting and controlling DeepSeek-Harness, written in Swift")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.frame = NSRect(x: 30, y: 550, width: 410, height: 32)
        container.addSubview(subtitleLabel)
        
        // Load whale icon
        if let appIcon = NSImage(named: "AppIcon") {
            whaleIconImage = appIcon
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                  let iconImage = NSImage(contentsOf: iconURL) {
            whaleIconImage = iconImage
        } else if let pngURL = Bundle.main.url(forResource: "whale-harness", withExtension: "png"),
                  let pngImage = NSImage(contentsOf: pngURL) {
            whaleIconImage = pngImage
        } else if let localIcon = NSImage(contentsOfFile: "\(EnvironmentManager.shared.repoRoot)/resources/AppIcon.icns") {
            whaleIconImage = localIcon
        } else {
            whaleIconImage = NSApp.applicationIconImage
        }
        
        // Header Icon Picture (~160 retina pixels = 80x80 pt, right-aligned to border)
        iconImageView = NSImageView(frame: NSRect(x: 450, y: 552, width: 80, height: 80))
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.image = whaleIconImage
        container.addSubview(iconImageView)
        
        // Status Card Box
        let statusCard = NSBox(frame: NSRect(x: 30, y: 465, width: 500, height: 75))
        statusCard.titlePosition = .noTitle
        statusCard.boxType = .custom
        statusCard.cornerRadius = 10
        statusCard.borderWidth = 1
        statusCard.borderColor = NSColor.separatorColor
        statusCard.fillColor = NSColor.controlBackgroundColor
        container.addSubview(statusCard)
        
        statusEmojiLabel = NSTextField(labelWithString: "🦑")
        statusEmojiLabel.font = NSFont.systemFont(ofSize: 15)
        statusEmojiLabel.isBezeled = false
        statusEmojiLabel.drawsBackground = false
        statusEmojiLabel.isEditable = false
        statusEmojiLabel.isSelectable = false
        statusEmojiLabel.frame = NSRect(x: 18, y: 35, width: 22, height: 20)
        statusCard.contentView?.addSubview(statusEmojiLabel)
        
        statusLabel = NSTextField(labelWithString: "Web Server: Stopped")
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        statusLabel.frame = NSRect(x: 44, y: 35, width: 308, height: 20)
        statusCard.contentView?.addSubview(statusLabel)
        
        repoPathLabel = NSTextField(labelWithString: "DSH Folder: \(EnvironmentManager.shared.repoRoot)")
        repoPathLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        repoPathLabel.textColor = .secondaryLabelColor
        repoPathLabel.lineBreakMode = .byTruncatingMiddle
        repoPathLabel.frame = NSRect(x: 20, y: 12, width: 380, height: 16)
        statusCard.contentView?.addSubview(repoPathLabel)
        
        let changeFolderButton = NSButton(title: "Change...", target: self, action: #selector(chooseFolderClicked))
        changeFolderButton.bezelStyle = .inline
        changeFolderButton.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        changeFolderButton.frame = NSRect(x: 410, y: 10, width: 75, height: 20)
        statusCard.contentView?.addSubview(changeFolderButton)
        
        openBrowserButton = NSButton(title: "Open Browser", target: self, action: #selector(openBrowserClicked))
        openBrowserButton.bezelStyle = .rounded
        openBrowserButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        openBrowserButton.frame = NSRect(x: 360, y: 30, width: 125, height: 30)
        openBrowserButton.isHidden = true
        statusCard.contentView?.addSubview(openBrowserButton)
        
        // Jobs section: live task list with aggregate usage.
        let jobsHeader = NSTextField(labelWithString: "Jobs")
        jobsHeader.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        jobsHeader.frame = NSRect(x: 30, y: 437, width: 120, height: 18)
        container.addSubview(jobsHeader)

        totalsLabel = NSTextField(labelWithString: "")
        totalsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        totalsLabel.textColor = .secondaryLabelColor
        totalsLabel.alignment = .right
        totalsLabel.frame = NSRect(x: 240, y: 438, width: 290, height: 16)
        container.addSubview(totalsLabel)

        let jobsScroll = NSScrollView(frame: NSRect(x: 30, y: 262, width: 500, height: 168))
        jobsScroll.hasVerticalScroller = true
        jobsScroll.borderType = .bezelBorder
        jobsScroll.autohidesScrollers = true

        jobsTable = NSTableView(frame: jobsScroll.bounds)
        jobsTable.usesAlternatingRowBackgroundColors = true
        jobsTable.rowHeight = 22
        jobsTable.allowsMultipleSelection = false
        jobsTable.dataSource = self
        jobsTable.delegate = self
        jobsTable.headerView = NSTableHeaderView()

        let stateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state"))
        stateColumn.title = "State"
        stateColumn.width = 74
        jobsTable.addTableColumn(stateColumn)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Job"
        nameColumn.width = 268
        jobsTable.addTableColumn(nameColumn)

        let tokensColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tokens"))
        tokensColumn.title = "Tokens"
        tokensColumn.width = 130
        jobsTable.addTableColumn(tokensColumn)

        jobsScroll.documentView = jobsTable
        container.addSubview(jobsScroll)

        haltButton = NSButton(title: "Halt Job", target: self, action: #selector(haltSelectedJobClicked))
        haltButton.bezelStyle = .rounded
        haltButton.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        haltButton.frame = NSRect(x: 30, y: 232, width: 100, height: 24)
        haltButton.isEnabled = false
        container.addSubview(haltButton)

        let haltHint = NSTextField(labelWithString: "Select a running job to halt its active turn.")
        haltHint.font = NSFont.systemFont(ofSize: 11)
        haltHint.textColor = .tertiaryLabelColor
        haltHint.frame = NSRect(x: 140, y: 236, width: 390, height: 16)
        container.addSubview(haltHint)

        // Primary Action Buttons
        let buttonY = 190
        
        webButton = NSButton(title: "Start Web GUI", target: self, action: #selector(toggleWebServerClicked))
        webButton.bezelStyle = .rounded
        webButton.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        webButton.frame = NSRect(x: 30, y: buttonY, width: 240, height: 42)
        container.addSubview(webButton)
        
        terminalButton = NSButton(title: "Terminal Session", target: self, action: #selector(openTerminalClicked))
        terminalButton.bezelStyle = .rounded
        terminalButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        terminalButton.frame = NSRect(x: 290, y: buttonY, width: 240, height: 42)
        container.addSubview(terminalButton)
        
        taskButton = NSButton(title: "Run Headless Task...", target: self, action: #selector(runTaskClicked))
        taskButton.bezelStyle = .rounded
        taskButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        taskButton.frame = NSRect(x: 30, y: buttonY - 55, width: 240, height: 42)
        container.addSubview(taskButton)
        
        logsButton = NSButton(title: "View Live Logs", target: self, action: #selector(viewLogsClicked))
        logsButton.bezelStyle = .rounded
        logsButton.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        logsButton.frame = NSRect(x: 290, y: buttonY - 55, width: 240, height: 42)
        container.addSubview(logsButton)
        
        // Launch Command Card: shows and edits the exact server start command.
        let commandCard = NSBox(frame: NSRect(x: 30, y: 62, width: 500, height: 66))
        commandCard.titlePosition = .noTitle
        commandCard.boxType = .custom
        commandCard.cornerRadius = 10
        commandCard.borderWidth = 1
        commandCard.borderColor = NSColor.separatorColor
        commandCard.fillColor = NSColor.controlBackgroundColor
        container.addSubview(commandCard)
        
        let commandLabel = NSTextField(labelWithString: "Launch Command")
        commandLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        commandLabel.frame = NSRect(x: 14, y: 42, width: 120, height: 14)
        commandCard.contentView?.addSubview(commandLabel)
        
        let commandHint = NSTextField(labelWithString: "Runs in the DSH folder on Start · saved across reboots")
        commandHint.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        commandHint.textColor = .tertiaryLabelColor
        commandHint.alignment = .right
        commandHint.frame = NSRect(x: 140, y: 43, width: 344, height: 14)
        commandCard.contentView?.addSubview(commandHint)
        
        launchCommandField = NSTextField(string: ServerManager.shared.launchCommand)
        launchCommandField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        launchCommandField.frame = NSRect(x: 14, y: 10, width: 352, height: 24)
        launchCommandField.lineBreakMode = .byTruncatingHead
        launchCommandField.toolTip = "The exact command executed to start the server, relative to the DSH folder. The first word is resolved via your PATH (e.g. pnpm, node, or an absolute path). Shell operators like && are not supported. Takes effect on the next Start."
        commandCard.contentView?.addSubview(launchCommandField)
        
        let saveCommandButton = NSButton(title: "Save", target: self, action: #selector(saveLaunchCommandClicked))
        saveCommandButton.bezelStyle = .rounded
        saveCommandButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        saveCommandButton.frame = NSRect(x: 374, y: 10, width: 54, height: 24)
        commandCard.contentView?.addSubview(saveCommandButton)
        
        let resetCommandButton = NSButton(title: "Reset", target: self, action: #selector(resetLaunchCommandClicked))
        resetCommandButton.bezelStyle = .rounded
        resetCommandButton.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        resetCommandButton.frame = NSRect(x: 432, y: 10, width: 54, height: 24)
        commandCard.contentView?.addSubview(resetCommandButton)
        
        // Author Credit Link (above separator)
        let creditField = NSTextField(labelWithString: "made by deep-blue-dark-red")
        creditField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        creditField.textColor = .secondaryLabelColor
        creditField.isSelectable = true
        creditField.isBordered = false
        creditField.drawsBackground = false
        creditField.frame = NSRect(x: 30, y: 24, width: 340, height: 16)
        let creditAttr = NSMutableAttributedString(
            string: "made by deep-blue-dark-red",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .link: Constants.authorUrl]
        )
        creditField.attributedStringValue = creditAttr
        
        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(openAuthorUrlClicked))
        creditField.addGestureRecognizer(clickRecognizer)
        container.addSubview(creditField)
        
        // Bottom Utility Bar
        let separator = NSBox(frame: NSRect(x: 30, y: 54, width: 500, height: 1))
        separator.boxType = .separator
        container.addSubview(separator)
        
        let docsButton = NSButton(title: "Docs & Guides", target: self, action: #selector(openDocsClicked))
        docsButton.bezelStyle = .inline
        docsButton.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        docsButton.frame = NSRect(x: 400, y: 20, width: 130, height: 28)
        container.addSubview(docsButton)
    }
    
    private func updateServerUI(_ status: ServerStatus) {
        // The jobs panel's wording depends on server state, so keep it in step.
        refreshJobs()

        switch status {
        case .stopped:
            statusEmojiLabel.stringValue = "🦑"
            statusLabel.stringValue = "Web Server: Stopped"
            statusLabel.textColor = .labelColor
            webButton.title = "Start Web GUI"
            webButton.isEnabled = true
            openBrowserButton.isHidden = true
        case .starting:
            statusEmojiLabel.stringValue = "🐡"
            statusLabel.stringValue = "Web Server: Starting..."
            statusLabel.textColor = .systemYellow
            // Stays enabled: a startup that stalls must still be cancellable.
            webButton.title = "Cancel Start"
            webButton.isEnabled = true
            openBrowserButton.isHidden = true
        case .running(_):
            statusEmojiLabel.stringValue = "🐋"
            statusLabel.stringValue = "Web Server: Running"
            statusLabel.textColor = .systemBlue
            webButton.title = "Stop Web Server"
            webButton.isEnabled = true
            openBrowserButton.isHidden = false
        case .error(let message):
            statusEmojiLabel.stringValue = "🦑"
            statusLabel.stringValue = "Error: \(message)"
            statusLabel.textColor = .systemRed
            webButton.title = "Retry Web GUI"
            webButton.isEnabled = true
            openBrowserButton.isHidden = true
        }
    }
    
    @objc private func toggleWebServerClicked() {
        switch ServerManager.shared.status {
        case .running, .starting:
            ServerManager.shared.stopWebServer()
        case .stopped, .error:
            ServerManager.shared.startWebServer()
        }
    }

    @objc private func saveLaunchCommandClicked() {
        ServerManager.shared.setLaunchCommand(launchCommandField.stringValue)
        launchCommandField.stringValue = ServerManager.shared.launchCommand
    }

    @objc private func resetLaunchCommandClicked() {
        launchCommandField.stringValue = Constants.defaultLaunchCommand
        ServerManager.shared.setLaunchCommand(Constants.defaultLaunchCommand)
    }
    
    @objc private func openBrowserClicked() {
        ServerManager.shared.openInBrowser()
    }
    
    @objc private func openTerminalClicked() {
        let env = EnvironmentManager.shared
        HeadlessRunner.openInteractiveTerminal(repoRoot: env.repoRoot, pathEnv: env.pathEnvironment)
    }
    
    @objc private func runTaskClicked() {
        let alert = NSAlert()
        alert.messageText = "Run Headless Task"
        alert.informativeText = "Enter task description to run headless with DeepSeek Harness:"
        alert.addButton(withTitle: "Run Task")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "e.g. Find all TODO comments in packages/core"
        alert.accessoryView = input
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let task = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !task.isEmpty {
                let env = EnvironmentManager.shared
                HeadlessRunner.runTaskInTerminal(task: task, repoRoot: env.repoRoot, pathEnv: env.pathEnvironment)
            }
        }
    }
    
    @objc private func viewLogsClicked() {
        LogWindowController.shared.showWindow(nil)
        LogWindowController.shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Repopulates the jobs table and the aggregate usage line.
    func refreshJobs() {
        guard jobsTable != nil else { return }
        let monitor = TaskMonitor.shared
        let selectedId = jobsTable.selectedRow >= 0 && jobsTable.selectedRow < jobRows.count
            ? jobRows[jobsTable.selectedRow].sessionId
            : nil

        jobRows = monitor.orderedTasks(limit: 200)
        jobsTable.reloadData()

        if let selectedId = selectedId,
           let row = jobRows.firstIndex(where: { $0.sessionId == selectedId }) {
            jobsTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        updateHaltButton()

        let usage = monitor.totalUsage
        if monitor.isAvailable {
            let counts = monitor.counts
            totalsLabel.stringValue = "\(counts.total) job(s)   ↓ \(AppDelegate.abbreviateTokens(usage.input)) in   ↑ \(AppDelegate.abbreviateTokens(usage.output)) out"
        } else {
            switch ServerManager.shared.status {
            case .running: totalsLabel.stringValue = "Connecting to the harness API…"
            case .starting: totalsLabel.stringValue = "Server starting…"
            case .stopped, .error: totalsLabel.stringValue = "Server not running"
            }
        }
    }

    private func updateHaltButton() {
        let row = jobsTable.selectedRow
        haltButton.isEnabled = row >= 0 && row < jobRows.count && jobRows[row].outcome.isRunning
    }

    @objc private func haltSelectedJobClicked() {
        let row = jobsTable.selectedRow
        guard row >= 0, row < jobRows.count else { return }
        let job = jobRows[row]

        let alert = NSAlert()
        alert.messageText = "Halt this job?"
        alert.informativeText = "\"\(job.shortName)\" will have its active turn cancelled. Work already done is kept."
        alert.addButton(withTitle: "Halt")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        TaskMonitor.shared.halt(sessionId: job.sessionId)
    }

    @objc private func openDocsClicked() {
        if let url = URL(string: Constants.githubUrl) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openAuthorUrlClicked() {
        if let url = URL(string: Constants.authorUrl) {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func chooseFolderClicked() {
        let panel = NSOpenPanel()
        panel.title = "Select DeepSeek-Harness Folder"
        panel.message = "Choose the directory where your deepseek-harness repository is located:"
        panel.prompt = "Select Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = URL(fileURLWithPath: EnvironmentManager.shared.repoRoot)
        
        if panel.runModal() == .OK, let url = panel.url {
            let newPath = url.path
            EnvironmentManager.shared.setRepoRoot(newPath)
            repoPathLabel.stringValue = "DSH Folder: \(newPath)"
            
            if case .running = ServerManager.shared.status {
                let alert = NSAlert()
                alert.messageText = "DSH Folder Updated"
                alert.informativeText = "DeepSeek-Harness folder has been changed to:\n\(newPath)\n\nPlease restart the web server to apply the change."
                alert.runModal()
            }
        }
    }
    
}

// MARK: - Jobs Table

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { jobRows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < jobRows.count, let column = tableColumn else { return nil }
        let job = jobRows[row]

        let text: String
        var monospaced = false
        switch column.identifier.rawValue {
        case "state":
            text = job.outcome.marker + " " + MainWindowController.stateLabel(job.outcome)
        case "name":
            let reason = job.outcome.reason.map { " (\($0))" } ?? ""
            text = job.shortName + reason
        default:
            text = "↓ \(AppDelegate.abbreviateTokens(job.usage.input))  ↑ \(AppDelegate.abbreviateTokens(job.usage.output))"
            monospaced = true
        }

        let field = NSTextField(labelWithString: text)
        field.font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            : NSFont.systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        field.toolTip = job.cwd
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateHaltButton()
    }

    static func stateLabel(_ outcome: TaskMonitor.Outcome) -> String {
        switch outcome {
        case .running: return "Running"
        case .done: return "Done"
        case .paused: return "Paused"
        case .blocked: return "Blocked"
        case .halted: return "Halted"
        }
    }
}

// MARK: - App Delegate & Menu Bar Integration

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshStatusPresentation()
    }

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var startWebItem: NSMenuItem?
    /// Separator closing the summary section, so its rows can be rebuilt in place.
    private var summarySectionEnd: NSMenuItem?
    private var summaryMenuItems: [NSMenuItem] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        MainWindowController.shared.showWindow(nil)
        MainWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "🦑"
        }
        
        statusMenu = NSMenu()
        
        // Summary statistics and task rows are rebuilt in place above this
        // separator. Everything below it is fixed.
        summarySectionEnd = NSMenuItem.separator()
        summarySectionEnd.map { statusMenu.addItem($0) }
        
        // Opening the browser is the action that actually gets used, so it leads.
        let browserItem = NSMenuItem(title: "Open Browser", action: #selector(openBrowserFromMenu), keyEquivalent: "b")
        browserItem.target = self
        statusMenu.addItem(browserItem)

        let openGuiItem = NSMenuItem(title: "Control Panel", action: #selector(showMainWindow), keyEquivalent: "o")
        openGuiItem.target = self
        statusMenu.addItem(openGuiItem)
        
        let startWebItem = NSMenuItem(title: "Start Web Server", action: #selector(toggleServerFromMenu), keyEquivalent: "s")
        startWebItem.target = self
        statusMenu.addItem(startWebItem)
        
        
        let terminalItem = NSMenuItem(title: "Open Terminal Session", action: #selector(openTerminalFromMenu), keyEquivalent: "t")
        terminalItem.target = self
        statusMenu.addItem(terminalItem)
        
        let logsItem = NSMenuItem(title: "View Live Logs", action: #selector(showLogsWindow), keyEquivalent: "l")
        logsItem.target = self
        statusMenu.addItem(logsItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit DeepSeek Harness Launcher", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
        
        // Rebuild on open so the rows are never a stale snapshot, whatever the
        // polling cadence happens to be.
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        
        self.startWebItem = startWebItem

        ServerManager.shared.addStatusListener { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatusPresentation() }
        }

        TaskMonitor.shared.onChange = { [weak self] _ in
            DispatchQueue.main.async { self?.refreshStatusPresentation() }
        }
    }

    /// Builds the status-item badge.
    ///
    /// While the server runs the badge reads `<whale> <completed>|<total>`, with
    /// 🐋 when any task is live and 🐳 when all are idle, plus a trailing `🐠<n>`
    /// for tasks that stopped for any reason other than completing.
    static func statusTitle(for status: ServerStatus, counts: TaskCounts) -> String {
        switch status {
        case .stopped, .error:
            return "🦑"
        case .starting:
            return "🐡"
        case .running:
            guard !counts.isEmpty else { return "🐳" }
            let whale = counts.running > 0 ? "🐋" : "🐳"
            let badge = "\(whale) \(counts.completed)|\(counts.total)"
            return counts.halted > 0 ? "\(badge) 🐠\(counts.halted)" : badge
        }
    }

    private func refreshStatusPresentation() {
        let status = ServerManager.shared.status
        statusItem.button?.title = AppDelegate.statusTitle(for: status, counts: TaskMonitor.shared.counts)

        switch status {
        case .running: startWebItem?.title = "Stop Web Server"
        case .starting: startWebItem?.title = "Cancel Start"
        case .stopped, .error: startWebItem?.title = "Start Web Server"
        }

        rebuildTaskSection()
    }

    /// Compact token count: 1234 -> "1.2k", 1234567 -> "1.2M".
    static func abbreviateTokens(_ value: Int) -> String {
        switch value {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return String(format: "%.1fk", Double(value) / 1_000)
        default: return String(format: "%.1fM", Double(value) / 1_000_000)
        }
    }

    /// A menu row with its trailing text right-aligned in a fixed column.
    private static func columnedTitle(_ leading: String, trailing: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 340)]
        return NSAttributedString(
            string: "\(leading)\t\(trailing)",
            attributes: [
                .paragraphStyle: paragraph,
                .font: NSFont.menuFont(ofSize: 13),
            ]
        )
    }

    /// Rebuilds the summary statistics and task rows above the first separator.
    private func rebuildTaskSection() {
        for item in summaryMenuItems where statusMenu.index(of: item) >= 0 {
            statusMenu.removeItem(item)
        }
        summaryMenuItems.removeAll()

        guard let end = summarySectionEnd, statusMenu.index(of: end) >= 0 else { return }
        var insertAt = 0

        func add(_ item: NSMenuItem) {
            statusMenu.insertItem(item, at: insertAt)
            summaryMenuItems.append(item)
            insertAt += 1
        }

        let monitor = TaskMonitor.shared
        let usage = monitor.totalUsage

        guard monitor.isAvailable else {
            // Report the server's actual state: "not running" was previously shown
            // even while it was up and the first poll had simply not landed.
            let text: String
            switch ServerManager.shared.status {
            case .running: text = "Connecting to the harness API…"
            case .starting: text = "Server starting…"
            case .stopped, .error: text = "Server not running"
            }
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            add(item)
            return
        }

        // Aggregate line: tokens this run. Cost and remaining credits are not
        // available from the harness (see README), so nothing is shown for them.
        let totals = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        totals.attributedTitle = AppDelegate.columnedTitle(
            "Session totals",
            trailing: "↓ \(AppDelegate.abbreviateTokens(usage.input))  ↑ \(AppDelegate.abbreviateTokens(usage.output))"
        )
        totals.isEnabled = false
        add(totals)

        let tasks = monitor.orderedTasks()
        guard !tasks.isEmpty else {
            let idle = NSMenuItem(title: "No tasks yet this run", action: nil, keyEquivalent: "")
            idle.isEnabled = false
            add(idle)
            return
        }

        for task in tasks {
            let reason = task.outcome.reason.map { " (\($0))" } ?? ""
            let leading = "\(task.outcome.marker) \(task.shortName)\(reason)"
            let trailing = "↓ \(AppDelegate.abbreviateTokens(task.usage.input))  ↑ \(AppDelegate.abbreviateTokens(task.usage.output))"

            let item = NSMenuItem(title: "", action: #selector(openBrowserFromMenu), keyEquivalent: "")
            item.attributedTitle = AppDelegate.columnedTitle(leading, trailing: trailing)
            item.target = self
            item.toolTip = task.cwd
            add(item)
        }
    }
    
    @objc private func showMainWindow() {
        MainWindowController.shared.showWindow(nil)
        MainWindowController.shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func toggleServerFromMenu() {
        switch ServerManager.shared.status {
        case .running, .starting:
            ServerManager.shared.stopWebServer()
        case .stopped, .error:
            ServerManager.shared.startWebServer()
        }
    }
    
    @objc private func openBrowserFromMenu() {
        ServerManager.shared.openInBrowser()
    }
    
    @objc private func openTerminalFromMenu() {
        let env = EnvironmentManager.shared
        HeadlessRunner.openInteractiveTerminal(repoRoot: env.repoRoot, pathEnv: env.pathEnvironment)
    }
    
    @objc private func showLogsWindow() {
        LogWindowController.shared.showWindow(nil)
        LogWindowController.shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        ServerManager.shared.stopWebServer()
        ServerManager.killLingeringServerProcesses()
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ServerManager.shared.stopWebServer()
        ServerManager.killLingeringServerProcesses()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
