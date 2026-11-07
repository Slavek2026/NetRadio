import Foundation

enum AppLanguage: String, Identifiable, Equatable {
    case czech = "cs"
    case english = "en"

    var id: String { rawValue }
    var shortLabel: String { self == .czech ? "CS" : "EN" }
    func text(_ czech: String, _ english: String) -> String {
        self == .czech ? czech : english
    }

    static var saved: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "NetRadio.language") ?? "cs") ?? .czech
    }
}
