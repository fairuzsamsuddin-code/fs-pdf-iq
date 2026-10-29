import SwiftUI

enum Lang: String { case ms, en }

/// App-wide settings: language (BM default) and appearance (light default).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var lang: Lang {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "lang") }
    }
    /// 0 = light, 1 = dark, 2 = follow device
    @Published var appearance: Int {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
    }

    private init() {
        lang = Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "ms") ?? .ms
        appearance = (UserDefaults.standard.object(forKey: "appearance") as? Int) ?? 0
    }

    var scheme: ColorScheme? {
        switch appearance {
        case 0: return .light
        case 1: return .dark
        default: return nil
        }
    }
}

/// Localised string helper: L("English", "Bahasa Melayu")
func L(_ en: String, _ ms: String) -> String {
    AppSettings.shared.lang == .en ? en : ms
}

struct IQError: LocalizedError {
    let en: String
    let ms: String
    var errorDescription: String? { L(en, ms) }

    static let cannotOpen = IQError(en: "This file could not be opened. It may be damaged or not a supported format.",
                                    ms: "Fail ini tidak dapat dibuka. Ia mungkin rosak atau formatnya tidak disokong.")
    static let locked = IQError(en: "This PDF is password-protected. Use Unlock PDF first.",
                                ms: "PDF ini dilindungi kata laluan. Gunakan Buka Kunci PDF dahulu.")
    static let wrongPassword = IQError(en: "Wrong password.", ms: "Kata laluan salah.")
    static let noPages = IQError(en: "No pages selected.", ms: "Tiada halaman dipilih.")
    static let badRange = IQError(en: "Page range is not valid. Example: 1-3, 5, 8-10",
                                  ms: "Julat halaman tidak sah. Contoh: 1-3, 5, 8-10")
    static let noInput = IQError(en: "Please add a file first.", ms: "Sila tambah fail dahulu.")
    static let saveFailed = IQError(en: "The result could not be saved.", ms: "Hasil tidak dapat disimpan.")
    static let nothingFound = IQError(en: "Nothing was found to extract.", ms: "Tiada apa-apa ditemui untuk diekstrak.")
    static func msg(_ en: String, _ ms: String) -> IQError { IQError(en: en, ms: ms) }
}
