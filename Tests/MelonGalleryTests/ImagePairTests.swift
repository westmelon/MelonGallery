import XCTest
@testable import MelonGallery

@MainActor
final class ImagePairTests: XCTestCase {
  func testPairsRespectDirectoryStemAndExtensions() {
    let raw = item("a/PHOTO.Rw2")
    let jpeg = item("a/PHOTO.JpEg")
    let differentDirectory = item("b/PHOTO.JPG")
    let differentStem = item("a/photo.JPG")
    let rawOnly = item("a/alone.RW2")
    let unsupported = item("a/PHOTO.NEF")
    let pairs = ImagePairResolver.pairs(in: [raw, jpeg, differentDirectory, differentStem, rawOnly, unsupported])
    XCTAssertEqual(pairs[raw.id], jpeg)
    XCTAssertEqual(pairs[jpeg.id], raw)
    XCTAssertEqual(pairs.count, 2)

    let jpg = item("a/PHOTO.JPG")
    XCTAssertEqual(ImagePairResolver.pairs(in: [raw, jpg])[raw.id], jpg)
    XCTAssertTrue(ImagePairResolver.pairs(in: [raw, jpg, jpeg]).isEmpty)
  }

  func testHiddenRAWIsPairedWithoutChangingSelectionOrFileState() {
    let keys = ["showRAWFiles", "imageRatings", "favoriteImagePaths"]
    let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, saved) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
      }
    }
    let store = GalleryStore()
    let raw = item("a/PHOTO.RW2")
    let jpeg = item("a/PHOTO.JPG")
    store.items = [jpeg, raw]
    store.showRAWFiles = false
    store.clearFilters()
    store.selectAll()
    XCTAssertEqual(store.selectedItems, [jpeg])
    XCTAssertEqual(store.pairedImage(for: jpeg), raw)
    store.setRating(5, for: raw)
    store.setRating(2, for: jpeg)
    store.toggleFavorite(raw)
    XCTAssertEqual(store.rating(for: raw), 5)
    XCTAssertEqual(store.rating(for: jpeg), 2)
    XCTAssertTrue(store.isFavorite(raw))
    XCTAssertFalse(store.isFavorite(jpeg))
    XCTAssertEqual(store.selectedItems, [jpeg])
    store.items.removeAll { $0.id == raw.id }
    XCTAssertNil(store.pairedImage(for: jpeg))
  }

  func testPairSwitchPreservesNavigationAndRemovalTargetsOnlyCurrentFile() {
    let raw = item("a/PHOTO.RW2")
    let jpeg = item("a/PHOTO.JPG")
    let next = item("a/NEXT.JPG")
    let session = SlideshowSession(items: [jpeg, next], startingAt: jpeg.id)
    session.showPairedImage(raw)
    XCTAssertEqual(session.currentItem, raw)
    XCTAssertEqual(session.items, [jpeg, next])
    session.showPairedImage(jpeg)
    XCTAssertEqual(session.currentItem, jpeg)
    session.showPairedImage(raw)
    session.next()
    XCTAssertEqual(session.currentItem, next)
    session.previous()
    session.showPairedImage(raw)
    XCTAssertTrue(session.removeCurrentItem())
    XCTAssertEqual(session.currentItem, jpeg)
    XCTAssertEqual(session.items, [jpeg, next])

    let visible = SlideshowSession(items: [jpeg, raw, next], startingAt: raw.id)
    visible.showPairedImage(jpeg)
    XCTAssertTrue(visible.removeCurrentItem())
    XCTAssertEqual(visible.currentItem, raw)
    XCTAssertEqual(visible.items, [raw, next])
  }

  private func item(_ path: String) -> ImageItem {
    ImageItem(
      url: URL(fileURLWithPath: "/tmp/MelonPairTests/\(path)"),
      fileSize: 1, modifiedAt: nil, metadata: .empty()
    )
  }
}
