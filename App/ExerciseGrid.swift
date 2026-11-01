#if os(macOS)
import AppKit
import Core
import SwiftUI

/// The exercise library as Finder's icon view: each exercise's photo with its name below, as large as the zoom slider
/// or a pinch on the trackpad makes them. A click selects, a Command-click adds to the selection, a double-click opens.
struct ExerciseGrid<Actions: View>: View {
    let rows: [ExercisesLibrary.Row]
    @Binding var selection: Set<String>
    @Binding var size: Double
    let open: (String) -> Void
    @ViewBuilder let actions: (Set<String>) -> Actions
    @State private var pinchStart: Double?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: size + 12), alignment: .top)], spacing: 12) {
                ForEach(rows) { cell($0) }
            }
            .padding()
        }
        .gesture(
            MagnifyGesture()
                .onChanged { pinch in
                    let start = pinchStart ?? size
                    pinchStart = start
                    let sizes = ExercisesLibrary.thumbnailSizes
                    size = min(max(start * pinch.magnification, sizes.lowerBound), sizes.upperBound)
                }
                .onEnded { _ in pinchStart = nil }
        )
    }

    private func cell(_ row: ExercisesLibrary.Row) -> some View {
        VStack(spacing: 6) {
            ExerciseThumbnail(id: row.id, size: size)
            Text(row.name).font(.callout).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(Color.accentColor.opacity(selection.contains(row.id) ? 0.2 : 0), in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onTapGesture(count: 2) { open(row.id) }
        .simultaneousGesture(TapGesture().onEnded { select(row.id) }) // selects at once, without waiting out a double-click
        .contextMenu { actions(selection.contains(row.id) ? selection : [row.id]) }
    }

    private func select(_ id: String) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.remove(id) == nil { selection.insert(id) }
        } else {
            selection = [id]
        }
    }
}
#endif
