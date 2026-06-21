import SwiftUI

struct SidebarView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    VStack(spacing: 0) {
      List(selection: $store.sidebarSelection) {
        Section(L10n.folders) {
          SidebarFolderRow(
            title: L10n.currentFolder,
            detail: store.currentFolder?.lastPathComponent,
            systemImage: "folder"
          )
          .tag(SidebarItem.current)
        }

        Section(L10n.recentOpened) {
          if store.recentFolders.isEmpty {
            Text(L10n.noRecentFolders)
              .foregroundStyle(.secondary)
          } else {
            ForEach(store.recentFolders, id: \.self) { folder in
              SidebarFolderRow(
                title: folder.lastPathComponent,
                detail: folder.deletingLastPathComponent().path,
                systemImage: "clock"
              )
              .tag(SidebarItem.recent(folder))
            }
          }
        }

        Section(L10n.favoriteFolders) {
          if store.favoriteFolders.isEmpty {
            Text(L10n.noFavorites)
              .foregroundStyle(.secondary)
          } else {
            ForEach(store.favoriteFolders, id: \.self) { folder in
              SidebarFolderRow(
                title: folder.lastPathComponent,
                detail: folder.deletingLastPathComponent().path,
                systemImage: "star"
              )
              .tag(SidebarItem.favorite(folder))
              .contextMenu {
                Button(L10n.removeFavorite) {
                  store.removeFavorite(folder)
                }
              }
            }
          }
        }
      }
      .listStyle(.sidebar)

      Divider()

      HStack {
        Button {
          store.addCurrentFolderToFavorites()
        } label: {
          Label(L10n.addFavorite, systemImage: "star")
        }
        .buttonStyle(.borderless)
        .disabled(store.currentFolder == nil)

        Spacer()
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
    }
  }
}

private struct SidebarFolderRow: View {
  let title: String
  let detail: String?
  let systemImage: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .lineLimit(1)

        if let detail, !detail.isEmpty {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
  }
}
