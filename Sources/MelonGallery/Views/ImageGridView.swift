import AppKit
import QuartzCore
import SwiftUI

struct ImageGridView: View {
  @Bindable var store: GalleryStore
  @State private var keyboardFocusToken = 0
  @State private var suppressFocusedScrollForID: ImageItem.ID?

  var body: some View {
    GeometryReader { geometry in
      let thumbnailSize = CGFloat(store.thumbnailSize)
      let cellWidth = max(thumbnailSize + 20, 108)
      let spacing: CGFloat = 10
      let gridPadding: CGFloat = 14
      let contentWidth = max(geometry.size.width - gridPadding * 2, 0)
      let columns = max(Int((contentWidth + spacing) / (cellWidth + spacing)), 1)
      let gridItems = Array(
        repeating: GridItem(.fixed(cellWidth), spacing: spacing, alignment: .top),
        count: columns
      )

      ScrollViewReader { scrollProxy in
        ScrollView {
          LazyVGrid(columns: gridItems, alignment: .leading, spacing: spacing) {
            ForEach(store.filteredItems) { item in
              let contextSelectionIsFavorite = store.selectedIDs.contains(item.id)
                ? store.allSelectedItemsAreFavorite
                : store.isFavorite(item)

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
              .onTapGesture {
                keyboardFocusToken += 1
                let modifierFlags = NSApp.currentEvent?.modifierFlags ?? []
                if item.id != store.focusedID {
                  suppressFocusedScrollForID = item.id
                }
                store.select(
                  item.id,
                  extending: modifierFlags.contains(.shift),
                  toggling: modifierFlags.contains(.command)
                )
              }
              .simultaneousGesture(
                TapGesture(count: 2)
                  .onEnded {
                    store.openPreview(item)
                  }
              )
              .onDrag {
                store.prepareSelection(forContextItem: item.id)
                return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
              }
              .contextMenu {
                Button {
                  store.prepareSelection(forContextItem: item.id)
                  store.openPreview(item)
                } label: {
                  Label(L10n.openPreview, systemImage: "eye")
                }

                Button {
                  store.compareSelectedImages()
                } label: {
                  Label(L10n.compareImages, systemImage: "rectangle.split.2x1")
                }
                .disabled(!store.selectedIDs.contains(item.id) || !store.canCompareSelection)

                if let paired = store.pairedImage(for: item) {
                  Button {
                    store.openPairedPreview(for: item)
                  } label: {
                    Label(paired.isRAW ? L10n.switchToRAW : L10n.switchToJPEG, systemImage: "arrow.triangle.2.circlepath")
                  }

                  Button {
                    store.comparePairedImage(for: item)
                  } label: {
                    Label(L10n.compareRAWAndJPEG, systemImage: "rectangle.split.2x1")
                  }
                }

                Button {
                  store.prepareSelection(forContextItem: item.id)
                  store.toggleFavoriteForSelection()
                } label: {
                  Label(
                    contextSelectionIsFavorite ? L10n.unfavorite : L10n.favorite,
                    systemImage: contextSelectionIsFavorite ? "heart.slash" : "heart"
                  )
                }

                Menu {
                  ForEach(1...5, id: \.self) { rating in
                    Button("\(L10n.rating) \(rating)") {
                      store.prepareSelection(forContextItem: item.id)
                      store.setRatingForSelection(rating)
                    }
                  }

                  Divider()

                  Button(L10n.clearRating) {
                    store.prepareSelection(forContextItem: item.id)
                    store.setRatingForSelection(0)
                  }
                } label: {
                  Label(L10n.rating, systemImage: "star")
                }

                Button {
                  store.prepareSelection(forContextItem: item.id)
                  store.startSlideshow()
                } label: {
                  Label(L10n.startSlideshow, systemImage: "play.rectangle")
                }

                Button {
                  store.prepareSelection(forContextItem: item.id)
                  store.copySelectedToFolder()
                } label: {
                  Label(L10n.copySelectedToFolder, systemImage: "doc.on.doc")
                }
                .disabled(store.isCopyingSelection)

                Button {
                  store.prepareSelection(forContextItem: item.id)
                  store.revealSelectionInFinder()
                } label: {
                  Label(L10n.showInFinder, systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                  store.prepareSelection(forContextItem: item.id)
                  store.requestTrashSelection()
                } label: {
                  Label(L10n.moveToTrash, systemImage: "trash")
                }
              }
            }
          }
          .padding(gridPadding)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .background(SmoothMouseWheelView())
        }
        .contentMargins(.trailing, 8, for: .scrollIndicators)
        .overlay {
          KeyboardCaptureView(focusToken: keyboardFocusToken) { event in
            handleKeyDown(event, columns: columns)
          }
        }
        .onChange(of: store.focusedID) { _, newValue in
          guard let newValue else {
            suppressFocusedScrollForID = nil
            return
          }
          if suppressFocusedScrollForID == newValue {
            suppressFocusedScrollForID = nil
            return
          }
          suppressFocusedScrollForID = nil
          withAnimation(.easeOut(duration: 0.2)) {
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
    case 49:
      store.openFocusedPreview()
      return true
    case 51, 117:
      store.requestTrashSelection()
      return true
    case 53:
      if store.searchText.isEmpty {
        store.clearSelection()
      } else {
        store.searchText = ""
      }
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

  @State private var thumbnailState: ThumbnailState = .loading
  @State private var retryGeneration = 0

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(.quaternary.opacity(0.25))

        switch thumbnailState {
        case .loaded(let image):
          ThumbnailImageView(image: image)
            .padding(6)

        case .loading:
          ProgressView()
            .controlSize(.small)

        case .failed:
          Button {
            retryGeneration += 1
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.title3)
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
          .buttonStyle(.plain)
          .help(L10n.retryThumbnail)
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
        .lineLimit(1)
        .truncationMode(.middle)
        .multilineTextAlignment(.center)
        .frame(width: size + 12, height: 18, alignment: .top)
        .help(item.name)
    }
    .padding(4)
    .frame(width: max(size + 20, 108), height: size + 36, alignment: .top)
    .background {
      RoundedRectangle(cornerRadius: 8)
        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
    }
    .contentShape(Rectangle())
    .task(
      id: "\(item.id.path)-\(Int(size))-\(item.modifiedAt?.timeIntervalSinceReferenceDate ?? 0)-\(retryGeneration)",
      priority: .utility
    ) {
      thumbnailState = .loading
      let image = await thumbnailService.thumbnail(
        for: item.url,
        modifiedAt: item.modifiedAt,
        pointSize: size,
        scale: NSScreen.main?.backingScaleFactor ?? 2
      )

      guard !Task.isCancelled else {
        return
      }
      thumbnailState = image.map(ThumbnailState.loaded) ?? .failed
    }
    .onDisappear {
      thumbnailState = .loading
    }
  }
}

private enum ThumbnailState {
  case loading
  case loaded(NSImage)
  case failed
}

private struct ThumbnailImageView: NSViewRepresentable {
  let image: NSImage

  func makeNSView(context: Context) -> NSImageView {
    let view = NSImageView()
    view.imageAlignment = .alignCenter
    view.imageScaling = .scaleProportionallyUpOrDown
    return view
  }

  func updateNSView(_ view: NSImageView, context: Context) {
    if view.image !== image { view.image = image }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? image.size.width, height: proposal.height ?? image.size.height)
  }

  static func dismantleNSView(_ view: NSImageView, coordinator: ()) {
    view.image = nil
  }
}

private struct SmoothMouseWheelView: NSViewRepresentable {
  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> ScrollViewLocator {
    let view = ScrollViewLocator()
    view.onMoveToWindow = { [weak coordinator = context.coordinator] view in
      DispatchQueue.main.async {
        coordinator?.attach(toAncestorOf: view)
      }
    }
    return view
  }

  func updateNSView(_ nsView: ScrollViewLocator, context: Context) {}

  static func dismantleNSView(_ nsView: ScrollViewLocator, coordinator: Coordinator) {
    coordinator.stop()
  }

  @MainActor
  final class Coordinator {
    private weak var scrollView: NSScrollView?
    private var eventMonitor: Any?
    private var targetY: CGFloat?
    private var animationGeneration = 0

    func attach(toAncestorOf view: NSView) {
      var ancestor = view.superview
      while let current = ancestor, !(current is NSScrollView) {
        ancestor = current.superview
      }
      guard let scrollView = ancestor as? NSScrollView,
            scrollView !== self.scrollView else {
        return
      }

      stop()
      self.scrollView = scrollView
      eventMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.scrollWheel, .leftMouseDown, .rightMouseDown, .keyDown]
      ) { [weak self] event in
        guard let self else { return event }
        return self.handle(event)
      }
    }

    func stop() {
      if let eventMonitor {
        NSEvent.removeMonitor(eventMonitor)
      }
      cancelAnimation()
      eventMonitor = nil
      scrollView = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      guard let scrollView, event.window === scrollView.window else {
        return event
      }
      guard event.type == .scrollWheel,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            !event.hasPreciseScrollingDeltas,
            event.momentumPhase.isEmpty,
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
            abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
            event.scrollingDeltaY != 0 else {
        cancelAnimation()
        return event
      }

      let location = scrollView.convert(event.locationInWindow, from: nil)
      guard scrollView.bounds.contains(location),
            let documentView = scrollView.documentView else {
        return event
      }

      let clipView = scrollView.contentView
      let maximumY = max(documentView.bounds.height - clipView.bounds.height, 0)
      let currentY = clipView.bounds.origin.y
      // 反向滚动从当前位置开始，立即取消前一方向的剩余位移。
      let isReversing = ((targetY ?? currentY) - currentY) * event.scrollingDeltaY > 0
      let currentTarget = isReversing ? currentY : (targetY ?? currentY)
      let newTarget = min(max(currentTarget - event.scrollingDeltaY * 36, 0), maximumY)
      if isReversing {
        cancelAnimation()
      }
      guard newTarget != currentTarget else {
        return nil
      }

      targetY = newTarget
      animationGeneration += 1
      let generation = animationGeneration

      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.61, 0.36, 1)
        clipView.animator().setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: newTarget))
      } completionHandler: { [weak self] in
        Task { @MainActor [weak self] in
          self?.finishAnimation(generation: generation)
        }
      }

      return nil
    }

    private func cancelAnimation() {
      guard targetY != nil, let clipView = scrollView?.contentView else { return }
      animationGeneration += 1
      targetY = nil
      let currentOrigin = clipView.bounds.origin
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0
        clipView.animator().setBoundsOrigin(currentOrigin)
      }
    }

    private func finishAnimation(generation: Int) {
      guard generation == animationGeneration else {
        return
      }
      targetY = nil
      if let scrollView {
        scrollView.reflectScrolledClipView(scrollView.contentView)
      }
    }
  }
}

private final class ScrollViewLocator: NSView {
  var onMoveToWindow: ((NSView) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onMoveToWindow?(self)
  }
}
