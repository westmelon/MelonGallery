import SwiftUI

struct ContentView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    NavigationSplitView {
      SidebarView(store: store)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    } detail: {
      GalleryDetailView(store: store)
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

      Picker(selection: $store.sortOrder) {
        ForEach(ImageSortOrder.allCases) { order in
          Text(order.title).tag(order)
        }
      } label: {
        Label(L10n.sort, systemImage: "arrow.up.arrow.down")
      }
      .pickerStyle(.menu)
      .frame(width: 150)
      .help(L10n.sort)

      HStack(spacing: 6) {
        Image(systemName: "photo")
          .foregroundStyle(.secondary)
        Slider(value: $store.thumbnailSize, in: 80...240, step: 10)
          .frame(width: 130)
      }
      .help(L10n.thumbnailSize)

      Button {
        store.startSlideshow()
      } label: {
        Label(L10n.startSlideshow, systemImage: "play.rectangle")
      }
      .disabled(store.items.isEmpty)
      .help(L10n.startSlideshow)

      Toggle(isOn: $store.showMetadataInspector) {
        Label(L10n.info, systemImage: "info.circle")
      }
      .toggleStyle(.button)
      .help(L10n.info)
    }
  }
}
