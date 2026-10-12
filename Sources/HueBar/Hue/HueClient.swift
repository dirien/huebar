import CryptoKit
import Foundation

enum HueClientError: LocalizedError, Equatable {
    case invalidHost
    case unauthorized
    case linkButtonNotPressed
    case certificateMismatch
    case notAHueBridge
    case http(Int)
    case bridge(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost: "That doesn't look like a valid IP address or host name."
        case .unauthorized: "The bridge rejected HueBar's app key."
        case .linkButtonNotPressed: "The link button on the bridge hasn't been pressed."
        case .certificateMismatch: "The bridge presented a different certificate than when it was paired."
        case .notAHueBridge: "The device at that address doesn't look like a Hue Bridge."
        case .http(let status): "The bridge answered with HTTP \(status)."
        case .bridge(let message): message
        }
    }
}

/// The bridge serves a certificate from Signify's private CA, which macOS doesn't trust.
/// We pin the leaf certificate's SHA-256 fingerprint the first time we pair (trust on first use)
/// and refuse any other certificate afterwards.
final class CertificatePinner: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var pinned: String?
    private var observed: String?
    private var mismatched = false

    init(pinnedFingerprint: String?) {
        pinned = pinnedFingerprint
    }

    var observedFingerprint: String? { lock.withLock { observed } }
    var sawMismatch: Bool { lock.withLock { mismatched } }

    func pin(_ fingerprint: String) {
        lock.withLock { pinned = fingerprint }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let fingerprint = Self.fingerprint(of: leaf)
        let accepted = lock.withLock { () -> Bool in
            observed = fingerprint
            if let pinned, pinned != fingerprint {
                mismatched = true
                return false
            }
            return true
        }
        if accepted {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    static func fingerprint(of certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }
}

/// Talks to one bridge over the CLIP v2 API.
final class HueClient: @unchecked Sendable {
    let host: String
    let appKey: String?
    let pinner: CertificatePinner
    private let session: URLSession
    private let streamSession: URLSession

    init(host: String, appKey: String?, pinnedFingerprint: String?) {
        self.host = host
        self.appKey = appKey
        pinner = CertificatePinner(pinnedFingerprint: pinnedFingerprint)

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpMaximumConnectionsPerHost = 4
        config.connectionProxyDictionary = [:]  // the bridge is on the LAN; never route it through a proxy
        session = URLSession(configuration: config, delegate: pinner, delegateQueue: nil)

        let streamConfig = URLSessionConfiguration.ephemeral
        streamConfig.timeoutIntervalForRequest = 3600  // idle time allowed between events
        streamConfig.connectionProxyDictionary = [:]
        streamSession = URLSession(configuration: streamConfig, delegate: pinner, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
        streamSession.invalidateAndCancel()
    }

    // MARK: Pairing

    /// Identifies the bridge without credentials. Also captures its certificate fingerprint.
    func config() async throws -> BridgeConfig {
        let data = try await perform(request("api/0/config"))
        do {
            return try JSONDecoder().decode(BridgeConfig.self, from: data)
        } catch {
            throw HueClientError.notAHueBridge
        }
    }

    /// Requests an app key. Fails with `.linkButtonNotPressed` until the button on the bridge is pressed.
    func register(deviceType: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["devicetype": deviceType, "generateclientkey": true])
        let data = try await perform(request("api", method: "POST", body: body))
        let items = (try? JSONDecoder().decode([PairResponseItem].self, from: data)) ?? []
        if let success = items.first?.success {
            return success.username
        }
        if let error = items.first?.error {
            throw error.type == 101 ? HueClientError.linkButtonNotPressed : HueClientError.bridge(error.description)
        }
        throw HueClientError.notAHueBridge
    }

    // MARK: Resources

    func resources<T: Decodable>(_ type: String, as _: T.Type = T.self) async throws -> [T] {
        let data = try await perform(request("clip/v2/resource/\(type)"))
        return try HueJSON.decoder.decode(HueEnvelope<T>.self, from: data).data
    }

    func update<Body: Encodable>(_ type: String, id: String, _ body: Body) async throws {
        let payload = try HueJSON.encoder.encode(body)
        _ = try await perform(request("clip/v2/resource/\(type)/\(id)", method: "PUT", body: payload))
    }

    /// Streams bridge events until the connection drops or the calling task is cancelled.
    func streamEvents(_ onEvents: ([HueEvent]) async -> Void) async throws {
        var streamRequest = try request("eventstream/clip/v2")
        streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await translatingTransportErrors {
            try await streamSession.bytes(for: streamRequest)
        }
        try validate(response, body: nil)

        var lines = LineSplitter()
        var parser = EventStreamParser()
        for try await byte in bytes {
            guard let line = lines.push(byte), let payload = parser.feed(line) else { continue }
            if let events = try? HueJSON.decoder.decode([HueEvent].self, from: Data(payload.utf8)) {
                await onEvents(events)
            }
        }
    }

    // MARK: Plumbing

    private func request(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard !host.isEmpty, !host.contains(where: \.isWhitespace),
            let url = URL(string: "https://\(host)/\(path)")
        else { throw HueClientError.invalidHost }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let appKey {
            request.setValue(appKey, forHTTPHeaderField: "hue-application-key")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await translatingTransportErrors {
            try await session.data(for: request)
        }
        try validate(response, body: data)
        return data
    }

    private func validate(_ response: URLResponse, body: Data?) throws {
        guard let http = response as? HTTPURLResponse else { throw HueClientError.http(0) }
        switch http.statusCode {
        case 200..<300:
            return
        case 401, 403:
            throw HueClientError.unauthorized
        default:
            if let body,
                let message = (try? HueJSON.decoder.decode(HueEnvelope<ResourceRef>.self, from: body))?.errors.first?
                    .description
            {
                throw HueClientError.bridge(message)
            }
            throw HueClientError.http(http.statusCode)
        }
    }

    private func translatingTransportErrors<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as URLError {
            if pinner.sawMismatch { throw HueClientError.certificateMismatch }
            throw error
        }
    }
}
