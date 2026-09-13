import Cocoa

final class GitUpdater: NSObject {
    var saveBeforeRestart: (() -> Void)?
    private var busy = false
    private var periodic: Timer?
    let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkManually), keyEquivalent: "")
    private var checkout: String? {
        guard let url = Bundle.main.url(forResource: "GitCheckout", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    override init() { super.init(); item.target = self }
    func start() {
        guard checkout != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.check(manual: false) }
        periodic = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in self?.check(manual: false) }
    }
    @objc private func checkManually() { check(manual: true) }
    private func message(_ title: String, _ detail: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail; alert.runModal()
    }
    private func setBusy(_ value: Bool, title: String = "Check for Updates…") {
        busy = value; item.title = title; item.action = value ? nil : #selector(checkManually)
    }
    private func run(_ arguments: [String], timeout: Double, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process(), output = Pipe()
            let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try? FileHandle(forWritingTo: log)
            defer { try? handle?.close(); try? FileManager.default.removeItem(at: log) }
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = arguments; process.standardOutput = output; process.standardError = handle
            do {
                try process.run()
                let deadline = Date().addingTimeInterval(timeout)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
                if process.isRunning { process.terminate(); throw NSError(domain: "Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "The operation timed out. Your installed app is unchanged."]) }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                guard process.terminationStatus == 0 else { throw NSError(domain: "Update", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not fetch or build the release. Check your internet connection, Git access and Apple Command Line Tools. Your installed app is unchanged."]) }
                let result = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async { completion(.success(result)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }
    }
    private func check(manual: Bool) {
        guard !busy else { return }
        guard let checkout, let script = Bundle.main.path(forResource: "git-update", ofType: "sh") else {
            if manual { message("Set up updates", "Install from a Git clone using install.sh to enable updates.") }; return
        }
        setBusy(true, title: "Checking for Updates…")
        run([script, "check", checkout], timeout: 60) { result in
            self.setBusy(false)
            switch result {
            case .failure(let error): if manual { self.message("Unable to check for updates", error.localizedDescription) }
            case .success(let output):
                let lines = output.split(whereSeparator: \.isNewline).map(String.init)
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                guard lines.count == 2, String(lines[0].dropFirst()).compare(current, options: .numeric) == .orderedDescending else {
                    if manual { self.message("You’re up to date", "Stopwatch \(current) is installed.") }; return
                }
                let alert = NSAlert(); alert.messageText = "Stopwatch \(lines[0]) is available"
                alert.informativeText = "Build and install this release? This may take a minute. Your timer will carry on after the app restarts."
                alert.addButton(withTitle: "Install Update"); alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn { self.build(script: script, checkout: checkout, tag: lines[0], commit: lines[1]) }
            }
        }
    }
    private func build(script: String, checkout: String, tag: String, commit: String) {
        setBusy(true, title: "Building Update…")
        run([script, "build", checkout, commit, String(tag.dropFirst())], timeout: 600) { result in
            self.setBusy(false)
            switch result {
            case .failure(let error): self.message("Update couldn’t be installed", error.localizedDescription)
            case .success(let output):
                let incoming = output.trimmingCharacters(in: .whitespacesAndNewlines)
                do {
                    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stopwatch-restart-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let helper = folder.appendingPathComponent("replace-app.sh")
                    try FileManager.default.copyItem(at: Bundle.main.url(forResource: "replace-app", withExtension: "sh")!, to: helper)
                    // Prepare the replacement while the old app is still running.
                    let destination = Bundle.main.bundleURL.path
                    let replacement = folder.appendingPathComponent("prepared.app")
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: incoming), to: replacement)
                    let buildFolder = URL(fileURLWithPath: incoming).deletingLastPathComponent()
                    if buildFolder.lastPathComponent.hasPrefix("stopwatch-update.") {
                        try? FileManager.default.removeItem(at: buildFolder)
                    }
                    let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                    process.arguments = [helper.path, replacement.path, destination, String(ProcessInfo.processInfo.processIdentifier)]
                    let ready = folder.appendingPathComponent("ready")
                    process.arguments!.append(ready.path)
                    try process.run()
                    self.setBusy(true, title: "Installing Update…")
                    DispatchQueue.global(qos: .utility).async {
                        let deadline = Date().addingTimeInterval(45)
                        while process.isRunning && !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline {
                            Thread.sleep(forTimeInterval: 0.1)
                        }
                        let prepared = FileManager.default.fileExists(atPath: ready.path) && process.isRunning
                        DispatchQueue.main.async {
                            self.setBusy(false)
                            if prepared {
                                self.saveBeforeRestart?()
                                NSApp.terminate(nil)
                            } else {
                                if process.isRunning { process.terminate() }
                                self.message("Update couldn’t be installed", "The replacement could not be prepared. Your current app is unchanged. Check that its folder is writable and try again.")
                            }
                        }
                    }
                } catch { self.message("Update couldn’t be installed", error.localizedDescription) }
            }
        }
    }
}
