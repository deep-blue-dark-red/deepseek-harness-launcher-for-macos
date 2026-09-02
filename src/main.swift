import Cocoa
import Foundation

// MARK: - Constants & Configuration

struct Constants {
    static let appName = "DeepSeek Harness"
    static let bundleIdentifier = "com.deepseek.harness"
    static let defaultPort = "5173"
    static let defaultProfile = "web"
    static let githubUrl = "https://github.com/deepseek-ai/deepseek-harness"
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
        var paths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append("\(home)/.local/bin")
        paths.append("\(home)/.cargo/bin")
        paths.append("\(home)/.proto/shims")
        paths.append("\(home)/.proto/bin")
        paths.append("\(home)/.asdf/shims")
        paths.append("\(home)/.asdf/bin")
        paths.append("\(home)/.fnm/current/bin")
        paths.append("\(home)/.volta/bin")
        
        let nvmDir = "\(home)/.nvm/versions/node"
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            let sorted = contents.sorted().reversed()
            for version in sorted {
                paths.append("\(nvmDir)/\(version)/bin")
            }
        }
        
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        if (try? process.run()) != nil {
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let shellPath = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let parts = shellPath.components(separatedBy: ":")
                    for p in parts where !paths.contains(p) && !p.isEmpty {
                        paths.insert(p, at: 0)
                    }
                }
            }
        }
        
        return paths.joined(separator: ":")
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
        
        return cwd
    }
    
    func setRepoRoot(_ newPath: String) {
        self.repoRoot = newPath
        UserDefaults.standard.set(newPath, forKey: "DSH_REPO_ROOT")
    }
    
    func getApiKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !key.isEmpty {
            return key
        }
        
        let envPath = "\(repoRoot)/.env"
        if let contents = try? String(contentsOfFile: envPath, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("DEEPSEEK_API_KEY=") {
                    let value = String(trimmed.dropFirst("DEEPSEEK_API_KEY=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t "))
                    if !value.isEmpty { return value }
                }
            }
        }
        
        let homeEnv = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.dsh/.env"
        if let contents = try? String(contentsOfFile: homeEnv, encoding: .utf8) {
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("DEEPSEEK_API_KEY=") {
                    let value = String(trimmed.dropFirst("DEEPSEEK_API_KEY=".count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'\t "))
                    if !value.isEmpty { return value }
                }
            }
        }
        
        return nil
    }
    
    func saveApiKey(_ key: String) -> Bool {
        let dshDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.dsh"
        try? FileManager.default.createDirectory(atPath: dshDir, withIntermediateDirectories: true)
        
        let envPath = "\(dshDir)/.env"
        var lines: [String] = []
        if let contents = try? String(contentsOfFile: envPath, encoding: .utf8) {
            lines = contents.components(separatedBy: .newlines).filter {
                !$0.trimmingCharacters(in: .whitespaces).hasPrefix("DEEPSEEK_API_KEY=")
            }
        }
        lines.append("DEEPSEEK_API_KEY=\(key)")
        let output = lines.joined(separator: "\n") + "\n"
        
        do {
            try output.write(toFile: envPath, atomically: true, encoding: String.Encoding.utf8)
            let repoEnv = "\(repoRoot)/.env"
            if FileManager.default.fileExists(atPath: repoEnv) {
                var repoLines: [String] = []
                if let repoContents = try? String(contentsOfFile: repoEnv, encoding: .utf8) {
                    repoLines = repoContents.components(separatedBy: .newlines).filter {
                        !$0.trimmingCharacters(in: .whitespaces).hasPrefix("DEEPSEEK_API_KEY=")
                    }
                }
                repoLines.append("DEEPSEEK_API_KEY=\(key)")
                try? (repoLines.joined(separator: "\n") + "\n").write(toFile: repoEnv, atomically: true, encoding: String.Encoding.utf8)
            }
            return true
        } catch {
            return false
        }
    }
    
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
    
    private(set) var status: ServerStatus = .stopped {
        didSet {
            DispatchQueue.main.async {
                self.onStatusChange?(self.status)
            }
        }
    }
    
    var onStatusChange: ((ServerStatus) -> Void)?
    var onLogLine: ((String) -> Void)?
    
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var logFileHandle: FileHandle?
    private(set) var currentWebUrl: String?
    
    func startWebServer(port: String = Constants.defaultPort) {
        guard case .stopped = status else { return }
        
        let env = EnvironmentManager.shared
        guard let pnpm = env.pnpmPath else {
            self.status = .error(message: "pnpm not found in PATH. Please install Node.js and pnpm.")
            return
        }
        
        guard env.getApiKey() != nil else {
            self.status = .error(message: "DEEPSEEK_API_KEY is not configured.")
            return
        }
        
        self.status = .starting
        self.currentWebUrl = nil
        
        let logFilePath = Constants.logsDirectory.appendingPathComponent("dsh-web.log")
        FileManager.default.createFile(atPath: logFilePath.path, contents: nil)
        self.logFileHandle = try? FileHandle(forWritingTo: logFilePath)
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pnpm)
        proc.currentDirectoryURL = URL(fileURLWithPath: env.repoRoot)
        
        var procArgs = ["dsh", "web"]
        if !port.isEmpty && port != "default" && port != "5173" {
            procArgs.append(contentsOf: ["--port", port])
        }
        proc.arguments = procArgs
        
        var procEnv = ProcessInfo.processInfo.environment
        procEnv["PATH"] = env.pathEnvironment
        if let key = env.getApiKey() {
            procEnv["DEEPSEEK_API_KEY"] = key
        }
        proc.environment = procEnv
        
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.stdoutPipe = pipe
        self.process = proc
        
        let outHandle = pipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            
            self.logFileHandle?.write(data)
            
            if let text = String(data: data, encoding: .utf8) {
                let lines = text.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    self.onLogLine?(line)
                    self.parseOutputLine(line)
                }
            }
        }
        
        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
                self.logFileHandle?.closeFile()
                self.logFileHandle = nil
                self.process = nil
                self.status = .stopped
            }
        }
        
        do {
            try proc.run()
        } catch {
            self.status = .error(message: "Failed to start process: \(error.localizedDescription)")
        }
    }
    
    private func parseOutputLine(_ line: String) {
        if line.contains("http://127.0.0.1") || line.contains("http://localhost") {
            let parts = line.components(separatedBy: .whitespaces)
            for part in parts {
                if let url = URL(string: part), (url.scheme == "http" || url.scheme == "https"),
                   url.host == "127.0.0.1" || url.host == "localhost" {
                    DispatchQueue.main.async {
                        self.currentWebUrl = url.absoluteString
                        self.status = .running(url: url.absoluteString)
                    }
                    return
                }
            }
        }
    }
    
    func stopWebServer() {
        guard let proc = process, proc.isRunning else {
            self.status = .stopped
            return
        }
        
        proc.terminate()
        DispatchQueue.global().async {
            for _ in 0..<20 {
                if !proc.isRunning { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
            DispatchQueue.main.async {
                self.status = .stopped
            }
        }
    }
    
    func openInBrowser() {
        if let urlStr = currentWebUrl, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "http://127.0.0.1:5173") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Headless Task Runner

class HeadlessRunner {
    static func runTaskInTerminal(task: String, repoRoot: String, pathEnv: String) {
        let escapedTask = task.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(repoRoot)' && export PATH='\(pathEnv)':$PATH && pnpm dsh --profile headless '\(escapedTask)'"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
            }
        }
    }
    
    static func openInteractiveTerminal(repoRoot: String, pathEnv: String) {
        let script = """
        tell application "Terminal"
            activate
            do script "cd '\(repoRoot)' && export PATH='\(pathEnv)':$PATH && echo '🤖 DeepSeek Harness Environment Ready' && echo 'Commands: pnpm dsh web | pnpm dsh --profile headless \"<task>\" | pnpm dsh --help' && echo ''"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript error: \(error)")
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
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DeepSeek Harness - Live Logs"
        window.center()
        self.init(window: window)
        
        setupUI()
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
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
        textView.textContainerInset = NSSize(width: 10, height: 10)
        
        scrollView.documentView = textView
        window.contentView?.addSubview(scrollView)
        
        ServerManager.shared.onLogLine = { [weak self] line in
            DispatchQueue.main.async {
                self?.appendLog(line)
            }
        }
    }
    
    func appendLog(_ text: String) {
        let formatted = text + "\n"
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
    
    func clearLogs() {
        textView.string = ""
    }
}

class MainWindowController: NSWindowController {
    static let shared = MainWindowController()
    
    private var statusLabel: NSTextField!
    private var statusDot: NSBox!
    private var webButton: NSButton!
    private var openBrowserButton: NSButton!
    private var terminalButton: NSButton!
    private var taskButton: NSButton!
    private var logsButton: NSButton!
    private var settingsButton: NSButton!
    private var repoPathLabel: NSTextField!
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = Constants.appName
        window.center()
        self.init(window: window)
        
        setupUI()
        updateServerUI(ServerManager.shared.status)
        
        ServerManager.shared.onStatusChange = { [weak self] status in
            self?.updateServerUI(status)
        }
    }
    
    private func setupUI() {
        guard let window = window, let contentView = window.contentView else { return }
        
        let container = NSView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        contentView.addSubview(container)
        
        // Header Title
        let titleLabel = NSTextField(labelWithString: "DeepSeek Harness")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.frame = NSRect(x: 30, y: 370, width: 350, height: 30)
        container.addSubview(titleLabel)
        
        let subtitleLabel = NSTextField(labelWithString: "All-Plugin Cordis Agent Harness for macOS")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 30, y: 348, width: 400, height: 18)
        container.addSubview(subtitleLabel)
        
        // Status Card Box
        let statusCard = NSBox(frame: NSRect(x: 30, y: 260, width: 500, height: 75))
        statusCard.titlePosition = .noTitle
        statusCard.boxType = .custom
        statusCard.cornerRadius = 10
        statusCard.borderWidth = 1
        statusCard.borderColor = NSColor.separatorColor
        statusCard.fillColor = NSColor.controlBackgroundColor
        container.addSubview(statusCard)
        
        statusDot = NSBox(frame: NSRect(x: 20, y: 38, width: 12, height: 12))
        statusDot.boxType = .custom
        statusDot.cornerRadius = 6
        statusDot.borderWidth = 0
        statusDot.fillColor = NSColor.systemGray
        statusCard.contentView?.addSubview(statusDot)
        
        statusLabel = NSTextField(labelWithString: "Web Server: Stopped")
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        statusLabel.frame = NSRect(x: 42, y: 35, width: 310, height: 20)
        statusCard.contentView?.addSubview(statusLabel)
        
        repoPathLabel = NSTextField(labelWithString: "Workspace: \(EnvironmentManager.shared.repoRoot)")
        repoPathLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        repoPathLabel.textColor = .secondaryLabelColor
        repoPathLabel.lineBreakMode = .byTruncatingMiddle
        repoPathLabel.frame = NSRect(x: 20, y: 12, width: 460, height: 16)
        statusCard.contentView?.addSubview(repoPathLabel)
        
        openBrowserButton = NSButton(title: "Open Browser", target: self, action: #selector(openBrowserClicked))
        openBrowserButton.bezelStyle = .rounded
        openBrowserButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        openBrowserButton.frame = NSRect(x: 360, y: 30, width: 125, height: 30)
        openBrowserButton.isHidden = true
        statusCard.contentView?.addSubview(openBrowserButton)
        
        // Primary Action Buttons
        let buttonY = 195
        
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
        
        // Bottom Utility Bar
        let separator = NSBox(frame: NSRect(x: 30, y: 70, width: 500, height: 1))
        separator.boxType = .separator
        container.addSubview(separator)
        
        settingsButton = NSButton(title: "Configure API Key / Settings", target: self, action: #selector(openSettingsClicked))
        settingsButton.bezelStyle = .inline
        settingsButton.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        settingsButton.frame = NSRect(x: 30, y: 25, width: 220, height: 28)
        container.addSubview(settingsButton)
        
        let docsButton = NSButton(title: "Docs & Guides", target: self, action: #selector(openDocsClicked))
        docsButton.bezelStyle = .inline
        docsButton.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        docsButton.frame = NSRect(x: 400, y: 25, width: 130, height: 28)
        container.addSubview(docsButton)
    }
    
    private func updateServerUI(_ status: ServerStatus) {
        switch status {
        case .stopped:
            statusDot.fillColor = NSColor.systemGray
            statusLabel.stringValue = "Web Server: Stopped"
            statusLabel.textColor = .labelColor
            webButton.title = "Start Web GUI"
            webButton.isEnabled = true
            openBrowserButton.isHidden = true
        case .starting:
            statusDot.fillColor = NSColor.systemYellow
            statusLabel.stringValue = "Web Server: Starting..."
            statusLabel.textColor = .systemYellow
            webButton.title = "Starting..."
            webButton.isEnabled = false
            openBrowserButton.isHidden = true
        case .running(_):
            statusDot.fillColor = NSColor.systemGreen
            statusLabel.stringValue = "Web Server: Running"
            statusLabel.textColor = .systemGreen
            webButton.title = "Stop Web Server"
            webButton.isEnabled = true
            openBrowserButton.isHidden = false
        case .error(let message):
            statusDot.fillColor = NSColor.systemRed
            statusLabel.stringValue = "Error: \(message)"
            statusLabel.textColor = .systemRed
            webButton.title = "Retry Web GUI"
            webButton.isEnabled = true
            openBrowserButton.isHidden = true
        }
    }
    
    @objc private func toggleWebServerClicked() {
        let env = EnvironmentManager.shared
        if env.getApiKey() == nil {
            promptForApiKey()
            return
        }
        
        if case .running = ServerManager.shared.status {
            ServerManager.shared.stopWebServer()
        } else {
            ServerManager.shared.startWebServer()
        }
    }
    
    @objc private func openBrowserClicked() {
        ServerManager.shared.openInBrowser()
    }
    
    @objc private func openTerminalClicked() {
        let env = EnvironmentManager.shared
        HeadlessRunner.openInteractiveTerminal(repoRoot: env.repoRoot, pathEnv: env.pathEnvironment)
    }
    
    @objc private func runTaskClicked() {
        let env = EnvironmentManager.shared
        if env.getApiKey() == nil {
            promptForApiKey()
            return
        }
        
        let alert = NSAlert()
        alert.messageText = "Run Headless Task"
        alert.informativeText = "Enter a task instruction for DeepSeek Harness:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Run Task")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 60))
        input.placeholderString = "e.g. explain the architecture of packages/core or run the tests"
        alert.accessoryView = input
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let taskText = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !taskText.isEmpty {
                HeadlessRunner.runTaskInTerminal(task: taskText, repoRoot: env.repoRoot, pathEnv: env.pathEnvironment)
            }
        }
    }
    
    @objc private func viewLogsClicked() {
        LogWindowController.shared.showWindow(nil)
        LogWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }
    
    @objc private func openSettingsClicked() {
        promptForApiKey()
    }
    
    @objc private func openDocsClicked() {
        if let url = URL(string: Constants.githubUrl) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func promptForApiKey() {
        let env = EnvironmentManager.shared
        let currentKey = env.getApiKey() ?? ""
        
        let alert = NSAlert()
        alert.messageText = "DeepSeek API Configuration"
        alert.informativeText = "Enter your DEEPSEEK_API_KEY. It will be saved securely in ~/.dsh/.env and used for sessions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 380, height: 80))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        input.placeholderString = "sk-..."
        input.stringValue = currentKey
        
        let repoLabel = NSTextField(labelWithString: "Workspace Root: \(env.repoRoot)")
        repoLabel.font = NSFont.systemFont(ofSize: 11)
        repoLabel.textColor = .secondaryLabelColor
        
        stack.addArrangedSubview(input)
        stack.addArrangedSubview(repoLabel)
        alert.accessoryView = stack
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newKey = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newKey.isEmpty {
                _ = env.saveApiKey(newKey)
            }
        }
    }
}

// MARK: - App Delegate & Menu Bar Integration

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        MainWindowController.shared.showWindow(nil)
        MainWindowController.shared.window?.makeKeyAndOrderFront(nil)
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "🐋 DSH"
        }
        
        statusMenu = NSMenu()
        
        let titleItem = NSMenuItem(title: "DeepSeek Harness", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        statusMenu.addItem(titleItem)
        statusMenu.addItem(NSMenuItem.separator())
        
        let openGuiItem = NSMenuItem(title: "Open Launcher Window", action: #selector(showMainWindow), keyEquivalent: "o")
        openGuiItem.target = self
        statusMenu.addItem(openGuiItem)
        
        let startWebItem = NSMenuItem(title: "Start Web Server", action: #selector(toggleServerFromMenu), keyEquivalent: "s")
        startWebItem.target = self
        statusMenu.addItem(startWebItem)
        
        let browserItem = NSMenuItem(title: "Open in Browser", action: #selector(openBrowserFromMenu), keyEquivalent: "b")
        browserItem.target = self
        statusMenu.addItem(browserItem)
        
        let terminalItem = NSMenuItem(title: "Open Terminal Session", action: #selector(openTerminalFromMenu), keyEquivalent: "t")
        terminalItem.target = self
        statusMenu.addItem(terminalItem)
        
        let logsItem = NSMenuItem(title: "View Live Logs", action: #selector(showLogsWindow), keyEquivalent: "l")
        logsItem.target = self
        statusMenu.addItem(logsItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit DeepSeek Harness", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        statusMenu.addItem(quitItem)
        
        statusItem.menu = statusMenu
        
        ServerManager.shared.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch status {
                case .running(_):
                    self.statusItem.button?.title = "🐋🟢 DSH"
                    startWebItem.title = "Stop Web Server"
                case .starting:
                    self.statusItem.button?.title = "🐋🟡 DSH"
                    startWebItem.title = "Starting..."
                case .stopped, .error:
                    self.statusItem.button?.title = "🐋 DSH"
                    startWebItem.title = "Start Web Server"
                }
            }
        }
    }
    
    @objc private func showMainWindow() {
        MainWindowController.shared.showWindow(nil)
        MainWindowController.shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func toggleServerFromMenu() {
        if case .running = ServerManager.shared.status {
            ServerManager.shared.stopWebServer()
        } else {
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
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        ServerManager.shared.stopWebServer()
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
