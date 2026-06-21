import SwiftUI

struct GalleryCommands: Commands {
  let store: GalleryStore

  var body: some Commands {
    CommandGroup(after: .newItem) {
      Button(L10n.openFolder) {
        store.chooseFolder()
      }
      .keyboardShortcut("o", modifiers: [.command])
    }

    CommandMenu(L10n.galleryMenu) {
      Button(L10n.startSlideshow) {
        store.startSlideshow()
      }
      .keyboardShortcut(.space, modifiers: [.command])
      .disabled(store.items.isEmpty)

      Button(L10n.selectAll) {
        store.selectAll()
      }
      .keyboardShortcut("a", modifiers: [.command])
      .disabled(store.items.isEmpty)

      Button(L10n.openPreview) {
        store.openFocusedPreview()
      }
      .keyboardShortcut(.return, modifiers: [])
      .disabled(store.focusedID == nil)
    }
  }
}
