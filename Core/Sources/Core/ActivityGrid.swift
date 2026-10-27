import SwiftUI

/// One column per week, one square per day, with month and weekday labels: gym days red, goals reached blue,
/// short of them light blue. Tapping a day selects it. The iPhone and Mac show it in Activity, the watch from its complication.
public struct ActivityGrid: View {
    let weeks: [GridWeek]
    @Binding var selected: Date

    public init(weeks: [GridWeek], selected: Binding<Date>) {
        self.weeks = weeks
        _selected = selected
    }

    public var body: some View {
        let months = monthLabels(weeks)
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .trailing, spacing: 3) {
                label("").frame(height: 12)
                ForEach(weekdayLabels(), id: \.self) { label($0).frame(height: 11) }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(weeks.indices, id: \.self) { week in
                        VStack(spacing: 3) {
                            label(months[week]?.formatted(.dateTime.month(.abbreviated)) ?? "")
                                .fixedSize() // a month's name runs on over the next columns
                                .frame(width: 11, height: 12, alignment: .leading)
                            ForEach(0..<7, id: \.self) { day in square(weeks[week], day) }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Gym on \(weeks.flatMap(\.days).filter { $0 == 3 }.count) days in the last \(weeks.count) weeks", bundle: .module))
    }

    private func square(_ week: GridWeek, _ day: Int) -> some View {
        let date = Calendar.current.date(byAdding: .day, value: day, to: week.start)!
        return RoundedRectangle(cornerRadius: 2).fill(Self.color(week.days[day])).frame(width: 11, height: 11)
            .overlay {
                if date == selected { RoundedRectangle(cornerRadius: 2).stroke(.primary, lineWidth: 1.5) }
            }
            .contentShape(Rectangle().inset(by: -1.5))
            .onTapGesture { if week.days[day] != nil { selected = date } }
    }

    public static func color(_ level: Int?) -> Color {
        switch level {
        case 3: .red
        case 2: .blue
        case 1: .blue.opacity(0.3)
        case 0: .secondary.opacity(0.15)
        default: .clear
        }
    }

    private func label(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: 9)).foregroundStyle(.secondary)
    }
}
