import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

// The catalog as the apps show it: the bundled exercises, with the user's own entries (`CatalogEntry`) on top.
// Plans and sets refer to an exercise only by its catalog id.

public extension CatalogExercise {
    static let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
}

/// The name to show for `id`: the user's own, else the bundled one. A custom exercise whose entry hasn't synced yet gets a placeholder.
public func exerciseName(_ id: String, entry: CatalogEntry?) -> String {
    if let name = entry?.name, !name.isEmpty { return name }
    return CatalogExercise.byID[id]?.name ?? String(localized: "Custom exercise", bundle: .module)
}

/// Up to `limit` catalog names matching `query`, the user's own (`custom`) first: what the plan assistant searches.
public func catalogNames(matching query: String, custom: [String], limit: Int = 8) -> [String] {
    let names = custom.filter { matchesEveryWord(of: query, in: [$0]) } + CatalogExercise.all.filter { $0.matches(query) }.map(\.name)
    return Array(names.prefix(limit))
}

public extension ModelContext {
    /// The catalog id of the exercise called `name`, ignoring case: the user's own first, then the bundled ones.
    func catalogID(named name: String) -> String? {
        let custom = (try? fetch(FetchDescriptor<CatalogEntry>())) ?? []
        return custom.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            ?? CatalogExercise.all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    }

    /// A new exercise of the user's own. Its id is a UUID, so devices can make exercises offline without clashing.
    func createExercise(named name: String) -> String {
        let id = UUID().uuidString
        record(.editExercise(id: id, name: name, details: "", videoURL: ""))
        return id
    }

    /// Changes the fields given and keeps the others. A bundled exercise keeps its name unless one is given.
    func editExercise(_ id: String, name: String? = nil, details: String? = nil, videoURL: String? = nil) {
        let entry = catalogEntry(id)
        record(.editExercise(
            id: id, name: name ?? entry?.name ?? "", details: details ?? entry?.details ?? "", videoURL: videoURL ?? entry?.videoURL ?? ""
        ))
    }

    /// Stores `image` shrunk to sync, or removes the photo for nil. Data that isn't an image changes nothing.
    func setPhoto(_ id: String, to image: Data?) {
        let photo = image.flatMap { Photo.jpeg($0) }
        guard photo != nil || image == nil else { return }
        record(.setPhoto(id: id, photo: photo))
    }
}

public enum Photo {
    /// A JPEG at most `maxPixels` on its longer side, from whatever the photo library hands over.
    public static func jpeg(_ data: Data, maxPixels: Int = 1024) -> Data? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    public static func image(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
