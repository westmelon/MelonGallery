import AppKit
import SwiftUI

struct ContentView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    NavigationSplitView {
      SidebarView(store: store)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    } detail: {
      GalleryDetailView(store: store)
        .alert(
          L10n.copyComplete,
          isPresented: Binding(
            get: { store.copyResultMessage != nil },
            set: { if !$0 { store.copyResultMessage = nil } }
          )
        ) {
          Button(L10n.ok, role: .cancel) {
            store.copyResultMessage = nil
          }
        } message: {
          Text(store.copyResultMessage ?? "")
        }
        .inspector(isPresented: $store.showMetadataInspector) {
          MetadataInspectorView(item: store.focusedItem)
        }
    }
    .navigationTitle(L10n.appName)
    .toolbar {
      GalleryToolbar(store: store)
    }
    .onChange(of: store.sidebarSelection) { _, newSelection in
      store.handleSidebarSelection(newSelection)
    }
    .onChange(of: store.recursiveScan) { _, _ in
      store.persistPreferences()
      store.reloadCurrentFolder()
    }
    .onChange(of: store.thumbnailSize) { _, _ in
      store.persistPreferences()
    }
    .onChange(of: store.sortOrder) { _, _ in
      store.applySortOrder()
    }
    .onChange(of: store.sortAscending) { _, _ in
      store.applySortOrder()
    }
    .onChange(of: store.showFavoritesOnly) { _, _ in
      store.applyFilters()
      store.persistBrowsingState()
    }
    .onChange(of: store.searchText) { _, _ in
      store.applyFilters()
      store.persistBrowsingState()
    }
    .onChange(of: store.minimumRating) { _, _ in
      store.applyFilters()
      store.persistBrowsingState()
    }
    .onChange(of: store.focusedID) { _, _ in
      store.persistBrowsingState()
    }
    .onChange(of: store.showMetadataInspector) { _, _ in
      store.persistPreferences()
    }
    .alert(
      L10n.error,
      isPresented: Binding(
        get: { store.errorMessage != nil },
        set: { if !$0 { store.errorMessage = nil } }
      )
    ) {
      Button(L10n.ok, role: .cancel) {
        store.errorMessage = nil
      }
    } message: {
      Text(store.errorMessage ?? "")
    }
  }
}

private struct GalleryToolbar: ToolbarContent {
  @Bindable var store: GalleryStore

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .primaryAction) {
      Button {
        store.chooseFolder()
      } label: {
        Label(L10n.openFolder, systemImage: "folder")
      }
      .help(L10n.openFolder)

      Toggle(isOn: $store.recursiveScan) {
        Label(L10n.recursiveScan, systemImage: "folder.badge.plus")
      }
      .toggleStyle(.button)
      .help(L10n.recursiveScan)

      Button {
        store.startSlideshow()
      } label: {
        Label(L10n.startSlideshow, systemImage: "play.rectangle")
      }
      .disabled(store.filteredItems.isEmpty)
      .help(L10n.startSlideshow)

      Button {
        store.compareSelectedImages()
      } label: {
        Label(L10n.compareImages, systemImage: "rectangle.split.2x1")
      }
      .disabled(!store.canCompareSelection)
      .help(L10n.compareImages)

      Button {
        store.copyFavoritesToFolder()
      } label: {
        Label(L10n.copyFavoritesToFolder, systemImage: "heart.text.square")
      }
      .disabled(store.favoriteImagePaths.isEmpty || store.isCopyingFavorites)
      .help(L10n.copyFavoritesToFolder)

      Toggle(isOn: $store.showMetadataInspector) {
        Label(L10n.info, systemImage: "info.circle")
      }
      .toggleStyle(.button)
      .help(L10n.info)

      Menu {
        ForEach(ImageSortOrder.allCases) { order in
          Button {
            store.sortOrder = order
          } label: {
            if store.sortOrder == order {
              Label(order.title, systemImage: "checkmark")
            } else {
              Text(order.title)
            }
          }
        }
      } label: {
        Label {
          Text(L10n.sort)
        } icon: {
          Image(nsImage: sortDirectionImage(ascending: store.sortAscending))
        }
      } primaryAction: {
        store.sortAscending.toggle()
      }
      .accessibilityLabel(L10n.sort)
      .help("\(store.sortOrder.title) · \(store.sortAscending ? L10n.sortAscending : L10n.sortDescending)")

      Menu {
        Toggle(L10n.showRAWFiles, isOn: $store.showRAWFiles)

        Divider()

        Toggle(L10n.showFavoritesOnly, isOn: $store.showFavoritesOnly)

        Picker(L10n.minimumRating, selection: $store.minimumRating) {
          Text(L10n.anyRating).tag(0)
          ForEach(1...5, id: \.self) { rating in
            Text("\(L10n.rating) \(rating)").tag(rating)
          }
        }

        Divider()

        Button(L10n.clearFilters) {
          store.clearFilters()
        }
        .disabled(!store.isFilterActive)
      } label: {
        Label(
          L10n.filter,
          systemImage: store.isFilterActive
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
        )
      }
      .help(L10n.filter)

      HStack(spacing: 5) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField(L10n.searchImages, text: $store.searchText)
          .textFieldStyle(.roundedBorder)
          .frame(width: 180)
      }
    }
  }
}

private func sortDirectionImage(ascending: Bool) -> NSImage {
  let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
    let path = NSBezierPath()
    path.lineWidth = 1.6
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
      NSPoint(x: x, y: 18 - y)
    }

    let x: CGFloat = ascending ? 15 : 3
    let tip: CGFloat = ascending ? 2 : 16
    let base: CGFloat = ascending ? 16 : 2
    path.move(to: point(x, base))
    path.line(to: point(x, tip))
    path.move(to: point(x - 2, ascending ? 4 : 14))
    path.line(to: point(x, tip))
    path.line(to: point(x + 2, ascending ? 4 : 14))

    for index in 0..<4 {
      let y = CGFloat(3 + index * 4)
      let width = CGFloat(ascending ? 3 + index * 2 : 9 - index * 2)
      let start: CGFloat = ascending ? 1 : 8
      path.move(to: point(start, y))
      path.line(to: point(start + width, y))
    }

    NSColor.black.setStroke()
    path.stroke()
    return true
  }
  image.isTemplate = true
  return image
}
