import SwiftUI

struct GalleryCommands: Commands {
  let store: GalleryStore

  var body: some Commands {
    let _ = store.appLanguage

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
      .disabled(store.filteredItems.isEmpty)

      Button(L10n.selectAll) {
        store.selectAll()
      }
      .keyboardShortcut("a", modifiers: [.command])
      .disabled(store.filteredItems.isEmpty)

      Button(L10n.openPreview) {
        store.openFocusedPreview()
      }
      .keyboardShortcut(.return, modifiers: [])
      .disabled(store.focusedID == nil)

      Button(L10n.compareImages) {
        store.compareSelectedImages()
      }
      .keyboardShortcut("c", modifiers: [.command, .shift])
      .disabled(!store.canCompareSelection)

      Divider()

      Menu(L10n.rating) {
        ForEach(1...5, id: \.self) { rating in
          Button("\(L10n.rating) \(rating)") {
            store.setRatingForSelection(rating)
          }
        }

        Divider()

        Button(L10n.clearRating) {
          store.setRatingForSelection(0)
        }
      }
      .disabled(store.selectedIDs.isEmpty)

      Button(store.allSelectedItemsAreFavorite ? L10n.unfavorite : L10n.favorite) {
        store.toggleFavoriteForSelection()
      }
      .disabled(store.selectedIDs.isEmpty)

      Button(L10n.moveToTrash, role: .destructive) {
        store.requestTrashSelection()
      }
      .keyboardShortcut(.delete, modifiers: [])
      .disabled(store.selectedIDs.isEmpty)

      Button(L10n.copySelectedToFolder) {
        store.copySelectedToFolder()
      }
      .disabled(store.selectedIDs.isEmpty || store.isCopyingSelection)

      Button(L10n.showInFinder) {
        store.revealSelectionInFinder()
      }
      .disabled(store.selectedIDs.isEmpty)

      Divider()

      Button(L10n.copyFavoritesToFolder) {
        store.copyFavoritesToFolder()
      }
      .disabled(store.favoriteImagePaths.isEmpty || store.isCopyingFavorites)
    }
  }
}
