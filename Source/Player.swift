import Cocoa
import WebKit

// Plays the pasted video in a hidden YouTube embed, so the music stays inside Stewie.
final class Player: NSObject {
    private var web: WKWebView?
    private var videoID: String?
    private var poll: Timer?
    private var requested = 0
    weak var host: NSView?
    // Called about once a second with ["playing": Bool, "seconds": Double], or ["loading": true] while it starts.
    var onChange: (([String: Any]) -> Void)?
    // Called when YouTube refuses to play the video in an embed.
    var onFailure: ((String, Int) -> Void)?

    func play(_ id: String, from seconds: Int? = nil) {
        if let seconds { requested = seconds }
        guard let web, videoID == id else { return load(id, from: seconds ?? requested) }
        let seek = seconds.map { "p.seekTo(\($0), true);" } ?? ""
        web.evaluateJavaScript("(() => { const p = document.getElementById('movie_player'); if (!p || !p.playVideo) return false; \(seek) p.playVideo(); return true })()") { [weak self] result, _ in
            // Still starting up: begin again from the requested point.
            if result as? Bool != true, let self { self.load(id, from: seconds ?? self.requested) }
        }
    }

    func pause() {
        web?.evaluateJavaScript("document.getElementById('movie_player')?.pauseVideo?.()", completionHandler: nil)
    }

    func stop() {
        poll?.invalidate(); poll = nil
        web?.removeFromSuperview(); web = nil
        videoID = nil; requested = 0
        onChange?(["playing": false, "seconds": 0])
    }

    private func load(_ id: String, from seconds: Int) {
        if web == nil {
            let configuration = WKWebViewConfiguration()
            configuration.mediaTypesRequiringUserActionForPlayback = []
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 4, height: 4), configuration: configuration)
            view.alphaValue = 0.01
            host?.addSubview(view, positioned: .below, relativeTo: nil)
            web = view
        }
        videoID = id
        var components = URLComponents(string: "https://www.youtube.com/embed/\(id)")!
        components.queryItems = [URLQueryItem(name: "autoplay", value: "1"), URLQueryItem(name: "start", value: String(max(0, seconds))),
                                 URLQueryItem(name: "playsinline", value: "1"), URLQueryItem(name: "controls", value: "0"),
                                 URLQueryItem(name: "rel", value: "0"), URLQueryItem(name: "enablejsapi", value: "1")]
        var request = URLRequest(url: components.url!)
        // Embeds refuse to play without a referrer.
        request.setValue("https://stewie.app/", forHTTPHeaderField: "Referer")
        web?.load(request)
        onChange?(["loading": true, "seconds": Double(seconds)])
        if poll == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
            RunLoop.main.add(timer, forMode: .common)
            poll = timer
        }
    }

    private func check() {
        let script = """
        (() => {
          const p = document.getElementById('movie_player'), v = document.querySelector('video');
          if (document.querySelector('.ytp-error')) return {failed: true};
          if (!p || !p.getCurrentTime || !v) return null;
          return {playing: !v.paused && !v.ended, seconds: p.getCurrentTime()};
        })()
        """
        web?.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, let state = result as? [String: Any], let id = self.videoID else { return }
            if let seconds = state["seconds"] as? Double { self.requested = Int(seconds) }
            if state["failed"] as? Bool == true { let from = self.requested; self.stop(); self.onFailure?(id, from); return }
            self.onChange?(state)
        }
    }
}
