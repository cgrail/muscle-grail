import Foundation
import SwiftData

public extension GymBook.File {
    /// The catalog exercises a GymBook exercise may be, the likeliest first: by its name and, from a backup, its English one.
    func suggestions(for name: String) -> [(id: String, score: Double)] {
        CatalogExercise.closest(to: [name] + [englishNames[name]].compactMap { $0 })
    }
}

public extension GymBook {
    /// The records an import adds, by kind.
    struct ImportSize: Equatable, Sendable {
        public var plans = 0, planExercises = 0, exercises = 0, workouts = 0, sets = 0
        public var total: Int { plans + planExercises + exercises + workouts + sets }
    }
}

public extension ModelContext {
    /// The exercise here each of `file`'s exercises surely is: yours or the catalog's by that name, else the catalog's
    /// whose name in English, German or Spanish is close to its own. One without stays out, to become one of your own.
    func gymBookMatches(_ file: GymBook.File) -> [String: String] {
        file.exercises.reduce(into: [:]) { matches, name in
            matches[name] = catalogID(named: name) ?? file.suggestions(for: name).first.flatMap { $0.score >= 0.85 ? $0.id : nil }
        }
    }

    /// The workouts of `file` that importing it adds: those not imported before.
    func newWorkouts(in file: GymBook.File) -> [GymBook.Session] {
        file.sessions.filter { workout($0.id) == nil }
    }

    /// The names of `file`'s plans you have, which importing leaves as they are: one by that name, or one imported before.
    func gymBookPlansHere(_ file: GymBook.File) -> Set<String> {
        let names = Set(((try? fetch(FetchDescriptor<Plan>())) ?? []).map(\.name))
        return Set(file.plans.map(\.name).filter { names.contains($0) || plan(importedPlan($0)) != nil })
    }

    /// Imports `file`: its plans, each with a funny name for what it trains, apart from those named in `leavingOut` and
    /// those you have (`gymBookPlansHere`), which stay as they are, and each workout with the sets done in it, under the plan
    /// of its name; a plan left out leaves its workouts without one.
    /// `exercises` maps a GymBook name to an exercise here, and one it leaves out becomes your own; without it,
    /// `gymBookMatches` decides. An exercise GymBook last showed in lb shows in lb. Without `history`, only the plans come
    /// in. Returns how many workouts it added: importing the same file again adds none.
    @discardableResult
    func importGymBook(_ file: GymBook.File, exercises: [String: String]? = nil, leavingOut: Set<String> = [], history: Bool = true) -> Int {
        var ids = exercises ?? gymBookMatches(file)
        var used: Set<String> = []
        func id(_ name: String) -> String { // an exercise of your own only once something uses it, so importing again makes none
            let id = ids[name] ?? createExercise(named: name)
            ids[name] = id
            if used.insert(name).inserted, weightUnit(of: id) != .lb, unit(of: name, in: file) == .lb { setUnit(id, to: .lb) }
            return id
        }
        var plans = Dictionary(((try? fetch(FetchDescriptor<Plan>())) ?? []).map { ($0.name, $0.id) }) { first, _ in first }
        for plan in file.plans where plans[plan.name] == nil {
            let imported = importedPlan(plan.name)
            if self.plan(imported) == nil {
                guard !leavingOut.contains(plan.name) else { continue }
                let new = addPlan(id: imported)
                rename(new, to: plan.name) // kept while its exercises tell nothing it trains
                for planned in plan.exercises {
                    setTargets(add(id(planned.exercise), to: new), sets: planned.sets, reps: planned.reps, weightKg: planned.weightKg)
                }
                nameFunnily(new, force: true)
            }
            plans[plan.name] = imported
        }
        let workouts = history ? newWorkouts(in: file) : []
        for session in workouts {
            let done = session.done
            // a plan left out has no id, and a new one matches no plan
            record(.startWorkout(id: session.id, plan: plans[session.plan] ?? UUID(), start: done[0].date))
            for (index, log) in done.enumerated() { // a second apart, so the sets of one minute keep their order
                record(.logSet(id: GymBook.id("set \(index) \(session.key)"), workout: session.id, exerciseID: id(log.exercise),
                               reps: log.reps!, weightKg: log.weightKg, date: log.date.addingTimeInterval(Double(index))))
            }
            record(.finishWorkout(id: session.id, end: done.last!.date.addingTimeInterval(Double(done.count))))
            try? save() // a workout at a time: each change's lookup by id slows with every unsaved one
        }
        return workouts.count
    }

    /// What `importGymBook` with the same choices adds, `workouts` being those it imports (`newWorkouts`, or none without
    /// the history). Each record comes with an entry in the change log, which this leaves out.
    func gymBookImportSize(_ file: GymBook.File, workouts: [GymBook.Session], exercises: [String: String],
                           leavingOut: Set<String>) -> GymBook.ImportSize {
        let plans = gymBookPlansComing(file, leavingOut: leavingOut)
        let entries = Set(gymBookExercisesUsed(file, workouts: workouts, leavingOut: leavingOut).compactMap { name -> String? in // one of your own, or a bundled one's to show in lb
            guard let id = exercises[name] else { return "own \(name)" }
            return catalogEntry(id) == nil && unit(of: name, in: file) == .lb ? id : nil
        })
        return GymBook.ImportSize(plans: plans.count, planExercises: plans.map(\.exercises.count).reduce(0, +), exercises: entries.count,
                                  workouts: workouts.count, sets: workouts.map(\.done.count).reduce(0, +))
    }

    /// The GymBook exercises `importGymBook` with the same choices uses: those of the plans coming in and of `workouts`.
    func gymBookExercisesUsed(_ file: GymBook.File, workouts: [GymBook.Session], leavingOut: Set<String>) -> Set<String> {
        Set(gymBookPlansComing(file, leavingOut: leavingOut).flatMap { $0.exercises.map(\.exercise) } + workouts.flatMap { $0.done.map(\.exercise) })
    }

    /// The plans of `file` importing it adds, each name once: not left out, and not here already.
    private func gymBookPlansComing(_ file: GymBook.File, leavingOut: Set<String>) -> [GymBook.Plan] {
        let here = gymBookPlansHere(file)
        var names: Set<String> = []
        return file.plans.filter { !here.contains($0.name) && !leavingOut.contains($0.name) && names.insert($0.name).inserted }
    }

    /// The records here that an import adds to: plans and their exercises, your exercises, workouts and sets.
    func gymBookRecordCount() -> Int {
        [try? fetchCount(FetchDescriptor<Plan>()), try? fetchCount(FetchDescriptor<PlanItem>()), try? fetchCount(FetchDescriptor<CatalogEntry>()),
         try? fetchCount(FetchDescriptor<Workout>()), try? fetchCount(FetchDescriptor<LoggedSet>())].compactMap { $0 }.reduce(0, +)
    }

    /// The id of the plan imported for GymBook's plan `name`: it gets a funny name, so its name can't tell it.
    private func importedPlan(_ name: String) -> UUID { GymBook.id("plan \(name)") }

    /// The unit GymBook last showed `name`'s weight in, or planned it in.
    private func unit(of name: String, in file: GymBook.File) -> WeightUnit? {
        file.sessions.lazy.flatMap(\.done).first { $0.exercise == name }?.unit
            ?? file.plans.lazy.flatMap(\.exercises).first { $0.exercise == name }?.unit
    }
}
