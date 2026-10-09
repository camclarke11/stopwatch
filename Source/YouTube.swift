import Foundation

// Looks up a pasted YouTube link without an API key: the title from oEmbed, a small thumbnail,
// and a tracklist from the video's comments (or its description when no comment has one).
enum YouTube {
    struct Failure: Error {}

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    static func load(id: String) async throws -> MusicLink {
        async let thumbnail = thumbnail(id)
        async let tracks = tracklist(id)
        let (title, author) = try await details(id)
        return MusicLink(id: id, title: title, author: author, thumbnail: await thumbnail ?? "", tracks: await tracks)
    }

    static func details(_ id: String) async throws -> (String, String) {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "format", value: "json"), URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)")]
        let data = try await fetch(URLRequest(url: components.url!))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let title = json["title"] as? String else { throw Failure() }
        return (title, json["author_name"] as? String ?? "")
    }

    static func thumbnail(_ id: String) async -> String? {
        guard let data = try? await fetch(URLRequest(url: URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")!)) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }

    // Reads the first two pages of comments, where pinned and top tracklists live.
    static func tracklist(_ id: String) async -> [Track] {
        async let length = duration(id)
        guard let watch = try? await next(["videoId": id]) else { return [] }
        var comments: [String] = []
        var token = Tracklist.commentsToken(in: watch)
        for _ in 0..<2 {
            guard let current = token, let page = try? await next(["continuation": current]) else { break }
            comments += Tracklist.comments(in: page)
            token = Tracklist.nextPageToken(in: page)
        }
        return Tracklist.best(comments: comments, description: Tracklist.description(in: watch), duration: await length)
    }

    // The video length, so timestamps past the end are dropped. Optional: the tracklist still loads without it.
    static func duration(_ id: String) async -> Int? {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(id)")!)
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        guard let data = try? await fetch(request), let page = String(data: data, encoding: .utf8),
              let range = page.range(of: #""lengthSeconds":"\d+""#, options: .regularExpression) else { return nil }
        return Int(page[range].filter(\.isNumber)).flatMap { $0 > 0 ? $0 : nil }
    }

    static func next(_ body: [String: Any]) async throws -> Any {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/next?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SOCS=CAI", forHTTPHeaderField: "Cookie")
        var payload = body
        payload["context"] = ["client": ["clientName": "WEB", "clientVersion": "2.20250101.00.00", "hl": "en"]]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return try JSONSerialization.jsonObject(with: try await fetch(request))
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure() }
        return data
    }
}
