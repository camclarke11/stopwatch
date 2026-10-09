import Cocoa
import WebKit
import CoreText
import MediaPlayer

final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let clock = ContinuousClock()
    let origin = ContinuousClock.now
    var state = TimerState()
    var ticker: Timer?
    let updater = GitUpdater()
    var ready = false
    var completionSound: NSSound?
    var backgrounds: [URL] = []
    var backgroundIndex = 0
    var log = TaskLog()
    var logSavedAt = 0.0
    var music: MusicLink?
    var musicRequest = 0
    let player = Player()
    var musicPlaying = false
    var musicSeconds = 0.0
    var musicVolume = UserDefaults.standard.object(forKey: "musicVolume") as? Int ?? 80
    let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Stewie", isDirectory: true).appendingPathComponent("tasks.json")
    func loadLog() {
        guard let data = try? Data(contentsOf: logURL) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode(TaskLog.self, from: data) { log = saved; return }
        // Set an unreadable file aside rather than overwrite someone's history.
        let aside = logURL.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: logURL, to: aside)
    }
    func saveLog() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(log).write(to: logURL, options: .atomic)
            logSavedAt = now()
        } catch {
            NSLog("Could not save tasks: %@", error.localizedDescription)
        }
    }
    func sendHistory() {
        log.record(state, at: now())
        guard let data = try? JSONSerialization.data(withJSONObject: log.history()),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.renderHistory(\(json));", completionHandler: nil)
    }
    func handleMusic(_ action: String) {
        if action == "music-clear" {
            musicRequest += 1; music = nil; player.stop()
            UserDefaults.standard.removeObject(forKey: "music")
            sendMusic(); return
        }
        if action == "music-play", let music { player.play(music.id); return }
        if action == "music-pause" { player.pause(); return }
        if action == "music-toggle" { toggleMusic(); return }
        if action == "music-next" { skipTrack(1); return }
        if action == "music-previous" { skipTrack(-1); return }
        if action.hasPrefix("music-volume:"), let level = Int(action.dropFirst("music-volume:".count)) {
            musicVolume = min(100, max(0, level))
            UserDefaults.standard.set(musicVolume, forKey: "musicVolume")
            player.volume = musicVolume; return
        }
        if action.hasPrefix("music-seek:"), let music, let seconds = Int(action.dropFirst("music-seek:".count)) { player.play(music.id, from: seconds); return }
        guard action.hasPrefix("music:") else { return }
        guard let id = Tracklist.videoID(from: String(action.dropFirst("music:".count))) else { sendMusic(status: "invalid"); return }
        musicRequest += 1
        let request = musicRequest
        player.stop()
        sendMusic(status: "loading")
        Task { @MainActor [weak self] in
            let link = try? await YouTube.load(id: id)
            // A newer paste or a removal replaces this one.
            guard let self, request == self.musicRequest else { return }
            guard let link else { self.sendMusic(status: "failed"); return }
            self.music = link
            if let data = try? JSONEncoder().encode(link) { UserDefaults.standard.set(data, forKey: "music") }
            self.sendMusic()
        }
    }
    // Opens behind Stewie, so the browser doesn't take over the screen.
    func openOnYouTube(_ id: String, from seconds: Int) {
        var components = URLComponents(string: "https://www.youtube.com/watch")!
        components.queryItems = [URLQueryItem(name: "v", value: id)]
        if seconds > 0 { components.queryItems?.append(URLQueryItem(name: "t", value: "\(seconds)s")) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(components.url!, configuration: configuration, completionHandler: nil)
    }
    @discardableResult func toggleMusic() -> Bool {
        guard let music else { return false }
        if musicPlaying { player.pause() } else { player.play(music.id) }
        return true
    }
    // Jumps to the next track, or back to the start of this one (or the one before, near its start).
    @discardableResult func skipTrack(_ direction: Int) -> Bool {
        guard let music, !music.tracks.isEmpty else { return false }
        let now = Int(musicSeconds)
        let current = music.tracks.lastIndex { $0.seconds <= now } ?? -1
        let target: Int
        if direction > 0 {
            guard current + 1 < music.tracks.count else { return false }
            target = music.tracks[current + 1].seconds
        } else if current >= 0, now - music.tracks[current].seconds > 3 || current == 0 {
            target = music.tracks[current].seconds
        } else {
            target = music.tracks[max(0, current - 1)].seconds
        }
        // Repeated presses step on from here, before the player reports back.
        musicSeconds = Double(target)
        player.play(music.id, from: target)
        return true
    }
    func setUpMediaKeys() {
        let commands = MPRemoteCommandCenter.shared()
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggleMusic() == true ? .success : .noActionableNowPlayingItem }
        commands.playCommand.addTarget { [weak self] _ in
            guard let self, let music = self.music else { return .noActionableNowPlayingItem }
            self.player.play(music.id); return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in self?.player.pause(); return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.skipTrack(1) == true ? .success : .commandFailed }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.skipTrack(-1) == true ? .success : .commandFailed }
    }
    // Lets the keyboard's media keys and Control Centre find the music.
    func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let music, musicPlaying || musicSeconds > 0 else { center.nowPlayingInfo = nil; center.playbackState = .stopped; return }
        let track = music.tracks.last { $0.seconds <= Int(musicSeconds) }
        center.nowPlayingInfo = [MPMediaItemPropertyTitle: track?.title ?? music.title, MPMediaItemPropertyArtist: track == nil ? music.author : music.title,
                                 MPNowPlayingInfoPropertyElapsedPlaybackTime: musicSeconds, MPNowPlayingInfoPropertyPlaybackRate: musicPlaying ? 1.0 : 0.0]
        center.playbackState = musicPlaying ? .playing : .paused
    }
    func sendPlayback(_ state: [String: Any]) {
        musicPlaying = state["playing"] as? Bool ?? false
        if let seconds = state["seconds"] as? Double { musicSeconds = seconds }
        updateNowPlaying()
        guard ready, let data = try? JSONSerialization.data(withJSONObject: state), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.renderPlayback(\(json));", completionHandler: nil)
    }
    func sendMusic(status: String? = nil) {
        var payload: [String: Any] = [:]
        if let music {
            payload = ["id": music.id, "title": music.title, "author": music.author, "thumbnail": music.thumbnail, "volume": musicVolume,
                       "tracks": music.tracks.map { ["seconds": $0.seconds, "title": $0.title, "note": $0.note ?? ""] as [String: Any] }]
        }
        if let status { payload["status"] = status }
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.renderMusic(\(json));", completionHandler: nil)
    }
    func migrateLegacyAppIfNeeded() -> Bool {
        let source = Bundle.main.bundleURL.standardizedFileURL
        let applications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").standardizedFileURL
        guard source.lastPathComponent == "Stopwatch.app", source.deletingLastPathComponent() == applications else { return false }
        let destination = applications.appendingPathComponent("Stewie.app")
        guard !FileManager.default.fileExists(atPath: destination.path),
              let bundledHelper = Bundle.main.url(forResource: "migrate-app", withExtension: "sh") else { return false }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stewie-migration-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let helper = folder.appendingPathComponent("migrate-app.sh")
            try FileManager.default.copyItem(at: bundledHelper, to: helper)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [helper.path, source.path, destination.path, String(ProcessInfo.processInfo.processIdentifier)]
            try process.run()
            NSApp.terminate(nil)
            return true
        } catch {
            NSLog("Could not rename Stopwatch.app to Stewie.app: %@", error.localizedDescription)
            return false
        }
    }
    func backgroundURI(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mime = url.pathExtension.lowercased() == "png" ? "image/png" : url.pathExtension.lowercased() == "webp" ? "image/webp" : "image/jpeg"
        return "data:\(mime);base64," + data.base64EncodedString()
    }
    func nextBackground() {
        guard backgrounds.count > 1 else { return }
        for offset in 1..<backgrounds.count {
            let candidate = (backgroundIndex + offset) % backgrounds.count
            guard let uri = backgroundURI(backgrounds[candidate]),
                  let data = try? JSONSerialization.data(withJSONObject: [uri]),
                  let json = String(data: data, encoding: .utf8) else { continue }
            backgroundIndex = candidate
            web.evaluateJavaScript("window.changeBackground(\(json)[0]);", completionHandler: nil)
            return
        }
    }
    func now() -> Double {
        let d = origin.duration(to: clock.now).components
        return Double(d.seconds) + Double(d.attoseconds) / 1e18
    }
    func signalCompletion() {
        completionSound = NSSound(named: "Glass")
        completionSound?.volume = 0.5
        completionSound?.play()
        NSApp.dockTile.badgeLabel = "✓"
    }
    func synchronizeTicker() {
        if state.startedAt != nil && ticker == nil {
            let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.render() }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if state.startedAt == nil {
            ticker?.invalidate(); ticker = nil
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if migrateLegacyAppIfNeeded() { return }
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let submenu = NSMenu(); submenu.addItem(withTitle: "Quit Stewie", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu
        submenu.insertItem(updater.item, at: 0)
        submenu.insertItem(NSMenuItem.separator(), at: 1)
        updater.saveBeforeRestart = { [weak self] in
            guard let self else { return }
            self.log.record(self.state, at: self.now()); self.saveLog()
            let checkpoint = UpdateCheckpoint(state: self.state, now: self.now())
            if let data = try? JSONEncoder().encode(checkpoint) {
                UserDefaults.standard.set(data, forKey: "updateCheckpoint")
                UserDefaults.standard.synchronize()
            }
        }
        // Without an Edit menu, ⌘V and the other text shortcuts do nothing in the web view.
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        let viewItem = NSMenuItem(); menu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let fullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(fullScreenItem); viewItem.submenu = viewMenu
        NSApp.mainMenu = menu
        state.mode = TimerMode(rawValue: UserDefaults.standard.string(forKey: "timerMode") ?? "stopwatch") ?? .stopwatch
        let savedTimings = UserDefaults.standard.array(forKey: "pomodoroTimings") as? [Int]
        if let timings = savedTimings, timings.count == 3, timings.allSatisfy({ (1...180).contains($0) }) {
            state.focusMinutes = timings[0]; state.breakMinutes = timings[1]; state.longBreakMinutes = timings[2]
        }
        if let data = UserDefaults.standard.data(forKey: "updateCheckpoint"),
           let checkpoint = try? JSONDecoder().decode(UpdateCheckpoint.self, from: data) {
            state = checkpoint.restored(at: now())
        }
        UserDefaults.standard.removeObject(forKey: "updateCheckpoint")
        loadLog()
        if let data = UserDefaults.standard.data(forKey: "music") { music = try? JSONDecoder().decode(MusicLink.self, from: data) }
        updater.start()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "stopwatch")
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 290), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Stewie"
        window.contentMinSize = NSSize(width: 320, height: 220)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        // The music player lives, hidden, behind the main view.
        let container = NSView()
        window.contentView = container
        web.frame = container.bounds
        web.autoresizingMask = [.width, .height]
        container.addSubview(web)
        player.host = container
        player.volume = musicVolume
        setUpMediaKeys()
        player.onChange = { [weak self] state in self?.sendPlayback(state) }
        player.onFailure = { [weak self] id, seconds in
            self?.openOnYouTube(id, from: seconds)
            self?.sendMusic(status: "external")
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let resources = Bundle.main.resourceURL!
        var html = try! String(contentsOf: resources.appendingPathComponent("index.html"), encoding: .utf8)
        backgrounds = ((try? FileManager.default.contentsOfDirectory(at: resources.appendingPathComponent("Backgrounds"), includingPropertiesForKeys: nil)) ?? [])
            .filter { ["png", "jpg", "jpeg", "webp"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        backgroundIndex = backgrounds.indices.randomElement() ?? 0
        let initialBackground = backgrounds.isEmpty ? "" : backgroundURI(backgrounds[backgroundIndex]) ?? ""
        html = html.replacingOccurrences(of: "__BACKGROUND_DATA__", with: initialBackground)
        let fontCSS = try! String(contentsOf: resources.appendingPathComponent("fonts.css"), encoding: .utf8)
        html = html.replacingOccurrences(of: "/* FONT */", with: fontCSS + (try! String(contentsOf: resources.appendingPathComponent("flap-font.css"), encoding: .utf8)))
        let css = try! String(contentsOf: resources.appendingPathComponent("rolling.css"), encoding: .utf8)
        let js = try! String(contentsOf: resources.appendingPathComponent("rolling.js"), encoding: .utf8)
        html = html.replacingOccurrences(of: "/* LIBRARY_CSS */", with: css).replacingOccurrences(of: "/* LIBRARY_JS */", with: js)
        let catJS = try! String(contentsOf: resources.appendingPathComponent("pixel-cat.js"), encoding: .utf8)
        html = html.replacingOccurrences(of: "/* PIXEL_CAT */", with: catJS)
        web.loadHTMLString(html, baseURL: resources)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let action = message.body as? String else { return }
        if action == "background:next" { nextBackground(); return }
        if action == "history" { sendHistory(); return }
        if action.hasPrefix("music") { handleMusic(action); return }
        let timestamp = now()
        if action.hasPrefix("task-") {
            // Credit the outgoing top task before the list changes.
            log.record(state, at: timestamp)
            if log.handle(action) { render(); saveLog() }
            return
        }
        if action == "ready" { ready = true; sendMusic() }
        else {
            log.record(state, at: timestamp)
            if state.handle(action, at: timestamp) { signalCompletion() }
            if action.hasPrefix("mode:") { UserDefaults.standard.set(state.mode.rawValue, forKey: "timerMode") }
            if action.hasPrefix("pomodoro-settings:") {
                UserDefaults.standard.set([state.focusMinutes, state.breakMinutes, state.longBreakMinutes], forKey: "pomodoroTimings")
            }
            if !state.isComplete { NSApp.dockTile.badgeLabel = nil }
        }
        render()
    }
    func render() {
        guard ready else { return }
        let timestamp = now()
        let wasTracking = log.isTracking
        log.record(state, at: timestamp)
        if state.tick(at: timestamp) { signalCompletion() }
        log.record(state, at: timestamp)
        if log.isTracking != wasTracking || (log.isTracking && timestamp - logSavedAt >= 30) { saveLog() }
        synchronizeTicker()
        var snapshot = state.snapshot(at: timestamp)
        snapshot.merge(log.snapshot()) { current, _ in current }
        let data = try! JSONSerialization.data(withJSONObject: snapshot)
        let json = String(data: data, encoding: .utf8)!
        web.evaluateJavaScript("window.render(\(json));", completionHandler: nil)
    }
    func applicationWillTerminate(_ notification: Notification) {
        guard ready else { return }
        log.record(state, at: now()); saveLog()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
