import Foundation

/// Reads ICY's interleaved title blocks from a fallback metadata-only request.
/// AVPlayer remains responsible for decoding and playing the stream.
final class ICYMetadataMonitor: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let onTitle: (String) -> Void
    private var metadataInterval = 0
    private var audioBytesRemaining = 0
    private var metadataBytesRemaining: Int?
    private var metadataBuffer = Data()
    private var expectingMetadataLength = false

    init(onTitle: @escaping (String) -> Void) {
        self.onTitle = onTitle
    }

    func start(url: URL) {
        var request = URLRequest(url: url)
        request.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        request.setValue("NetRadioMac/1.0 (macOS internet radio)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: queue)
        self.session = session
        task = session.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let response = response as? HTTPURLResponse,
           let value = response.value(forHTTPHeaderField: "icy-metaint"),
           let interval = Int(value), interval > 0 {
            metadataInterval = interval
            audioBytesRemaining = interval
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let bytes = [UInt8](data)
        var index = 0
        while index < bytes.count {
            if let remaining = metadataBytesRemaining {
                let amount = min(remaining, bytes.count - index)
                metadataBuffer.append(contentsOf: bytes[index..<(index + amount)])
                index += amount
                metadataBytesRemaining = remaining - amount
                if metadataBytesRemaining == 0 {
                    parseMetadataBlock()
                    metadataBytesRemaining = nil
                    audioBytesRemaining = metadataInterval
                }
            } else if expectingMetadataLength {
                let blockLength = Int(bytes[index]) * 16
                index += 1
                expectingMetadataLength = false
                if blockLength == 0 {
                    audioBytesRemaining = metadataInterval
                } else {
                    metadataBuffer.removeAll(keepingCapacity: true)
                    metadataBytesRemaining = blockLength
                }
            } else {
                let amount = min(audioBytesRemaining, bytes.count - index)
                index += amount
                audioBytesRemaining -= amount
                if audioBytesRemaining == 0 { expectingMetadataLength = true }
            }
        }
    }

    private func parseMetadataBlock() {
        guard let text = String(data: metadataBuffer, encoding: .utf8) else { return }
        let expression = try? NSRegularExpression(pattern: "(?i)StreamTitle=['\"]([^'\"]*)['\"]")
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression?.firstMatch(in: text, range: range),
              let titleRange = Range(match.range(at: 1), in: text) else { return }
        let title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { onTitle(title) }
    }
}
