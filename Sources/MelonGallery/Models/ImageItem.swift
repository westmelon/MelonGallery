import Foundation

struct ImageItem: Identifiable, Hashable, Sendable {
  let id: URL
  let url: URL
  let name: String
  let fileSize: Int64
  let modifiedAt: Date?
  let dateTaken: Date?
  let pixelWidth: Int?
  let pixelHeight: Int?
  let formatName: String
  let metadata: ImageMetadata

  var isRAW: Bool {
    url.pathExtension.lowercased() == "rw2"
  }

  var playsAsAnimation: Bool {
    ["gif", "webp"].contains(url.pathExtension.lowercased())
  }

  init(url: URL, fileSize: Int64, modifiedAt: Date?, metadata: ImageMetadata) {
    self.id = url
    self.url = url
    self.name = url.lastPathComponent
    self.fileSize = fileSize
    self.modifiedAt = modifiedAt
    self.dateTaken = metadata.dateTaken
    self.pixelWidth = metadata.pixelWidth
    self.pixelHeight = metadata.pixelHeight
    self.formatName = metadata.formatName
    self.metadata = metadata
  }
}
