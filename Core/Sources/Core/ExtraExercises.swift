extension CatalogExercise {
    /// Exercises RepDB lacks, written for Muscle Grail in RepDB's form: names in English, German and Spanish, and steps in
    /// English and German. Their drawing (`Extras/<id>.png`, from `Design/<id>.svg`) is adapted from Open Exercise Art, CC BY-SA
    /// 4.0, never from RepDB's images: its license forbids deriving one from them. Their ids are catalog ids like RepDB's, so a
    /// RepDB update that brings one of them replaces ours.
    static let extras = [
        CatalogExercise(
            id: "machine-torso-rotation", name: "Machine Torso Rotation", equipment: "rotary_torso_machine", primaryMuscles: ["obliques"],
            images: [],
            instructions: [
                "Set the machine to start on one side, then sit down with your knees braced against the pads and your feet flat on the floor.",
                "Rest your chest against the pad and grip the handles in front of your chest.",
                "Brace your core and sit tall, your hips facing forward.",
                "Rotate your upper body to the other side against the resistance, turning from the trunk rather than pulling with the arms.",
                "Pause briefly, then return to the start with control.",
                "Finish your reps, then set the machine to the other side and repeat.",
            ],
            level: "beginner", category: "strength", germanName: "Rumpfdrehung am Gerät",
            germanInstructions: [
                "Stelle die Maschine auf die Startposition einer Seite ein und setze dich, die Knie gegen die Polster und die Füße flach auf dem Boden.",
                "Lege die Brust an das Polster und greife die Griffe vor der Brust.",
                "Spanne den Rumpf an und sitze aufrecht, die Hüfte zeigt nach vorne.",
                "Drehe den Oberkörper gegen den Widerstand zur anderen Seite; die Bewegung kommt aus dem Rumpf, nicht aus den Armen.",
                "Halte kurz und kehre kontrolliert zur Startposition zurück.",
                "Mache alle Wiederholungen, stelle die Maschine dann auf die andere Seite und wiederhole.",
            ],
            spanishName: "Rotación de tronco en máquina"
        ),
    ]

    /// RepDB's exercises, then our `extras` it doesn't have.
    static func withExtras(_ repdb: [CatalogExercise]) -> [CatalogExercise] {
        repdb + extras.filter { extra in !repdb.contains { $0.id == extra.id } }
    }
}
