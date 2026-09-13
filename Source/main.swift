import Cocoa
import WebKit
import CoreText

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
        let menu = NSMenu()
        let item = NSMenuItem(); menu.addItem(item)
        let submenu = NSMenu(); submenu.addItem(withTitle: "Quit Stopwatch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu
        submenu.insertItem(updater.item, at: 0)
        submenu.insertItem(NSMenuItem.separator(), at: 1)
        updater.saveBeforeRestart = { [weak self] in
            guard let self else { return }
            let checkpoint = UpdateCheckpoint(state: self.state, now: self.now())
            if let data = try? JSONEncoder().encode(checkpoint) {
                UserDefaults.standard.set(data, forKey: "updateCheckpoint")
                UserDefaults.standard.synchronize()
            }
        }
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
        updater.start()
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "stopwatch")
        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 290), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Stopwatch"
        window.contentMinSize = NSSize(width: 320, height: 220)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let resources = Bundle.main.resourceURL!
        var html = try! String(contentsOf: resources.appendingPathComponent("index.html"), encoding: .utf8)
        let backgroundNumber = Int.random(in: 1...7)
        let backgroundData = try! Data(contentsOf: resources.appendingPathComponent("Backgrounds/background\(backgroundNumber).png"))
        html = html.replacingOccurrences(of: "__BACKGROUND_DATA__", with: "data:image/png;base64," + backgroundData.base64EncodedString())
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
        if action == "ready" { ready = true }
        else {
            if state.handle(action, at: now()) { signalCompletion() }
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
        if state.tick(at: timestamp) { signalCompletion() }
        synchronizeTicker()
        let data = try! JSONSerialization.data(withJSONObject: state.snapshot(at: timestamp))
        let json = String(data: data, encoding: .utf8)!
        web.evaluateJavaScript("window.render(\(json));", completionHandler: nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
