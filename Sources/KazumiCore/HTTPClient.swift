// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public var statusCode: Int
    public var data: Data
    public var text: String
    public var url: URL
    public var headers: [String: String]

    public var json: JSONValue? { try? JSONValue.parse(data) }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init(session: URLSession = .shared) {
        self.session = session
    }

    private let session: URLSession

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KazumiError.message("响应不是 HTTP")
        }
        return (data, http)
    }
}

public struct HTTPClient: Sendable {
    public var transport: any HTTPTransport
    public var timeout: TimeInterval

    public init(transport: any HTTPTransport = URLSessionTransport(), timeout: TimeInterval = 20) {
        self.transport = transport
        self.timeout = timeout
    }

    public func send(
        _ prepared: PreparedRequest,
        userAgent: String? = nil,
        referer: String? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> HTTPResponse {
        guard var components = URLComponents(string: prepared.url) else {
            throw KazumiError.message("URL 无效: \(prepared.url)")
        }
        if !prepared.query.isEmpty {
            var items = components.queryItems ?? []
            for (key, value) in prepared.query.sorted(by: { $0.key < $1.key }) {
                items.append(URLQueryItem(name: key, value: value))
            }
            components.queryItems = items
        }
        guard let url = components.url else {
            throw KazumiError.message("URL 无效: \(prepared.url)")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = prepared.method
        var headers = extraHeaders
        if let userAgent, !userAgent.isEmpty { headers["User-Agent"] = userAgent }
        if let referer, !referer.isEmpty { headers["Referer"] = referer }
        for (key, value) in prepared.headers {
            headers[key] = value
        }
        if prepared.bodyType == APIBodyType.json {
            headers["Content-Type"] = headers["Content-Type"] ?? "application/json"
            if let body = prepared.body {
                request.httpBody = try JSONSerialization.data(withJSONObject: body.foundationObject)
            }
        } else if prepared.bodyType == APIBodyType.form {
            headers["Content-Type"] = headers["Content-Type"] ?? "application/x-www-form-urlencoded"
            if case .object(let fields)? = prepared.body {
                let pairs = fields.keys.sorted().map { key in
                    let value = fields[key]?.templateString ?? ""
                    return PercentEncoding.encodeQueryComponent(key) + "=" + PercentEncoding.encodeQueryComponent(value)
                }
                request.httpBody = pairs.joined(separator: "&").data(using: .utf8)
            }
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, http) = try await transport.send(request)
        guard (200..<400).contains(http.statusCode) else {
            throw KazumiError.http(status: http.statusCode, url: url.absoluteString)
        }
        let text = decodeText(data, headers: http)
        var headerMap: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headerMap[String(describing: key)] = String(describing: value)
        }
        return HTTPResponse(statusCode: http.statusCode, data: data, text: text, url: http.url ?? url, headers: headerMap)
    }

    /// Raw body for WebDAV XML and other non-JSON calls. Status 207 is accepted.
    public func sendRaw(
        method: String,
        url: String,
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> HTTPResponse {
        guard let target = URL(string: url) else {
            throw KazumiError.message("URL 无效: \(url)")
        }
        var request = URLRequest(url: target, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, http) = try await transport.send(request)
        guard (200..<400).contains(http.statusCode) else {
            throw KazumiError.http(status: http.statusCode, url: url)
        }
        let text = decodeText(data, headers: http)
        var headerMap: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headerMap[String(describing: key)] = String(describing: value)
        }
        return HTTPResponse(statusCode: http.statusCode, data: data, text: text, url: http.url ?? target, headers: headerMap)
    }

    public func get(_ url: String, headers: [String: String] = [:]) async throws -> HTTPResponse {
        try await send(PreparedRequest(method: "GET", url: url), extraHeaders: headers)
    }

    public func post(_ url: String, json body: JSONValue, headers: [String: String] = [:]) async throws -> HTTPResponse {
        try await send(
            PreparedRequest(method: "POST", url: url, bodyType: APIBodyType.json, body: body),
            extraHeaders: headers
        )
    }

    private func decodeText(_ data: Data, headers: HTTPURLResponse) -> String {
        let declared = TextCharsets.charset(
            contentType: headers.value(forHTTPHeaderField: "Content-Type"),
            bodyPrefix: nil
        )
        if let declared, !TextCharsets.isUTF8(declared), let text = TextCharsets.decode(data, charset: declared) {
            return text
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let meta = TextCharsets.charset(contentType: nil, bodyPrefix: Data(data.prefix(4096))),
           let text = TextCharsets.decode(data, charset: meta) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }
}

public struct RuleService: Sendable {
    public var engine: RuleEngine
    public var http: HTTPClient

    public init(engine: RuleEngine = RuleEngine(), http: HTTPClient = HTTPClient()) {
        self.engine = engine
        self.http = http
    }

    public func search(rule: PluginRule, keyword: String, extraHeaders: [String: String] = [:]) async throws -> [SearchHit] {
        let request: PreparedRequest
        do {
            request = try engine.prepareSearch(rule: rule, keyword: keyword)
        } catch {
            throw KazumiError.message("\(rule.name) 搜索请求无效：\(error)")
        }
        let response: HTTPResponse
        do {
            response = try await http.send(request, userAgent: agent(rule), referer: referer(rule), extraHeaders: extraHeaders)
        } catch let error as KazumiError {
            if case .http = error, rule.antiCrawler.enabled {
                throw KazumiError.captchaRequired(plugin: rule.name, pageURL: request.url)
            }
            throw error
        }
        let parsed: SearchParseResult
        do {
            parsed = try engine.parseSearch(rule: rule, raw: response.text)
        } catch let error as KazumiError {
            if case .captchaRequired(let plugin, _) = error {
                throw KazumiError.captchaRequired(plugin: plugin, pageURL: response.url.absoluteString)
            }
            throw error
        }
        if parsed.items.isEmpty {
            throw KazumiError.noResult(plugin: rule.name)
        }
        return parsed.items
    }

    public func chapters(rule: PluginRule, source: String, extraHeaders: [String: String] = [:]) async throws -> [PlaybackRoad] {
        let request = try engine.prepareChapters(rule: rule, source: source)
        let response = try await http.send(request, userAgent: agent(rule), referer: referer(rule), extraHeaders: extraHeaders)
        let parsed = try engine.parseChapters(rule: rule, raw: response.text, source: source)
        if parsed.roads.isEmpty {
            throw KazumiError.message("\(rule.name) 没有解析到播放线路")
        }
        return parsed.roads
    }

    private func agent(_ rule: PluginRule) -> String {
        rule.userAgent.isEmpty ? KazumiCore.defaultBrowserUserAgent : rule.userAgent
    }

    private func referer(_ rule: PluginRule) -> String {
        if !rule.referer.isEmpty { return rule.referer }
        return rule.baseURL
    }
}
