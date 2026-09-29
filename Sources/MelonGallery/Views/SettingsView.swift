import SwiftUI

struct SettingsView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    Form {
      Picker(L10n.language, selection: $store.appLanguage) {
        ForEach(AppLanguage.allCases) { language in
          Text(language.title)
            .tag(language)
        }
      }

      Toggle(L10n.maximizePreviewWindow, isOn: $store.maximizePreviewWindow)
      Toggle(L10n.showRAWFiles, isOn: $store.showRAWFiles)
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
    .environment(\.locale, store.appLanguage.locale)
  }
}
