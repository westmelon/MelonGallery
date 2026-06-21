import AppKit
import SwiftUI

struct ImageGridView: View {
  @Bindable var store: GalleryStore

  var body: some View {
    GeometryReader { geometry in
      let thumbnailSize = CGFloat(store.thumbnailSize)
      let cellWidth = max(thumbnailSize + 28, 116)
      let spacing: CGFloat = 14
      let columns = max(Int((geometry.size.width + spacing) / (cellWidth + spacing)), 1)
      let gridItems = Array(
        repeating: GridItem(.fixed(cellWidth), spacing: spacing, alignment: .top),
        count: columns
      )

      ScrollViewReader { scrollProxy in
        ScrollView {
          LazyVGrid(columns: gridItems, alignment: .leading, spacing: spacing) {
            ForEach(store.items) { item in
              ThumbnailCell(
                item: item,
                size: thumbnailSize,
                isSelected: store.selectedIDs.contains(item.id),
                isFocused: store.focusedID == item.id,
                rating: store.rating(for: item),
                isFavorite: store.isFavorite(item),
                thumbnailService: store.thumbnailService
              )
              .id(item.id)
              .onTapGesture(count: 2) {
                store.openPreview(item)
              }
              .onTapGesture {
                let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
                store.select(
                  item.id,
                  extending: modifierFlags.contains(.shift),
                  toggling: modifierFlags.contains(.command)
                )
              }
            }
          }
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay {
          KeyboardCaptureView { event in
            handleKeyDown(event, columns: columns)
          }
        }
        .onChange(of: store.focusedID) { _, newValue in
          guard let newValue else {
            return
          }
          withAnimation(.easeOut(duration: 0.12)) {
            scrollProxy.scrollTo(newValue, anchor: .center)
          }
        }
      }
    }
  }

  private func handleKeyDown(_ event: NSEvent, columns: Int) -> Bool {
    guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
      return false
    }

    let extending = event.modifierFlags.contains(.shift)

    switch event.keyCode {
    case 123:
      store.moveSelection(horizontal: -1, vertical: 0, columns: columns, extending: extending)
      return true
    case 124:
      store.moveSelection(horizontal: 1, vertical: 0, columns: columns, extending: extending)
      return true
    case 125:
      store.moveSelection(horizontal: 0, vertical: 1, columns: columns, extending: extending)
      return true
    case 126:
      store.moveSelection(horizontal: 0, vertical: -1, columns: columns, extending: extending)
      return true
    case 36, 76:
      store.openFocusedPreview()
      return true
    default:
      return false
    }
  }
}

private struct ThumbnailCell: View {
  let item: ImageItem
  let size: CGFloat
  let isSelected: Bool
  let isFocused: Bool
  let rating: Int
  let isFavorite: Bool
  let thumbnailService: ThumbnailService

  @State private var image: NSImage?

  var body: some View {
    VStack(spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(.quaternary.opacity(0.25))

        if let image {
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .padding(6)
        } else {
          ProgressView()
            .controlSize(.small)
        }
      }
      .frame(width: size, height: size)
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
      }
      .overlay(alignment: .bottomTrailing) {
        if isFocused {
          Image(systemName: "circle.fill")
            .font(.system(size: 7))
            .foregroundStyle(Color.accentColor)
            .padding(6)
        }
      }
      .overlay(alignment: .topTrailing) {
        if isFavorite {
          Image(systemName: "heart.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.red)
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
            .padding(5)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if rating > 0 {
          HStack(spacing: 1) {
            ForEach(0..<rating, id: \.self) { _ in
              Image(systemName: "star.fill")
            }
          }
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(.yellow)
          .padding(.horizontal, 5)
          .padding(.vertical, 3)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(5)
        }
      }

      Text(item.name)
        .font(.caption)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .frame(width: size + 18, height: 34, alignment: .top)
    }
    .padding(4)
    .frame(width: max(size + 28, 116), height: size + 54, alignment: .top)
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
    }
    .contentShape(Rectangle())
    .task(id: "\(item.id.path)-\(Int(size))") {
      image = await thumbnailService.thumbnail(
        for: item.url,
        pointSize: size,
        scale: NSScreen.main?.backingScaleFactor ?? 2
      )
    }
  }
}
