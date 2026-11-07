import AVFoundation
import Combine
import Foundation

enum PlaybackPhase: Equatable {
    case idle, connecting, playing, paused, failed
}

@MainActor
final class PlayerStore: NSObject, ObservableObject, @preconcurrency AVPlayerItemMetadataOutputPushDelegate {
    @Published var presets: [RadioStation] = Array(repeating: .empty, count: 10) {
        didSet { savePresets() }
    }
    @Published var selectedPreset = 0
    @Published private(set) var currentStation: RadioStation?
    @Published private(set) var songTitle = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var phase: PlaybackPhase = .idle
    @Published private(set) var failureMessage = ""
    @Published private(set) var language = AppLanguage.saved
    var status: String {
        switch phase {
        case .idle: language.text("Připraveno", "Ready")
        case .connecting: language.text("Připojuji se", "Connecting")
        case .playing: language.text("Přehrává se", "Playing")
        case .paused: language.text("Pozastaveno", "Paused")
        case .failed: failureMessage.isEmpty ? language.text("Stream se nepodařilo přehrát", "Could not play the stream") : failureMessage
        }
    }
    var waitingForTitle: String { language.text("Čekám na informace o skladbě…", "Waiting for track information…") }
    @Published var volume: Double = {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "NetRadio.volume") != nil else { return 0.7 }
        return min(max(defaults.double(forKey: "NetRadio.volume"), 0), 1)
    }() {
        didSet {
            UserDefaults.standard.set(volume, forKey: "NetRadio.volume")
            player.volume = Float(volume)
        }
    }

    private var player = AVPlayer()
    private let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var startupTimeoutTask: Task<Void, Never>?
    private var metadataFallbackTask: Task<Void, Never>?
    private var icyMetadataMonitor: ICYMetadataMonitor?
    private var userRequestedPause = false
    private var playbackStableSince: Date?
    private var connectingSince: Date?
    private var playbackGeneration = 0

    override init() {
        super.init()
        player.volume = Float(volume)
        configurePlayerObservation()
        if let data = UserDefaults.standard.data(forKey: "NetRadio.presets.v1"),
           let saved = try? JSONDecoder().decode([RadioStation].self, from: data) {
            presets = Array(saved.prefix(10)) + Array(repeating: .empty, count: max(0, 10 - saved.count))
        }
        metadataOutput.setDelegate(self, queue: .main)
        Task { [weak self] in await self?.loadMissingStationFavicons() }
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        let wasWaiting = songTitle == waitingForTitle
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: "NetRadio.language")
        if wasWaiting { songTitle = waitingForTitle }
        if phase == .failed, failureMessage.isEmpty {
            songTitle = language.text("Stream není dostupný nebo ho macOS nepodporuje.", "The stream is unavailable or not supported by macOS.")
        }
    }

    private func loadMissingStationFavicons() async {
        let missing = presets.enumerated().compactMap { index, station -> (Int, String, String)? in
            guard station.favicon?.isEmpty != false, !station.uuid.isEmpty else { return nil }
            return (index, station.uuid, station.streamURL)
        }
        await withTaskGroup(of: (Int, String, String?).self) { group in
            for (index, uuid, streamURL) in missing {
                group.addTask { (index, streamURL, await RadioBrowserService.favicon(for: uuid)) }
            }
            for await (index, streamURL, favicon) in group {
                guard let favicon, presets.indices.contains(index), presets[index].streamURL == streamURL else { continue }
                presets[index].favicon = favicon
                if currentStation?.streamURL == streamURL, currentStation?.favicon?.isEmpty != false {
                    currentStation?.favicon = favicon
                }
            }
        }
    }

    func play(_ station: RadioStation, in slot: Int? = nil, registerClick: Bool = false) {
        playbackGeneration += 1
        guard let url = playbackURL(for: station) else {
            failureMessage = language.text("Neplatná adresa streamu", "Invalid stream URL")
            phase = .failed
            return
        }
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        metadataFallbackTask?.cancel()
        icyMetadataMonitor?.stop()
        icyMetadataMonitor = nil
        resetPlayerForNewStream()
        if let slot { selectedPreset = slot }
        currentStation = station
        songTitle = waitingForTitle
        phase = .connecting
        failureMessage = ""
        userRequestedPause = false
        isPlaying = false
        playbackStableSince = nil
        connectingSince = Date()
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = url.pathExtension.lowercased() == "m3u8" ? 2 : 3
        item.add(metadataOutput)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    // Readiness alone is not proof that the stream is flowing.
                    break
                case .failed:
                    self.startupTimeoutTask?.cancel()
                    self.startupTimeoutTask = nil
                    self.failureMessage = self.language.text("Stream se nepodařilo přehrát", "Could not play the stream")
                    self.phase = .failed
                    self.songTitle = self.language.text("Stream není dostupný nebo ho macOS nepodporuje.", "The stream is unavailable or not supported by macOS.")
                    self.isPlaying = false
                    self.statusObservation?.invalidate()
                    self.statusObservation = nil
                    self.player.pause()
                    self.player.currentItem?.remove(self.metadataOutput)
                    self.player.replaceCurrentItem(with: nil)
                    self.connectingSince = nil
                    self.playbackStableSince = nil
                    self.icyMetadataMonitor?.stop()
                    self.icyMetadataMonitor = nil
                default: break
                }
            }
        }
        player.replaceCurrentItem(with: item)
        player.volume = Float(volume)
        player.play()
        metadataFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, !Task.isCancelled,
                  self.currentStation?.id == station.id,
                  self.songTitle == self.waitingForTitle else { return }
            let monitor = ICYMetadataMonitor { [weak self] title in
                Task { @MainActor in
                    guard self?.currentStation?.id == station.id else { return }
                    self?.songTitle = title
                }
            }
            self.icyMetadataMonitor = monitor
            monitor.start(url: metadataURL(for: station, fallback: url))
        }
        scheduleStartupTimeout()
        if registerClick { RadioBrowserService().registerClick(for: station) }
    }

    func tune(_ slot: Int) {
        guard presets.indices.contains(slot), !presets[slot].streamURL.isEmpty else { selectedPreset = slot; return }
        play(presets[slot], in: slot, registerClick: true)
    }

    func save(_ station: RadioStation, to slot: Int) {
        guard presets.indices.contains(slot) else { return }
        presets[slot] = station
        selectedPreset = slot
    }

    func removePreset(at slot: Int) {
        guard presets.indices.contains(slot) else { return }
        presets[slot] = .empty
    }

    func togglePlayback() {
        if phase == .playing {
            startupTimeoutTask?.cancel()
            startupTimeoutTask = nil
            userRequestedPause = true
            playbackGeneration += 1
            player.pause()
            isPlaying = false
            phase = .paused
            playbackStableSince = nil
            connectingSince = nil
            metadataFallbackTask?.cancel()
            icyMetadataMonitor?.stop()
            icyMetadataMonitor = nil
        }
        else if phase == .connecting, let currentStation {
            play(currentStation)
        }
        else if let currentStation {
            userRequestedPause = false
            if phase == .failed || phase == .idle || player.currentItem == nil {
                play(currentStation)
                return
            }
            phase = .connecting
            playbackGeneration += 1
            connectingSince = Date()
            if player.currentItem != nil { scheduleStartupTimeout() }
            player.play()
        }
    }

    func stop() {
        playbackGeneration += 1
        startupTimeoutTask?.cancel()
        startupTimeoutTask = nil
        metadataFallbackTask?.cancel()
        icyMetadataMonitor?.stop()
        icyMetadataMonitor = nil
        player.pause()
        player.currentItem?.remove(metadataOutput)
        player.replaceCurrentItem(with: nil)
        statusObservation?.invalidate()
        statusObservation = nil
        songTitle = language.text("Přehrávání zastaveno.", "Playback stopped.")
        isPlaying = false
        userRequestedPause = false
        phase = .idle
        playbackStableSince = nil
        connectingSince = nil
        failureMessage = ""
    }

    private func updatePlaybackState(_ controlStatus: AVPlayer.TimeControlStatus) {
        guard currentStation != nil, player.currentItem != nil, phase != .failed else { return }
        switch controlStatus {
        case .playing:
            if phase != .playing { playbackStableSince = Date() }
            phase = .playing
            isPlaying = true
        case .waitingToPlayAtSpecifiedRate:
            guard !userRequestedPause else { return }
            if let stableSince = playbackStableSince,
               Date().timeIntervalSince(stableSince) >= 8 {
                connectingSince = Date()
            } else if connectingSince == nil {
                connectingSince = Date()
            }
            playbackStableSince = nil
            phase = .connecting
            isPlaying = false
            if startupTimeoutTask == nil, player.currentItem != nil {
                scheduleStartupTimeout()
            }
        case .paused:
            isPlaying = false
            if userRequestedPause { phase = .paused }
        @unknown default:
            break
        }
    }

    private func resetPlayerForNewStream() {
        timeControlObservation?.invalidate()
        timeControlObservation = nil
        statusObservation?.invalidate()
        statusObservation = nil
        player.pause()
        player.currentItem?.remove(metadataOutput)
        player.replaceCurrentItem(with: nil)
        player = AVPlayer()
        configurePlayerObservation()
    }

    private func configurePlayerObservation() {
        player.automaticallyWaitsToMinimizeStalling = true
        let observedPlayer = player
        timeControlObservation = observedPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak observedPlayer] _, _ in
            Task { @MainActor [weak self, weak observedPlayer] in
                guard let self, let observedPlayer, self.player === observedPlayer else { return }
                self.updatePlaybackState(observedPlayer.timeControlStatus)
            }
        }
    }

    private func scheduleStartupTimeout() {
        guard startupTimeoutTask == nil, let connectingSince else { return }
        let generation = playbackGeneration
        let remaining = max(0, 10 - Date().timeIntervalSince(connectingSince))
        startupTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self,
                  self.playbackGeneration == generation else { return }
            self.startupTimeoutTask = nil
            guard self.phase != .idle, self.phase != .paused, self.phase != .failed else { return }
            if self.phase == .playing {
                self.connectingSince = nil
                return
            }
            self.player.pause()
            self.player.replaceCurrentItem(with: nil)
            self.statusObservation?.invalidate()
            self.statusObservation = nil
            self.isPlaying = false
            self.phase = .failed
            self.playbackStableSince = nil
            self.connectingSince = nil
            self.failureMessage = self.language.text("Stream se neotevřel", "The stream did not open")
            self.songTitle = self.language.text("Připojení vypršelo. Zkuste jinou stanici.", "Connection timed out. Try another station.")
            self.icyMetadataMonitor?.stop()
            self.icyMetadataMonitor = nil
        }
    }

    private func playbackURL(for station: RadioStation) -> URL? {
        guard var components = URLComponents(string: station.streamURL) else { return nil }
        // Play.cz serves the same Icecast stream over HTTPS; AVPlayer can stall on its HTTP endpoint.
        if ["icecast1.play.cz", "icecast8.play.cz"].contains(components.host ?? ""),
           components.scheme == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    private func metadataURL(for station: RadioStation, fallback: URL) -> URL {
        let normalizedName = station.name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if normalizedName.contains("radiozurnal"),
           let url = URL(string: "https://icecast8.play.cz/cro1-128.mp3") {
            return url
        }
        return fallback
    }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        let entries = groups.flatMap(\.items).compactMap { item -> (Bool, String)? in
            let identifier = item.identifier?.rawValue ?? ""
            let key = item.key.map { String(describing: $0) } ?? ""
            let isTrackTitle = item.commonKey == .commonKeyTitle
                || identifier.localizedCaseInsensitiveContains("streamtitle")
                || key.localizedCaseInsensitiveContains("streamtitle")
            guard let value = item.stringValue ?? item.value as? String else { return nil }
            var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = cleaned.range(of: "StreamTitle=", options: .caseInsensitive) {
                cleaned = String(cleaned[range.upperBound...])
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\"; \n\r\0"))
            }
            return cleaned.isEmpty ? nil : (isTrackTitle, cleaned)
        }
        let preferredTitle = entries.first(where: { $0.0 }).map { $0.1 }
        guard let title = preferredTitle ?? entries.first.map({ $0.1 }) else { return }
        Task { @MainActor [weak self] in
            self?.songTitle = title
        }
    }

    private func savePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: "NetRadio.presets.v1")
    }
}
