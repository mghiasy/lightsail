import Foundation

enum APIClientError: LocalizedError {
    case badURL
    case badStatus(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid backend URL"
        case .badStatus(let code):
            return "Server returned \(code)"
        case .transport(let message):
            return message
        }
    }
}

/// Streams plaintext progress from the existing Python backend.
final class APIClient: NSObject, URLSessionDataDelegate {
    /// Simulator: localhost works. Physical device: set to your Mac's LAN IP, e.g. http://192.168.1.20:5173
    static var baseURL = URL(string: "http://127.0.0.1:5173")!

    private var session: URLSession!
    private var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private var buffer = Data()

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3600
        config.timeoutIntervalForResource = 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func stream(path: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.buffer = Data()

            guard let url = URL(string: path, relativeTo: Self.baseURL) else {
                continuation.finish(throwing: APIClientError.badURL)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("text/plain", forHTTPHeaderField: "Accept")

            let task = self.session.dataTask(with: request)
            continuation.onTermination = { _ in
                task.cancel()
            }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            continuation?.finish(throwing: APIClientError.badStatus(http.statusCode))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let range = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    continuation?.yield(trimmed)
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                continuation?.yield(trimmed)
            }
            buffer.removeAll()
        }

        if let error {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                continuation?.finish()
            } else {
                continuation?.finish(throwing: APIClientError.transport(error.localizedDescription))
            }
        } else {
            continuation?.finish()
        }
        continuation = nil
    }
}
