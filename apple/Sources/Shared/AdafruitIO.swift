import Foundation

/// A single reading from an Adafruit IO feed.
public struct FeedReading: Sendable, Equatable, Identifiable {
    public let value: Double
    public let createdAt: Date
    public var id: Date { createdAt }

    public init(value: Double, createdAt: Date) {
        self.value = value
        self.createdAt = createdAt
    }
}

public enum AdafruitIOError: Error, Sendable {
    case badURL
    case http(Int)
    case empty
    case decoding
}

/// Minimal async Adafruit IO REST client (read-only).
/// Docs: https://io.adafruit.com/api/docs/
public struct AdafruitIOClient: Sendable {
    public let username: String
    public let apiKey: String
    private let session: URLSession

    public init(username: String, apiKey: String, session: URLSession = .shared) {
        self.username = username
        self.apiKey = apiKey
        self.session = session
    }

    private func makeRequest(path: String) throws -> URLRequest {
        guard let url = URL(string: "https://io.adafruit.com/api/v2/\(username)/\(path)") else {
            throw AdafruitIOError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-AIO-Key")
        request.timeoutInterval = 15
        return request
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AdafruitIOError.http(http.statusCode)
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String?) -> Date {
        guard let s else { return Date() }
        return isoFormatter.date(from: s) ?? Date()
    }

    /// Latest value of a feed (e.g. "temperature").
    public func latest(feed: String) async throws -> FeedReading {
        struct FeedDTO: Decodable { let last_value: String?; let updated_at: String? }
        let (data, response) = try await session.data(for: makeRequest(path: "feeds/\(feed)"))
        try Self.check(response)
        let dto = try JSONDecoder().decode(FeedDTO.self, from: data)
        guard let raw = dto.last_value, let value = Double(raw) else { throw AdafruitIOError.empty }
        return FeedReading(value: value, createdAt: Self.parseDate(dto.updated_at))
    }

    /// Recent history for a feed, oldest → newest.
    public func history(feed: String, limit: Int = 200) async throws -> [FeedReading] {
        struct PointDTO: Decodable { let value: String; let created_at: String }
        let (data, response) = try await session.data(for: makeRequest(path: "feeds/\(feed)/data?limit=\(limit)"))
        try Self.check(response)
        let points = try JSONDecoder().decode([PointDTO].self, from: data)
        return points
            .compactMap { p -> FeedReading? in
                guard let v = Double(p.value) else { return nil }
                return FeedReading(value: v, createdAt: Self.parseDate(p.created_at))
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
