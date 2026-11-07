import SwiftUI
import AppKit

private let ink = Color(red: 0.14, green: 0.18, blue: 0.20)
private let muted = Color(red: 0.48, green: 0.53, blue: 0.54)
private let accent = Color(red: 0.12, green: 0.48, blue: 0.41)
private let paper = Color(red: 0.97, green: 0.97, blue: 0.94)

struct ContentView: View {
    @StateObject private var store = PlayerStore()
    @State private var isSearchPresented = false
    @State private var isCompact = false
    @State private var isAlwaysOnTop = UserDefaults.standard.bool(forKey: "NetRadio.alwaysOnTop")
    @State private var hostWindow: NSWindow?
    @State private var expandedWindowFrame: NSRect?

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private func tr(_ czech: String, _ english: String) -> String {
        store.language.text(czech, english)
    }

    var body: some View {
        Group {
            if isCompact {
                compactPlayer
            } else {
                VStack(spacing: 0) {
                    header
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            nowPlaying
                            presetsSection
                            searchEntry
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .frame(minWidth: isCompact ? 320 : 450, idealWidth: isCompact ? 320 : 450,
               minHeight: isCompact ? 100 : 640, idealHeight: isCompact ? 100 : 640)
        .background(paper)
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .background(WindowAccessor { window in
            if hostWindow !== window {
                hostWindow = window
                MenuBarController.shared.registerMainWindow(window)
                restoreWindowPosition(window)
                applyWindowPreferences()
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { notification in
            guard let movedWindow = notification.object as? NSWindow, movedWindow === hostWindow else { return }
            UserDefaults.standard.set(movedWindow.frame.minX, forKey: "NetRadio.windowTopLeftX")
            UserDefaults.standard.set(movedWindow.frame.maxY, forKey: "NetRadio.windowTopLeftY")
        }
        .onChange(of: isCompact) { _ in applyWindowPreferences() }
        .onChange(of: isAlwaysOnTop) { value in
            UserDefaults.standard.set(value, forKey: "NetRadio.alwaysOnTop")
            applyWindowPreferences()
        }
        .sheet(isPresented: $isSearchPresented) {
            StationSearchSheet(store: store)
                .frame(minWidth: 520, idealWidth: 560, minHeight: 500, idealHeight: 580)
        }
    }

    private var compactPlayer: some View {
        Button {
            isCompact = false
        } label: {
            HStack(spacing: 11) {
                stationArtwork(size: 36, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.currentStation?.name ?? "NetRadio")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(store.songTitle.isEmpty ? store.status : store.songTitle)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                        .help(store.songTitle)
                    Text(store.currentStation?.detail(language: store.language) ?? tr("Internetové rádio", "Internet radio"))
                        .font(.system(size: 9)).foregroundStyle(muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Circle().fill(store.isPlaying ? accent : muted.opacity(0.35)).frame(width: 7, height: 7)
                if isAlwaysOnTop {
                    Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(accent)
                }
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(muted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("Kliknutím obnovíte hlavní okno", "Click to restore the main window"))
    }

    private func applyWindowPreferences() {
        guard let window = hostWindow else { return }
        window.level = isAlwaysOnTop ? .floating : .normal
        window.minSize = isCompact ? NSSize(width: 320, height: 100) : NSSize(width: 450, height: 640)

        DispatchQueue.main.async {
            guard self.hostWindow === window else { return }
            if self.isCompact {
                let topLeft = self.expandedWindowFrame.map { NSPoint(x: $0.minX, y: $0.maxY) }
                    ?? NSPoint(x: window.frame.minX, y: window.frame.maxY)
                window.setContentSize(NSSize(width: 320, height: 100))
                window.setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
            } else if let expandedFrame = self.expandedWindowFrame {
                let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
                let restoredFrame = NSRect(x: topLeft.x, y: topLeft.y - expandedFrame.height,
                                           width: expandedFrame.width, height: expandedFrame.height)
                window.setFrame(restoredFrame, display: true, animate: true)
                self.expandedWindowFrame = nil
            } else {
                window.setContentSize(NSSize(width: 450, height: 640))
            }
        }
    }

    private func restoreWindowPosition(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "NetRadio.windowTopLeftX") != nil,
              defaults.object(forKey: "NetRadio.windowTopLeftY") != nil else { return }
        let x = defaults.double(forKey: "NetRadio.windowTopLeftX")
        let topY = defaults.double(forKey: "NetRadio.windowTopLeftY")
        window.setFrameOrigin(NSPoint(x: x, y: topY - window.frame.height))
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 1) {
                Text("NetRadio").font(.system(size: 16, weight: .semibold))
                Text(tr("INTERNETOVÉ RÁDIO", "INTERNET RADIO")).font(.system(size: 9, weight: .semibold, design: .rounded)).tracking(1.1).foregroundStyle(muted)
            }
            Spacer()
            HStack(spacing: 12) {
                Button {
                    let activeWindow = hostWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible })
                    if let activeWindow {
                        MenuBarController.shared.minimizeToMenuBar(activeWindow)
                    }
                } label: {
                    Image(systemName: "arrow.up.to.line")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(tr("Minimalizovat do horní lišty macOS", "Minimize to the macOS menu bar"))
                Button {
                    if let hostWindow, expandedWindowFrame == nil { expandedWindowFrame = hostWindow.frame }
                    isCompact = true
                } label: {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(tr("Kompaktní přehrávač", "Compact player"))
                Button {
                    isAlwaysOnTop.toggle()
                } label: {
                    Image(systemName: isAlwaysOnTop ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isAlwaysOnTop ? accent : muted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isAlwaysOnTop ? tr("Vypnout: vždy navrchu", "Turn off: always on top") : tr("Zapnout: vždy navrchu", "Turn on: always on top"))
                Button {
                    let newLanguage: AppLanguage = store.language == .czech ? .english : .czech
                    store.setLanguage(newLanguage)
                    MenuBarController.shared.updateLanguage(newLanguage)
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: "globe")
                            .font(.system(size: 12, weight: .medium))
                        Text(store.language.shortLabel)
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(muted)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Přepnout jazyk na angličtinu", "Switch language to Czech"))
            }
            .frame(width: 132, alignment: .trailing)
        }
        .padding(.horizontal, 22).padding(.vertical, 15)
        .background(.white.opacity(0.85))
        .overlay(alignment: .bottom) { Rectangle().fill(ink.opacity(0.07)).frame(height: 1) }
    }

    private var nowPlaying: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label(tr("PRÁVĚ HRAJE", "NOW PLAYING"), systemImage: "waveform")
                    .font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundStyle(accent)
                Spacer()
                Text(playbackBadge)
                    .font(.system(size: 9, weight: .bold)).tracking(0.5)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(store.phase == .playing ? accent.opacity(0.10) : store.phase == .connecting ? Color.orange.opacity(0.12) : ink.opacity(0.06), in: Capsule())
                    .foregroundStyle(store.phase == .playing ? accent : store.phase == .connecting ? .orange : muted)
            }
            HStack(spacing: 13) {
                stationArtwork(size: 64, cornerRadius: 15)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.currentStation?.name ?? tr("Vyberte předvolbu", "Choose a preset"))
                        .font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    if let station = store.currentStation {
                        HStack(spacing: 6) {
                            Text(station.technicalDetails.isEmpty ? station.language : station.technicalDetails)
                                .font(.system(size: 10)).foregroundStyle(muted).lineLimit(1)
                            Text(station.bitrateLabel(language: store.language))
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(accent.opacity(0.08), in: Capsule())
                                .lineLimit(1)
                        }
                    }
                    Text(store.songTitle.isEmpty ? tr("Nalaďte stanici nebo ji vyhledejte", "Tune a preset or search for a station") : store.songTitle)
                        .font(.system(size: 12)).foregroundStyle(muted).lineLimit(2)
                }
                Spacer(minLength: 5)
            }
            HStack(spacing: 12) {
                Button(action: store.togglePlayback) {
                    let title: String = switch store.phase {
                    case .playing: tr("Pozastavit", "Pause")
                    case .connecting: tr("Znovu připojit", "Reconnect")
                    default: tr("Přehrát", "Play")
                    }
                    let icon = store.phase == .playing ? "pause.fill" : store.phase == .connecting ? "arrow.clockwise" : "play.fill"
                    Label(title, systemImage: icon)
                        .font(.system(size: 12, weight: .semibold)).frame(width: 126, height: 34)
                }
                .buttonStyle(.borderedProminent).tint(accent).disabled(store.currentStation == nil)
                Button(action: store.stop) { Image(systemName: "stop.fill").font(.system(size: 12)).frame(width: 34, height: 34) }
                    .buttonStyle(.bordered).tint(ink).disabled(store.currentStation == nil)
                Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(muted)
                Slider(value: $store.volume, in: 0...1).tint(accent).frame(maxWidth: 110)
            }
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ink.opacity(0.06), lineWidth: 1))
    }

    private func stationArtwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let rawURL = store.currentStation?.favicon,
               let url = URL(string: rawURL),
               ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    stationArtworkFallback(size: size, cornerRadius: cornerRadius)
                }
            } else {
                stationArtworkFallback(size: size, cornerRadius: cornerRadius)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private func stationArtworkFallback(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius).fill(LinearGradient(colors: [accent, Color(red: 0.08, green: 0.34, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: size * 0.39, weight: .medium)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var playbackBadge: String {
        switch store.phase {
        case .idle: tr("ZASTAVENO", "STOPPED")
        case .connecting: tr("PŘIPOJUJI SE", "CONNECTING")
        case .playing: tr("ŽIVĚ", "LIVE")
        case .paused: tr("PAUZA", "PAUSED")
        case .failed: tr("CHYBA", "ERROR")
        }
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr("PŘEDVOLBY", "PRESETS")).font(.system(size: 10, weight: .bold)).tracking(0.9).foregroundStyle(muted)
                Spacer()
                Text(tr("\(store.presets.filter { !$0.streamURL.isEmpty }.count) / 10 uložených", "\(store.presets.filter { !$0.streamURL.isEmpty }.count) / 10 saved"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<10, id: \.self) { index in presetButton(index) }
            }
        }
    }

    private var searchEntry: some View {
        Button {
            isSearchPresented = true
        } label: {
            Label(tr("Vyhledat stanici", "Search stations"), systemImage: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 42)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
        .keyboardShortcut("f", modifiers: .command)
    }

    private func presetButton(_ index: Int) -> some View {
        let station = store.presets[index]
        let active = store.selectedPreset == index
        return Button {
            store.tune(index)
        } label: {
            HStack(spacing: 9) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? accent : muted)
                    .frame(width: 25, height: 25)
                    .background(active ? accent.opacity(0.10) : ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name.isEmpty ? tr("Prázdná předvolba", "Empty preset") : station.name)
                        .font(.system(size: 11, weight: active ? .semibold : .medium)).foregroundStyle(station.name.isEmpty ? muted : ink).lineLimit(1)
                    Text(station.name.isEmpty ? tr("Vyberte a uložte stanici", "Choose and save a station") : (station.detail(language: store.language).isEmpty ? tr("Internetová stanice", "Internet station") : station.detail(language: store.language)))
                        .font(.system(size: 9)).foregroundStyle(muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                if active && store.isPlaying { Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)).foregroundStyle(accent) }
            }
            .padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? accent.opacity(0.055) : .white.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? accent.opacity(0.28) : ink.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !station.streamURL.isEmpty {
                Button(tr("Přehrát", "Play"), systemImage: "play.fill") { store.tune(index) }
                Button(tr("Odebrat", "Remove"), systemImage: "trash", role: .destructive) { store.removePreset(at: index) }
            }
        }
    }

}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onResolve(window) }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = view.window { onResolve(window) }
        }
    }
}

private struct StationSearchSheet: View {
    @ObservedObject var store: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFieldIsFocused: Bool
    @State private var service = RadioBrowserService()
    @State private var query = ""
    @State private var results: [RadioStation] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var targetSlot = 0
    @State private var isManualEntryExpanded = false
    @State private var manualStationName = ""
    @State private var manualStreamURL = ""
    @State private var manualBitrate = ""
    @State private var manualEntryError: String?
    @State private var searchTask: Task<Void, Never>?

    private func tr(_ czech: String, _ english: String) -> String {
        store.language.text(czech, english)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Najít internetovou stanici", "Find an internet station"))
                        .font(.system(size: 19, weight: .semibold))
                    Text(tr("Vyhledávání přes Radio Browser a další katalogy", "Search Radio Browser and other catalogs"))
                        .font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer()
                Button(tr("Zavřít", "Close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14)).foregroundStyle(muted)
                TextField(tr("Zadejte název stanice", "Enter a station name"), text: $query)
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .focused($searchFieldIsFocused)
                    .onSubmit { startSearch() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        searchError = nil
                        searchFieldIsFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("Vymazat hledání", "Clear search"))
                }
                Button { startSearch() } label: {
                    if isSearching {
                        ProgressView().controlSize(.small).frame(width: 82, height: 30)
                    } else {
                        Label(tr("Hledat", "Search"), systemImage: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(minWidth: 82, minHeight: 30)
                    }
                }
                .buttonStyle(.borderedProminent).tint(accent)
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            .padding(.leading, 13).padding(.trailing, 6).frame(height: 46)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.10), lineWidth: 1))

            HStack(spacing: 8) {
                Text(tr("DALŠÍ KATALOGY", "MORE CATALOGS"))
                    .font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(muted)
                Link(destination: URL(string: "https://new.radia.cz/radia")!) {
                    Label("Radia.cz", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white, in: Capsule())
                }
                .accessibilityLabel(tr("Otevřít katalog českých rádií Radia.cz", "Open the Radia.cz Czech radio directory"))
                Link(destination: providerSearchURL(host: "fmstream.org", path: "/index.php", queryName: "s")) {
                    Label("FMSTREAM", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white, in: Capsule())
                }
                .accessibilityLabel(tr("Vyhledat na FMSTREAM.org", "Search FMSTREAM.org"))
                Link(destination: providerSearchURL(host: "myonlineradio.cz", path: "/vyhledavani", queryName: "search")) {
                    Label("MyOnlineRadio", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.white, in: Capsule())
                }
                .accessibilityLabel(tr("Vyhledat na MyOnlineRadio.cz", "Search MyOnlineRadio.cz"))
                Spacer(minLength: 0)
            }
            .foregroundStyle(accent)
            Text(tr("Otevře se katalog s výběrem streamů. FMSTREAM.org je uveden jako externí zdroj.", "This opens an external catalog of radio streams."))
                .font(.system(size: 10)).foregroundStyle(muted)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isManualEntryExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(tr("Vložit URL streamu", "Add a stream URL"), systemImage: "link")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                    Spacer()
                    Image(systemName: isManualEntryExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isManualEntryExpanded {
                VStack(alignment: .leading, spacing: 9) {
                    TextField(tr("Název stanice", "Station name"), text: $manualStationName)
                        .textFieldStyle(.roundedBorder)
                    TextField(tr("Přímá adresa streamu (https://…)", "Direct stream URL (https://… )"), text: $manualStreamURL)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        TextField(tr("Bitrate v kb/s (volitelné)", "Bitrate in kb/s (optional)"), text: $manualBitrate)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 180)
                        Picker(tr("Uložit do předvolby", "Save to preset"), selection: $targetSlot) {
                            ForEach(0..<10, id: \.self) { i in
                                Text("\(String(format: "%02d", i + 1))  \(store.presets[i].name.isEmpty ? tr("Prázdná", "Empty") : store.presets[i].name)").tag(i)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 200)
                        Spacer(minLength: 0)
                        Button(tr("Uložit stanici", "Save station")) { saveManualStation() }
                            .buttonStyle(.borderedProminent).tint(accent)
                    }
                    if let manualEntryError {
                        Text(manualEntryError).font(.system(size: 11)).foregroundStyle(.red)
                    }
                    Text(tr("Vložte přímou adresu audio streamu, ne adresu stránky rádia.", "Enter a direct audio stream URL, not the radio station's webpage."))
                        .font(.system(size: 10)).foregroundStyle(muted)
                }
                .padding(.top, 8)
            }

            if let searchError {
                Label(searchError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !results.isEmpty {
                HStack {
                    Text(tr("VÝSLEDKY · \(results.count)", "RESULTS · \(results.count)"))
                        .font(.system(size: 10, weight: .bold)).tracking(0.7).foregroundStyle(muted)
                    Spacer()
                    Picker(tr("Uložit do předvolby", "Save to preset"), selection: $targetSlot) {
                        ForEach(0..<10, id: \.self) { i in
                            Text("\(String(format: "%02d", i + 1))  \(store.presets[i].name.isEmpty ? tr("Prázdná předvolba", "Empty preset") : store.presets[i].name)").tag(i)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: 190)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { station in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(station.name)
                                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(station.technicalDetails.isEmpty ? station.language : station.technicalDetails)
                                            .font(.system(size: 11)).foregroundStyle(muted).lineLimit(1)
                                            Text(station.bitrateLabel(language: store.language))
                                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                                            .padding(.horizontal, 6).padding(.vertical, 3)
                                            .background(accent.opacity(0.08), in: Capsule())
                                            .lineLimit(1)
                                    }
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(station.streamURL)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(muted)
                                            .lineLimit(2)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(station.streamURL, forType: .string)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 10))
                                                .foregroundStyle(accent)
                                        }
                                        .buttonStyle(.plain)
                                        .help(tr("Zkopírovat úplnou adresu streamu", "Copy the full stream URL"))
                                        .accessibilityLabel(tr("Zkopírovat úplnou adresu streamu", "Copy the full stream URL"))
                                    }
                                }
                                Spacer(minLength: 8)
                                Button {
                                    store.save(station, to: targetSlot)
                                    dismiss()
                                } label: {
                                    Label(tr("Uložit", "Save"), systemImage: "plus")
                                        .font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 9).padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered).tint(accent)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            if station.id != results.last?.id { Divider().padding(.leading, 12) }
                        }
                    }
                }
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.06), lineWidth: 1))
            } else if searchError == nil && !isSearching {
                VStack(spacing: 9) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 28)).foregroundStyle(accent.opacity(0.65))
                    Text(tr("Zadejte název stanice", "Enter a station name"))
                        .font(.system(size: 13, weight: .medium))
                    Text(tr("Výsledky z Radio Browseru se zobrazí zde.", "Radio Browser results will appear here."))
                        .font(.system(size: 11)).foregroundStyle(muted)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(22)
        .background(paper)
        .onAppear {
            searchFieldIsFocused = true
            targetSlot = store.presets.firstIndex(where: { $0.streamURL.isEmpty }) ?? 0
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func startSearch() {
        searchTask?.cancel()
        searchTask = Task { await search() }
    }

    @MainActor
    private func search() async {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isSearching = true
        searchError = nil
        results = []
        do {
            results = try await service.search(name: term)
            if results.isEmpty {
                searchError = store.language.text("Pro „\(term)“ jsme nenašli žádnou stanici.", "No stations found for “\(term)”.")
            }
        } catch {
            if let radioError = error as? RadioBrowserError {
                searchError = radioError.message(language: store.language)
            } else {
                searchError = tr("Vyhledávání se nezdařilo. Zkontrolujte připojení k internetu.", "Search failed. Check your internet connection.")
            }
        }
        isSearching = false
    }

    private func providerSearchURL(host: String, path: String, queryName: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [URLQueryItem(name: queryName, value: query)]
        return components.url ?? URL(string: "https://\(host)\(path)")!
    }

    private func saveManualStation() {
        let name = manualStationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = manualStreamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { manualEntryError = tr("Zadejte název stanice.", "Enter a station name."); return }
        guard let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            manualEntryError = tr("Zadejte platnou přímou adresu HTTP nebo HTTPS streamu.", "Enter a valid direct HTTP or HTTPS stream URL.")
            return
        }
        let station = RadioStation(
            uuid: UUID().uuidString,
            name: name,
            streamURL: url.absoluteString,
            country: "",
            language: "",
            codec: "",
            bitrate: manualBitrate.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        store.save(station, to: targetSlot)
        dismiss()
    }
}
