import AppKit
import SwiftUI

struct SlideshowView: View {
  @Bindable var session: SlideshowSession
  @Bindable var store: GalleryStore
  let autoplay: Bool
  let close: () -> Void

  @State private var showInspector = false

  var body: some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      HStack(spacing: 0) {
        ZStack {
          if let currentItem = session.currentItem {
            SlideshowImageView(item: currentItem)
              .padding(28)
          }

          VStack {
            Spacer()
            SlideshowHUD(
              session: session,
              store: store,
              autoplay: autoplay,
              showInspector: showInspector,
              toggleInspector: {
                showInspector.toggle()
              },
              deleteCurrentItem: {
                deleteCurrentItem()
              }
            )
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if showInspector {
          MetadataInspectorView(item: session.currentItem)
            .frame(width: 320)
            .background(.regularMaterial)
        }
      }
    }
    .overlay {
      KeyboardCaptureView { event in
        handleKeyDown(event)
      }
    }
    .frame(minWidth: 640, minHeight: 420)
  }

  private func deleteCurrentItem() {
    guard let currentItem = session.currentItem,
          store.trash(currentItem) else {
      return
    }

    guard session.removeCurrentItem() else {
      close()
      return
    }

    if let currentItem = session.currentItem {
      store.select(currentItem.id, extending: false, toggling: false)
    }
  }

  private func handleKeyDown(_ event: NSEvent) -> Bool {
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
      return false
    }

    switch event.keyCode {
    case 18, 83:
      setRating(1)
      return true
    case 19, 84:
      setRating(2)
      return true
    case 20, 85:
      setRating(3)
      return true
    case 21, 86:
      setRating(4)
      return true
    case 23, 87:
      setRating(5)
      return true
    case 29, 82:
      setRating(0)
      return true
    case 3:
      toggleFavorite()
      return true
    case 34:
      showInspector.toggle()
      return true
    case 51, 117:
      deleteCurrentItem()
      return true
    case 49:
      guard autoplay else {
        return false
      }
      session.togglePause()
      return true
    case 123:
      session.previous()
      return true
    case 124:
      session.next()
      return true
    case 53:
      close()
      return true
    default:
      return false
    }
  }

  private func setRating(_ rating: Int) {
    guard let currentItem = session.currentItem else {
      return
    }
    store.setRating(rating, for: currentItem)
  }

  private func toggleFavorite() {
    guard let currentItem = session.currentItem else {
      return
    }
    store.toggleFavorite(currentItem)
  }
}

private struct SlideshowHUD: View {
  @Bindable var session: SlideshowSession
  @Bindable var store: GalleryStore
  let autoplay: Bool
  let showInspector: Bool
  let toggleInspector: () -> Void
  let deleteCurrentItem: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(session.currentItem?.name ?? "")
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer()

      if let currentItem = session.currentItem {
        RatingControl(rating: store.rating(for: currentItem)) { rating in
          store.setRating(rating, for: currentItem)
        }

        Button {
          store.toggleFavorite(currentItem)
        } label: {
          Image(systemName: store.isFavorite(currentItem) ? "heart.fill" : "heart")
        }
        .buttonStyle(.plain)
        .foregroundStyle(store.isFavorite(currentItem) ? .red : .white)
        .help(store.isFavorite(currentItem) ? L10n.unfavorite : L10n.favorite)

        Button(role: .destructive) {
          deleteCurrentItem()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(L10n.moveToTrash)

        Button {
          toggleInspector()
        } label: {
          Image(systemName: showInspector ? "info.circle.fill" : "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(L10n.info)
      }

      if autoplay && session.isPaused {
        Text(L10n.paused)
          .fontWeight(.semibold)
      }

      Text(session.counterText)
        .monospacedDigit()
    }
    .font(.caption)
    .foregroundStyle(.white)
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
  }
}

private struct RatingControl: View {
  let rating: Int
  let setRating: (Int) -> Void

  var body: some View {
    HStack(spacing: 3) {
      ForEach(1...5, id: \.self) { value in
        Button {
          setRating(value == rating ? 0 : value)
        } label: {
          Image(systemName: value <= rating ? "star.fill" : "star")
            .foregroundStyle(value <= rating ? .yellow : .white)
        }
        .buttonStyle(.plain)
        .help(value == rating ? L10n.clearRating : "\(L10n.rating) \(value)")
      }
    }
    .accessibilityLabel(L10n.rating)
  }
}

private struct SlideshowImageView: View {
  let item: ImageItem
  @State private var image: NSImage?

  var body: some View {
    Group {
      if item.playsAsAnimation {
        AnimatedImageView(url: item.url)
      } else if let image {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
      } else {
        ProgressView()
          .controlSize(.regular)
          .tint(.white)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task(id: item.id) {
      image = ImageDecoder.displayImage(at: item.url, maxPixelSize: 4096)
    }
  }
}
