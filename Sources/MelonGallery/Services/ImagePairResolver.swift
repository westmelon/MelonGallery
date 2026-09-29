import Foundation

enum ImagePairResolver {
  static func pairs(in items: [ImageItem]) -> [ImageItem.ID: ImageItem] {
    let candidates = items.filter {
      ["rw2", "jpg", "jpeg"].contains($0.url.pathExtension.lowercased())
    }
    let groups = Dictionary(grouping: candidates) {
      $0.url.standardizedFileURL.deletingPathExtension()
    }
    var pairs: [ImageItem.ID: ImageItem] = [:]
    for group in groups.values {
      let raws = group.filter(\.isRAW)
      let jpegs = group.filter { !$0.isRAW }
      // Ambiguous groups remain separate files rather than choosing an arbitrary partner.
      guard raws.count == 1, jpegs.count == 1 else { continue }
      pairs[raws[0].id] = jpegs[0]
      pairs[jpegs[0].id] = raws[0]
    }
    return pairs
  }
}
