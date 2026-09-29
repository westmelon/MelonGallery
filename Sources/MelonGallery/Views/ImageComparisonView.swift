@preconcurrency import AppKit
import SwiftUI

struct ImageComparisonView: View {
  let items: [ImageItem]
  @Bindable var store: GalleryStore
  let close: () -> Void

  @State private var viewportLink = ImageViewportLink()
  @State private var synchronizesViewports = true
  @State private var swapsSides = false
  @State private var showsGrid = false
  @State private var fitRequest = 0
  @State private var actualSizeRequest = 0
  @State private var rawDecodeRequest = 0

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 16) {
        Text(L10n.compareImages)
          .font(.headline)

        Spacer()

        Toggle(isOn: $synchronizesViewports) {
          Label(L10n.synchronizeViews, systemImage: "link")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(L10n.synchronizeViews)

        Button {
          fitRequest += 1
        } label: {
          Image(systemName: "arrow.down.right.and.arrow.up.left")
        }
        .help(L10n.fitToWindow)
        .accessibilityLabel(L10n.fitToWindow)

        if items.contains(where: { $0.isRAW }) {
          Button {
            rawDecodeRequest += 1
          } label: {
            Text("RAW")
          }
          .help(L10n.parseRAW)
          .accessibilityLabel(L10n.parseRAW)
        }

        Button {
          actualSizeRequest += 1
        } label: {
          Text("1:1")
        }
        .help(L10n.actualSize)
        .accessibilityLabel(L10n.actualSize)

        Toggle(isOn: $showsGrid) {
          Label(L10n.ruleOfThirds, systemImage: "square.grid.3x3")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .help(L10n.ruleOfThirds)

        Button {
          swapsSides.toggle()
        } label: {
          Image(systemName: "arrow.left.arrow.right")
        }
        .help(L10n.swapSides)
        .accessibilityLabel(L10n.swapSides)
      }
      .padding(.horizontal, 16)
      .frame(height: 46)
      .background(.bar)

      HStack(spacing: 1) {
        ForEach(swapsSides ? Array(items.reversed()) : items) { item in
          ComparisonPane(
            item: item,
            store: store,
            viewportLink: viewportLink,
            showsGrid: showsGrid,
            fitRequest: fitRequest,
            actualSizeRequest: actualSizeRequest,
            rawDecodeRequest: rawDecodeRequest
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(.separator)
    }
    .frame(minWidth: 900, minHeight: 480)
    .environment(\.locale, store.appLanguage.locale)
    .overlay {
      KeyboardCaptureView { event in
        guard event.keyCode == 53,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        close()
        return true
      }
    }
    .onChange(of: synchronizesViewports) { _, value in
      viewportLink.isEnabled = value
    }
  }
}

private struct ComparisonPane: View {
  let item: ImageItem
  @Bindable var store: GalleryStore
  let viewportLink: ImageViewportLink
  let showsGrid: Bool
  let fitRequest: Int
  let actualSizeRequest: Int
  let rawDecodeRequest: Int

  @State private var image: NSImage?
  @State private var magnification: CGFloat = 1

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Color.black

        ImagePreviewView(
          item: item,
          image: $image,
          magnification: $magnification,
          showsGrid: showsGrid,
          fitRequest: fitRequest,
          actualSizeRequest: actualSizeRequest,
          rawDecodeRequest: rawDecodeRequest,
          viewportLink: viewportLink
        )
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      VStack(spacing: 8) {
        HStack(spacing: 12) {
          Text(item.name)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(item.url.path)

          Spacer(minLength: 0)

          if let image {
            Text("\(Int(image.size.width)) × \(Int(image.size.height))")
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .fixedSize()
          }
        }

        HStack(spacing: 12) {
          Button {
            magnification = max(magnification / 1.25, 0.01)
          } label: {
            Image(systemName: "minus.magnifyingglass")
          }
          .help(L10n.zoomOut)
          .accessibilityLabel(L10n.zoomOut)
          .disabled(image == nil)

          Text(image == nil ? "--" : "\(Int((magnification * 100).rounded()))%")
            .monospacedDigit()
            .frame(width: 50)

          Button {
            magnification = min(magnification * 1.25, 8)
          } label: {
            Image(systemName: "plus.magnifyingglass")
          }
          .help(L10n.zoomIn)
          .accessibilityLabel(L10n.zoomIn)
          .disabled(image == nil)

          Spacer(minLength: 0)

          RatingControl(rating: store.rating(for: item), unratedColor: .secondary) { rating in
            store.setRating(rating, for: item)
          }

          Button {
            store.toggleFavorite(item)
          } label: {
            Image(systemName: store.isFavorite(item) ? "heart.fill" : "heart")
              .foregroundStyle(store.isFavorite(item) ? Color.red : Color.primary)
          }
          .help(store.isFavorite(item) ? L10n.unfavorite : L10n.favorite)
          .accessibilityLabel(store.isFavorite(item) ? L10n.unfavorite : L10n.favorite)
        }
        .buttonStyle(.plain)
      }
      .font(.caption)
      .padding(12)
      .background(.bar)
    }
  }
}
