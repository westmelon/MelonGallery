import SwiftUI

struct MetadataInspectorView: View {
  let item: ImageItem?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text(L10n.metadata)
          .font(.headline)

        if let item {
          metadataRows(for: item)
          rawMetadataRows(for: item)
        } else {
          Text(L10n.noSelection)
            .foregroundStyle(.secondary)
        }
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minWidth: 260, idealWidth: 300)
  }

  @ViewBuilder
  private func metadataRows(for item: ImageItem) -> some View {
    let metadata = item.metadata

    MetadataRow(label: L10n.name, value: item.name)
    MetadataRow(label: L10n.path, value: item.url.path)
    MetadataRow(label: L10n.format, value: item.formatName)
    MetadataRow(label: L10n.fileSize, value: ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
    MetadataRow(label: L10n.dimensions, value: dimensionsText(width: item.pixelWidth, height: item.pixelHeight))
    MetadataRow(label: L10n.dateModified, value: dateText(item.modifiedAt))
    MetadataRow(label: L10n.dateTaken, value: dateText(item.dateTaken))
    MetadataRow(label: L10n.camera, value: cameraText(make: metadata.cameraMake, model: metadata.cameraModel))
    MetadataRow(label: L10n.lens, value: metadata.lensModel)
    MetadataRow(label: L10n.iso, value: metadata.iso.map(String.init))
    MetadataRow(label: L10n.aperture, value: apertureText(metadata.aperture))
    MetadataRow(label: L10n.exposureTime, value: exposureText(metadata.exposureTime))
    MetadataRow(label: L10n.focalLength, value: focalLengthText(metadata.focalLength))
    MetadataRow(label: L10n.gps, value: metadata.hasGPS ? L10n.yes : L10n.no)
  }

  @ViewBuilder
  private func rawMetadataRows(for item: ImageItem) -> some View {
    let groups = item.metadata.rawGroups

    if !groups.isEmpty {
      Divider()

      Text(L10n.details)
        .font(.headline)

      ForEach(groups) { group in
        DisclosureGroup(group.name) {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(group.fields) { field in
              MetadataRow(label: field.key, value: field.value)
            }
          }
          .padding(.top, 6)
        }
      }
    }
  }

  private func dimensionsText(width: Int?, height: Int?) -> String? {
    guard let width, let height else {
      return nil
    }
    return "\(width) x \(height)"
  }

  private func dateText(_ date: Date?) -> String? {
    guard let date else {
      return nil
    }

    return date.formatted(date: .abbreviated, time: .standard)
  }

  private func cameraText(make: String?, model: String?) -> String? {
    [make, model]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .nilIfEmpty
  }

  private func apertureText(_ aperture: Double?) -> String? {
    guard let aperture else {
      return nil
    }
    return String(format: "f/%.1f", aperture)
  }

  private func exposureText(_ exposureTime: Double?) -> String? {
    guard let exposureTime else {
      return nil
    }

    if exposureTime > 0, exposureTime < 1 {
      let denominator = Int((1 / exposureTime).rounded())
      return "1/\(denominator) s"
    }

    return String(format: "%.3g s", exposureTime)
  }

  private func focalLengthText(_ focalLength: Double?) -> String? {
    guard let focalLength else {
      return nil
    }
    return String(format: "%.0f mm", focalLength)
  }
}

private struct MetadataRow: View {
  let label: String
  let value: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(value?.nilIfEmpty ?? "-")
        .font(.callout)
        .textSelection(.enabled)
        .lineLimit(3)
        .truncationMode(.middle)
    }
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
