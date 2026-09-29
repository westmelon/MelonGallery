import AppKit
import SwiftUI

struct SlideshowView: View {
  @Bindable var session: SlideshowSession
  @Bindable var store: GalleryStore
  let autoplay: Bool
  let close: () -> Void

  @State private var showInspector = false
  @State private var magnification: CGFloat = 1
  @State private var showsGrid = false
  @State private var fitRequest = 0
  @State private var actualSizeRequest = 0
  @State private var rawDecodeRequest = 0
  @State private var image: NSImage?

  var body: some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      HStack(spacing: 0) {
        VStack(spacing: 0) {
          ZStack {
            if let currentItem = session.currentItem {
              SlideshowImageView(
                item: currentItem,
                image: $image,
                magnification: $magnification,
                showsGrid: showsGrid,
                fitRequest: fitRequest,
                actualSizeRequest: actualSizeRequest,
                rawDecodeRequest: rawDecodeRequest
              )
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          SlideshowHUD(
            session: session,
            store: store,
            autoplay: autoplay,
            showInspector: showInspector,
            showsGrid: showsGrid,
            magnification: magnification,
            canZoom: image != nil,
            toggleGrid: {
              showsGrid.toggle()
            },
            toggleInspector: {
              showInspector.toggle()
            },
            zoomOut: {
              magnification = max(magnification / 1.25, 0.01)
            },
            zoomIn: {
              magnification = min(magnification * 1.25, 8)
            },
            fitImage: {
              fitRequest += 1
            },
            showActualSize: {
              actualSizeRequest += 1
            },
            parseRAW: {
              rawDecodeRequest += 1
            },
            deleteCurrentItem: {
              deleteCurrentItem()
            }
          )
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
    .environment(\.locale, store.appLanguage.locale)
    .id(store.appLanguage)
    .onChange(of: session.currentItem?.id) { _, _ in
      fitRequest += 1
    }
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
    case 24:
      if image != nil { magnification = min(magnification * 1.25, 8) }
      return true
    case 27:
      if image != nil { magnification = max(magnification / 1.25, 0.01) }
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
      if autoplay {
        session.togglePause()
      } else {
        close()
      }
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
  let showsGrid: Bool
  let magnification: CGFloat
  let canZoom: Bool
  let toggleGrid: () -> Void
  let toggleInspector: () -> Void
  let zoomOut: () -> Void
  let zoomIn: () -> Void
  let fitImage: () -> Void
  let showActualSize: () -> Void
  let parseRAW: () -> Void
  let deleteCurrentItem: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(session.currentItem?.name ?? "")
        .lineLimit(1)
        .truncationMode(.middle)

      Spacer()

      if let currentItem = session.currentItem {
        if let paired = store.pairedImage(for: currentItem) {
          Button {
            session.showPairedImage(paired)
          } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
          }
          .buttonStyle(.plain)
          .help(paired.isRAW ? L10n.switchToRAW : L10n.switchToJPEG)
          .accessibilityLabel(paired.isRAW ? L10n.switchToRAW : L10n.switchToJPEG)

          Button {
            store.comparePairedImage(for: currentItem)
          } label: {
            Image(systemName: "rectangle.split.2x1")
          }
          .buttonStyle(.plain)
          .help(L10n.compareRAWAndJPEG)
          .accessibilityLabel(L10n.compareRAWAndJPEG)
        }

        if currentItem.isRAW {
          Button(action: parseRAW) {
            Text("RAW")
          }
          .buttonStyle(.plain)
          .help(L10n.parseRAW)
          .accessibilityLabel(L10n.parseRAW)
          .disabled(canZoom)
        }

        if !currentItem.playsAsAnimation {
          Button(action: zoomOut) {
            Image(systemName: "minus.magnifyingglass")
          }
          .buttonStyle(.plain)
          .help(L10n.zoomOut)
          .disabled(!canZoom)

          Text(canZoom ? "\(Int((magnification * 100).rounded()))%" : "--")
            .monospacedDigit()
            .frame(minWidth: 42)

          Button(action: zoomIn) {
            Image(systemName: "plus.magnifyingglass")
          }
          .buttonStyle(.plain)
          .help(L10n.zoomIn)
          .disabled(!canZoom)

          Button(action: fitImage) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
          }
          .buttonStyle(.plain)
          .help(L10n.fitToWindow)

          Button(action: showActualSize) {
            Text("1:1")
          }
          .buttonStyle(.plain)
          .help(L10n.actualSize)
          .disabled(!canZoom)

          Button(action: toggleGrid) {
            Image(systemName: showsGrid ? "square.grid.3x3.fill" : "square.grid.3x3")
          }
          .buttonStyle(.plain)
          .help(L10n.ruleOfThirds)

          Divider()
            .frame(height: 14)
        }

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

struct RatingControl: View {
  let rating: Int
  var unratedColor: Color = .white
  let setRating: (Int) -> Void

  var body: some View {
    HStack(spacing: 3) {
      ForEach(1...5, id: \.self) { value in
        Button {
          setRating(value == rating ? 0 : value)
        } label: {
          Image(systemName: value <= rating ? "star.fill" : "star")
            .foregroundStyle(value <= rating ? .yellow : unratedColor)
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
  @Binding var image: NSImage?
  @Binding var magnification: CGFloat
  let showsGrid: Bool
  let fitRequest: Int
  let actualSizeRequest: Int
  let rawDecodeRequest: Int

  var body: some View {
    Group {
      if item.playsAsAnimation {
        AnimatedImageView(url: item.url)
      } else {
        ImagePreviewView(
          item: item,
          image: $image,
          magnification: $magnification,
          showsGrid: showsGrid,
          fitRequest: fitRequest,
          actualSizeRequest: actualSizeRequest,
          rawDecodeRequest: rawDecodeRequest
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
