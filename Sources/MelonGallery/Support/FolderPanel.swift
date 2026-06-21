import AppKit

enum FolderPanel {
  @MainActor
  static func chooseFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.title = L10n.openFolder
    panel.prompt = L10n.open
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    return panel.runModal() == .OK ? panel.url : nil
  }
}
