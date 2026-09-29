import SwiftUI

struct GalleryDetailView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    VStack(spacing: 0) {
      Group {
        if store.currentFolder == nil {
          EmptyGalleryView {
            store.chooseFolder()
          }
        } else if store.items.isEmpty && !store.isScanning {
          EmptyImagesView()
        } else if store.browsableItems.isEmpty && !store.isScanning {
          VStack(spacing: 12) {
            Label(L10n.rawFilesHidden, systemImage: "eye.slash")
              .foregroundStyle(.secondary)
            Button(L10n.showRAWFiles) {
              store.showRAWFiles = true
            }
          }
        } else if store.filteredItems.isEmpty && !store.isScanning {
          EmptyFilteredImagesView {
            store.clearFilters()
          }
        } else {
          ImageGridView(store: store)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      StatusBarView(store: store)
    }
    .alert(
      L10n.moveSelectedToTrash,
      isPresented: $store.isConfirmingTrashSelection
    ) {
      Button(L10n.cancel, role: .cancel) {}
      Button(L10n.moveToTrash, role: .destructive) {
        store.confirmTrashSelection()
      }
    } message: {
      Text(L10n.trashConfirmation(store.selectedIDs.count))
    }
  }
}

private struct EmptyGalleryView: View {
  let openFolder: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 54))
        .foregroundStyle(.secondary)

      Text(L10n.noFolderSelected)
        .font(.title3)

      Button {
        openFolder()
      } label: {
        Label(L10n.openFolder, systemImage: "folder")
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct EmptyImagesView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "photo")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text(L10n.noImages)
        .font(.title3)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct EmptyFilteredImagesView: View {
  let clearFilters: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "line.3.horizontal.decrease.circle")
        .font(.system(size: 48))
        .foregroundStyle(.secondary)
      Text(L10n.noMatchingImages)
        .font(.title3)
        .foregroundStyle(.secondary)
      Button(L10n.clearFilters, action: clearFilters)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct StatusBarView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    HStack(spacing: 12) {
      if store.isScanning {
        ProgressView()
          .controlSize(.small)
        Text(L10n.scanning)
      }

      Text(
        store.isFilterActive
          ? L10n.filteredImageCount(store.filteredItems.count, total: store.browsableItems.count)
          : L10n.imageCount(store.browsableItems.count)
      )

      Divider()
        .frame(height: 14)

      Text(store.selectedIDs.isEmpty ? L10n.noSelection : L10n.selectedCount(store.selectedIDs.count))

      Spacer()

      if let currentFolder = store.currentFolder {
        Text(currentFolder.path)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(.secondary)
      }

      Divider()
        .frame(height: 14)

      HStack(spacing: 6) {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
        Slider(value: $store.thumbnailSize, in: 80...240, step: 10)
          .frame(width: 130)
      }
      .help(L10n.thumbnailSize)
    }
    .font(.caption)
    .padding(.horizontal, 12)
    .frame(height: 32)
    .background(.bar)
  }
}
