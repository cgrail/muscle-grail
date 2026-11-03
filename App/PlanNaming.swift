import Core
import SwiftData
import SwiftUI

/// The dice beside a plan's name: gives it the next funny name for what it trains, with its drawing, then lists every funny name
/// to pick another, those for what the plan trains on top.
struct FunnyNameButton: View {
    @Environment(\.modelContext) private var context
    let plan: Plan
    @State private var choosing = false

    var body: some View {
        Button("Funny name", systemImage: "dice") {
            context.rollFunnyName(plan)
            choosing = true
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless) // only the dice, not the whole row
        .help("Funny name")
        .popover(isPresented: $choosing) { FunnyNameList(plan: plan) }
    }
}

/// Every funny name, each with its motto and drawing after it: those for what the plan trains first, then all the others.
/// A tap names the plan after it.
private struct FunnyNameList: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let plan: Plan

    var body: some View {
        let choices = plan.funnyNameChoices
        let others: LocalizedStringKey = choices.proposals.isEmpty ? "All funny names" : "More funny names"
        NavigationStack {
            List {
                if !choices.proposals.isEmpty {
                    Section("For this plan") { rows(choices.proposals) }
                }
                Section(others) { rows(choices.others) }
            }
            .navigationTitle("Funny names")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 380, height: 480) // the popover's
        #endif
    }

    private func rows(_ characters: [FunnyCharacter]) -> some View {
        ForEach(characters) { character in
            let current = character.name == plan.name
            Button {
                context.name(plan, after: character)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: character.name).font(.headline)
                        Text(verbatim: character.motto).font(.caption).italic().foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if current { Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true) }
                    CharacterPicture(character, color: plan.color, size: 44)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(current ? .isSelected : [])
        }
    }
}

/// A plan's picture as a button: it lists every character's drawing to choose another, whatever the plan's name.
struct PictureButton: View {
    let plan: Plan
    let size: Double
    @State private var choosing = false

    var body: some View {
        Button { choosing = true } label: {
            PlanPicture(plan, size: size).overlay(alignment: .bottomTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: max(18, size * 0.22)))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .tint)
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose picture")
        .help("Choose picture")
        .popover(isPresented: $choosing) { PictureChooser(plan: plan) }
    }
}

/// Every character's drawing on a tile in the plan's color, the one the plan shows ringed. A tap makes it the plan's picture.
private struct PictureChooser: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let plan: Plan

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 12)], spacing: 12) {
                    ForEach(allCharacters) { character in
                        let shown = character == plan.character
                        Button {
                            context.choosePicture(character, for: plan)
                            dismiss()
                        } label: {
                            CharacterPicture(character, color: plan.color, size: 72).overlay {
                                if shown { RoundedRectangle(cornerRadius: 18).strokeBorder(.tint, lineWidth: 3) }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: character.name))
                        .accessibilityAddTraits(shown ? .isSelected : [])
                        .help(Text(verbatim: character.name))
                    }
                }
                .padding()
            }
            .navigationTitle("Picture")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 380, height: 440) // the popover's
        #endif
    }
}
