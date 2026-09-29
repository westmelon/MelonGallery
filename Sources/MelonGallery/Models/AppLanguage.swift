import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
  case system
  case english = "en"
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"

  static let defaultsKey = "appLanguage"

  var id: String { rawValue }

  var locale: Locale {
    switch self {
    case .system:
      .autoupdatingCurrent
    case .english, .simplifiedChinese, .traditionalChinese:
      Locale(identifier: rawValue)
    }
  }

  var title: String {
    switch self {
    case .system:
      L10n.systemDefault
    case .english:
      "English"
    case .simplifiedChinese:
      "简体中文"
    case .traditionalChinese:
      "繁體中文"
    }
  }

  static var stored: AppLanguage {
    guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
          let language = AppLanguage(rawValue: rawValue) else {
      return .system
    }
    return language
  }

  func save() {
    UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
  }

  var localizationBundle: Bundle {
    guard self != .system,
          let localization = Bundle.module.localizations.first(where: {
            $0.caseInsensitiveCompare(rawValue) == .orderedSame
          }),
          let path = Bundle.module.path(forResource: localization, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
      return .module
    }
    return bundle
  }
}
