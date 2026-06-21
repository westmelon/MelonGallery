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
        } else {
          ImageGridView(store: store)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      StatusBarView(store: store)
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

private struct StatusBarView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    HStack(spacing: 12) {
      if store.isScanning {
        ProgressView()
          .controlSize(.small)
        Text(L10n.scanning)
      }

      Text(L10n.imageCount(store.items.count))

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
    }
    .font(.caption)
    .padding(.horizontal, 12)
    .frame(height: 28)
    .background(.bar)
  }
}
