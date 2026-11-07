import Foundation

struct RadioStation: Codable, Identifiable, Hashable {
    var id: String { uuid.isEmpty ? streamURL : uuid }
    var uuid: String
    var name: String
    var streamURL: String
    var country: String
    var language: String
    var codec: String
    var bitrate: String
    var favicon: String? = nil

    var technicalDetails: String {
        [country, codec.isEmpty ? nil : codec.uppercased()]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    func bitrateLabel(language: AppLanguage) -> String {
        guard let rate = Int(bitrate), rate > 0 else {
            return language.text("Bitrate neuveden", "Bitrate unavailable")
        }
        return "\(rate) kb/s"
    }

    func detail(language: AppLanguage) -> String {
        let bitrate = bitrateLabel(language: language)
        return [technicalDetails, bitrate == language.text("Bitrate neuveden", "Bitrate unavailable") ? nil : bitrate]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    static let empty = RadioStation(uuid: "", name: "", streamURL: "", country: "", language: "", codec: "", bitrate: "")
}
