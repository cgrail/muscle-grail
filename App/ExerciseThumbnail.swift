import Core
import SwiftData
import SwiftUI

/// An exercise's photo: the user's own, else the bundled one, else a symbol.
struct ExerciseThumbnail: View {
    @Query private var entries: [CatalogEntry]
    private let id: String
    private let size: Double
    private let placeholder: String

    init(id: String, size: Double, placeholder: String = "dumbbell") {
        (self.id, self.size, self.placeholder) = (id, size, placeholder)
        _entries = Query(filter: #Predicate { $0.id == id })
    }

    var body: some View {
        Group {
            if let image = entries.first?.photo.flatMap(Photo.image) {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if let url = CatalogExercise.byID[id]?.imageURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { symbol }
            } else {
                symbol
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size / 8))
        .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: placeholder).font(.system(size: size * 0.45)).foregroundStyle(.secondary)
            .frame(width: size, height: size).background(.quaternary)
    }
}
