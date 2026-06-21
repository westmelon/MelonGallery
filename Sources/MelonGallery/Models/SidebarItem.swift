import Foundation

enum SidebarItem: Hashable, Identifiable {
  case current
  case recent(URL)
  case favorite(URL)

  var id: String {
    switch self {
    case .current:
      "current"
    case .recent(let url):
      "recent-\(url.path)"
    case .favorite(let url):
      "favorite-\(url.path)"
    }
  }
}
