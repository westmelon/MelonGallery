@preconcurrency import AppKit
import SwiftUI

struct ImagePreviewView: View {
  let item: ImageItem
  @Binding var image: NSImage?
  @Binding var magnification: CGFloat
  let showsGrid: Bool
  let fitRequest: Int
  let actualSizeRequest: Int
  let rawDecodeRequest: Int
  var viewportLink: ImageViewportLink? = nil

  @State private var source: ImageDecodingSource = .image
  @State private var failed = false
  @State private var retryGeneration = 0
  @State private var quickPreview: DecodedImage?
  @State private var displayedItemID: ImageItem.ID?
  @State private var previewItemID: ImageItem.ID?
  @State private var transitionImage: NSImage?
  @State private var rawTransitionPreview: NSImage?
  @State private var isLoading = false
  @State private var fullResolutionItemID: ImageItem.ID?

  private var loadFullResolution: Bool { fullResolutionItemID == item.id }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      Group {
        if let image, displayedItemID == item.id {
          ZoomableImageView(
            image: image,
            magnification: $magnification,
            showsGrid: showsGrid,
            fitRequest: fitRequest,
            actualSizeRequest: actualSizeRequest,
            viewportLink: viewportLink
          )
          .id(item.id)
        } else if let quickPreview, previewItemID == item.id {
          Image(nsImage: quickPreview.image)
            .resizable()
            .scaledToFit()
        } else if let transitionImage = rawTransitionPreview ?? image ?? quickPreview?.image ?? transitionImage {
          Image(nsImage: transitionImage)
            .resizable()
            .scaledToFit()
            .overlay {
              ProgressView()
                .tint(.white)
            }
        } else if failed {
          VStack(spacing: 12) {
            Label(L10n.unableToLoadImage, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.white)
            Button(L10n.retry) {
              retryGeneration += 1
            }
          }
        } else {
          ProgressView()
            .tint(.white)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if let displayedImage = displayedItemID == item.id ? image : quickPreview?.image,
         let title = displayedItemID == item.id ? source.title : quickPreview?.source.title,
         displayedItemID == item.id || previewItemID == item.id {
        HStack(spacing: 6) {
          Text("\(title) · \(Int(displayedImage.size.width)) × \(Int(displayedImage.size.height))")
          if isLoading {
            ProgressView()
              .controlSize(.small)
              .tint(.white)
          }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.7))
        .padding(8)
        .allowsHitTesting(false)
      }
    }
    .overlay(alignment: .topLeading) {
      if item.isRAW, loadFullResolution, !isLoading, quickPreview != nil {
        HStack(spacing: 8) {
          Label(L10n.unableToLoadFullRAW, systemImage: "exclamationmark.triangle")
          Button(L10n.retry) { retryGeneration += 1 }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.7))
        .padding(8)
      }
    }
    .task(id: "\(item.id.path)-\(item.modifiedAt?.timeIntervalSinceReferenceDate ?? 0)-\(retryGeneration)-\(loadFullResolution)") {
      // Keep the small embedded preview across navigation, never the full RAW buffer.
      transitionImage = rawTransitionPreview ?? (source == .fullResolutionRAW ? nil : image) ?? quickPreview?.image ?? transitionImage
      rawTransitionPreview = nil
      image = nil
      quickPreview = nil
      displayedItemID = nil
      previewItemID = nil
      failed = false
      isLoading = true
      let result = await ImageDecoder.preview(at: item.url, onPreview: { preview in
        guard !Task.isCancelled else { return }
        quickPreview = preview
        rawTransitionPreview = preview.image
        previewItemID = item.id
        transitionImage = nil
      }, loadFullResolution: !item.isRAW || loadFullResolution, cachesFullResolution: false)
      guard !Task.isCancelled else { return }
      // 完整解析失败时保留当前文件已发布的预览，继续显示失败提示和重试入口。
      let decoded = result ?? (previewItemID == item.id ? quickPreview : nil)
      source = decoded?.source ?? .image
      if let decoded, decoded.source == .embeddedPreview || decoded.source == .systemPreview {
        rawTransitionPreview = decoded.image
        image = nil
        displayedItemID = nil
        quickPreview = decoded
        previewItemID = item.id
      } else {
        image = decoded?.image
        displayedItemID = decoded == nil ? nil : item.id
        quickPreview = nil
        previewItemID = nil
      }
      transitionImage = nil
      failed = decoded == nil
      isLoading = false
    }
    .onChange(of: item.id) { _, _ in
      fullResolutionItemID = nil
    }
    .onChange(of: rawDecodeRequest) { _, _ in
      guard item.isRAW, image == nil, !(loadFullResolution && isLoading) else { return }
      fullResolutionItemID = item.id
      retryGeneration += 1
    }
    .onDisappear {
      image = nil
      quickPreview = nil
      transitionImage = nil
      rawTransitionPreview = nil
    }
  }
}
