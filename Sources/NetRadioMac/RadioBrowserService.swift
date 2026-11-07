import Foundation

enum RadioBrowserError: LocalizedError {
    case invalidResponse
    case noServers

    var errorDescription: String? {
        switch self {
        case .invalidResponse: AppLanguage.saved.text("Server vrátil neplatnou odpověď.", "The server returned an invalid response.")
        case .noServers: AppLanguage.saved.text("Služba Radio Browser právě není dostupná.", "Radio Browser is currently unavailable.")
        }
    }

    func message(language: AppLanguage) -> String {
        switch self {
        case .invalidResponse: language.text("Server vrátil neplatnou odpověď.", "The server returned an invalid response.")
        case .noServers: language.text("Služba Radio Browser právě není dostupná.", "Radio Browser is currently unavailable.")
        }
    }
}

final class RadioBrowserService: NSObject, XMLParserDelegate {
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = ["User-Agent": "NetRadioMac/1.0 (macOS internet radio)"]
        return URLSession(configuration: config)
    }()
    private var parsedStations: [RadioStation] = []
    private var currentFields: [String: String] = [:]

    func search(name: String) async throws -> [RadioStation] {
        let servers = await availableServers()
        guard !servers.isEmpty else { throw RadioBrowserError.noServers }
        var lastError: Error = RadioBrowserError.noServers
        for host in servers {
            do {
                var components = URLComponents(string: "https://\(host)/xml/stations/search")!
                components.queryItems = [
                    URLQueryItem(name: "name", value: name),
                    URLQueryItem(name: "limit", value: "100"),
                    URLQueryItem(name: "order", value: "votes"),
                    URLQueryItem(name: "reverse", value: "true"),
                    URLQueryItem(name: "hidebroken", value: "true")
                ]
                guard let url = components.url else { throw RadioBrowserError.invalidResponse }
                var request = URLRequest(url: url)
                request.setValue("NetRadioMac/1.0 (macOS internet radio)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RadioBrowserError.invalidResponse }
                return try parse(data)
            } catch { lastError = error }
        }
        throw lastError
    }

    func registerClick(for station: RadioStation) {
        guard !station.uuid.isEmpty, let url = URL(string: "https://de1.api.radio-browser.info/json/url/\(station.uuid)") else { return }
        var request = URLRequest(url: url)
        request.setValue("NetRadioMac/1.0 (macOS internet radio)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request).resume()
    }

    private func availableServers() async -> [String] {
        let discovery = URL(string: "https://all.api.radio-browser.info/json/servers")!
        if let (data, _) = try? await session.data(from: discovery),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let hosts = entries.compactMap { $0["name"] as? String }.shuffled()
            if !hosts.isEmpty {
                var unique: [String] = []
                for host in hosts + ["de1.api.radio-browser.info", "at1.api.radio-browser.info"] where !unique.contains(host) {
                    unique.append(host)
                    if unique.count == 2 { break }
                }
                return unique
            }
        }
        return ["de1.api.radio-browser.info", "at1.api.radio-browser.info"]
    }

    private func parse(_ data: Data) throws -> [RadioStation] {
        parsedStations = []
        currentFields = [:]
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw parser.parserError ?? RadioBrowserError.invalidResponse }
        return parsedStations
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "station" { currentFields = attributes }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "station",
              currentFields["lastcheckok"] != "0",
              let url = (currentFields["url_resolved"] ?? currentFields["url"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: url),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil,
              let name = currentFields["name"], !name.isEmpty else { return }
        parsedStations.append(RadioStation(
            uuid: currentFields["stationuuid"] ?? "", name: name, streamURL: url,
            country: currentFields["country"] ?? "", language: currentFields["language"] ?? "",
            codec: currentFields["codec"] ?? "", bitrate: currentFields["bitrate"] ?? "",
            favicon: currentFields["favicon"]
        ))
    }

    static func favicon(for uuid: String) async -> String? {
        guard !uuid.isEmpty, let url = URL(string: "https://de1.api.radio-browser.info/json/stations/byuuid/\(uuid)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("NetRadioMac/1.0 (macOS internet radio)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let stations = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let value = stations.first?["favicon"] as? String,
              let iconURL = URL(string: value),
              ["http", "https"].contains(iconURL.scheme?.lowercased() ?? ""),
              iconURL.host != nil else { return nil }
        return value
    }
}
