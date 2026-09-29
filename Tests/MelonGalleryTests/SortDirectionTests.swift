import XCTest
@testable import MelonGallery

@MainActor
final class SortDirectionTests: XCTestCase {
  func testBothDirectionsForEverySortFieldAndPersistence() {
    withIsolatedSortDefaults {
      let store = GalleryStore()
      let a = item("A.JPG", size: 20, modified: 1, taken: 3)
      let b = item("B.JPG", size: 10, modified: 3, taken: 1)
      let c = item("C.JPG", size: 30, modified: 2, taken: 2)
      let expected: [(ImageSortOrder, [String])] = [
        (.name, ["A.JPG", "B.JPG", "C.JPG"]),
        (.dateTaken, ["B.JPG", "C.JPG", "A.JPG"]),
        (.dateModified, ["A.JPG", "C.JPG", "B.JPG"]),
        (.fileSize, ["B.JPG", "A.JPG", "C.JPG"])
      ]
      store.selectedIDs = [b.id]

      for (order, names) in expected {
        store.items = [c, a, b]
        store.sortOrder = order
        store.sortAscending = true
        store.applySortOrder()
        XCTAssertEqual(store.items.map(\.name), names)

        store.sortAscending = false
        store.applySortOrder()
        XCTAssertEqual(store.items.map(\.name), names.reversed())
        XCTAssertEqual(store.selectedIDs, [b.id])
      }

      let restored = GalleryStore()
      XCTAssertEqual(restored.sortOrder, .fileSize)
      XCTAssertFalse(restored.sortAscending)
    }
  }

  func testMissingCaptureDateRemainsLastInEitherDirection() {
    withIsolatedSortDefaults {
      let store = GalleryStore()
      let first = item("A.JPG", size: 1, modified: 1, taken: 1)
      let second = item("B.JPG", size: 2, modified: 2, taken: 2)
      let missing = item("C.JPG", size: 3, modified: 3, taken: nil)
      store.items = [missing, second, first]
      store.sortOrder = .dateTaken
      store.applySortOrder()
      XCTAssertEqual(store.items.map(\.name), ["A.JPG", "B.JPG", "C.JPG"])
      store.sortAscending = false
      store.applySortOrder()
      XCTAssertEqual(store.items.map(\.name), ["B.JPG", "A.JPG", "C.JPG"])
    }
  }

  private func item(_ name: String, size: Int64, modified: TimeInterval, taken: TimeInterval?) -> ImageItem {
    var metadata = ImageMetadata.empty()
    metadata.dateTaken = taken.map(Date.init(timeIntervalSince1970:))
    return ImageItem(
      url: URL(fileURLWithPath: "/tmp/MelonSortDirectionTests/\(name)"),
      fileSize: size,
      modifiedAt: Date(timeIntervalSince1970: modified),
      metadata: metadata
    )
  }

  private func withIsolatedSortDefaults(_ body: () -> Void) {
    let keys = ["lastFolder", "sortOrder", "sortAscending", "recursiveScan", "thumbnailSize", "showMetadataInspector"]
    let saved = keys.map { UserDefaults.standard.object(forKey: $0) }
    UserDefaults.standard.removeObject(forKey: "lastFolder")
    UserDefaults.standard.removeObject(forKey: "sortOrder")
    UserDefaults.standard.removeObject(forKey: "sortAscending")
    defer {
      for (key, value) in zip(keys, saved) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
      }
    }
    body()
  }
}
