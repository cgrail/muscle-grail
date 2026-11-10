extension CatalogExercise {
    /// Exercises RepDB lacks, written for Muscle Grail in RepDB's form: names in English, German and Spanish, and steps in
    /// English and German. Their picture is our own, in `Extras/`, named in `images`, never based on RepDB's images: its
    /// license forbids deriving one from them. Their ids are catalog ids like RepDB's, so a RepDB update that brings one of
    /// them replaces ours.
    static let extras = [
        CatalogExercise(
            id: "machine-torso-rotation", name: "Machine Torso Rotation", equipment: "rotary_torso_machine", primaryMuscles: ["obliques"],
            images: ["Extras/machine-torso-rotation.jpeg"],
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
        // Not "glute-kickback": RepDB has that id for the kickback on all fours.
        CatalogExercise(
            id: "machine-glute-kickback", name: "Machine Glute Kickback", equipment: "glute_kickback_machine", primaryMuscles: ["gluteus_maximus"],
            images: ["Extras/machine-glute-kickback.jpeg"],
            instructions: [
                "Start with a light weight. Lie with your upper body on the pad and hold on to the handles. Adjust the pad and foot plate so you lie stably and can place your working foot securely. Have a trainer show you the exact setup on your machine once, as designs differ.",
                "Brace your abs lightly and keep your back in its natural position. Your pelvis stays level on the pad: don't rotate it to the side and don't lift it off the pad.",
                "Push the foot plate back from the bent starting position. Think \"drive the thigh back from the hip\", not just \"straighten the knee\". How much the knee straightens depends on the machine's path; don't force a different movement.",
                "Stop as soon as you can't move the leg further back without moving your pelvis or lower back. Often the thigh is then roughly in line with your torso. Further back isn't automatically better. Squeeze your glutes briefly at the end point.",
                "Let the leg return to the bent starting position with control, for example over about two seconds. Don't let the weight pull you forward or the plates crash together. Breathe out as you push back, breathe in as you return.",
                "Common mistakes: arching your lower back to get the leg further back (shorten the range of motion); rotating the pelvis or lifting it off the pad (reduce the weight and stay stable); pushing with momentum or starting with a jerk (do the rep more slowly); letting the weight drop back uncontrolled (control the way back too).",
                "Remember: extend the hip, not the back. If you have to compensate to do it, the range of motion is too big or the weight too heavy. Stop if you feel pain, especially in your back or a pinching at the front of the hip, and have your setup and technique checked.",
            ],
            level: "beginner", category: "strength", germanName: "Gluteus Kickback am Gerät",
            germanInstructions: [
                "Wähle zunächst ein leichtes Gewicht. Lege dich mit dem Oberkörper auf die Auflage und halte dich an den Griffen fest. Stelle Polster und Fußplatte so ein, dass du stabil liegst und den arbeitenden Fuß sicher aufsetzen kannst. Lass dir die genaue Einstellung an eurem Gerät einmal vom Trainer zeigen, da sich die Bauformen unterscheiden.",
                "Spanne den Bauch leicht an und halte den Rücken in seiner natürlichen Position. Das Becken bleibt gerade auf der Auflage: nicht seitlich aufdrehen und nicht vom Polster abheben.",
                "Drücke die Fußplatte aus der angezogenen Position nach hinten. Denke dabei: „Den Oberschenkel aus der Hüfte nach hinten führen“ – nicht nur das Knie strecken. Ob und wie stark sich das Knie dabei streckt, richtet sich nach der Führung der Maschine; erzwinge keine andere Bewegung.",
                "Beende die Bewegung, sobald du das Bein nicht weiter nach hinten führen kannst, ohne Becken oder unteren Rücken mitzubewegen. Häufig befindet sich der Oberschenkel dann ungefähr in einer Linie mit dem Rumpf. Weiter nach hinten ist nicht automatisch besser. Spanne den Po am Endpunkt kurz bewusst an.",
                "Lass das Bein kontrolliert wieder in die angezogene Ausgangsposition kommen, beispielsweise über etwa zwei Sekunden. Lass dich nicht vom Gewicht nach vorne ziehen und die Gewichte nicht aufeinanderknallen. Beim Zurückdrücken ausatmen, beim Zurückführen einatmen.",
                "Häufige Fehler: Hohlkreuz machen, um das Bein weiter nach hinten zu bekommen (Bewegungsweg verkürzen); Becken aufdrehen oder von der Auflage abheben (Gewicht reduzieren und stabil liegen bleiben); mit Schwung drücken oder ruckartig starten (die Wiederholung langsamer ausführen); Gewicht unkontrolliert zurückfallen lassen (auch den Rückweg aktiv kontrollieren).",
                "Merksatz: Hüfte strecken – nicht den Rücken. Wenn du dafür ausweichen musst, ist der Bewegungsweg zu groß oder das Gewicht zu schwer. Bei Schmerzen, insbesondere im Rücken oder einem Einklemmen vorne in der Hüfte, abbrechen und die Einstellung sowie Ausführung prüfen lassen.",
            ],
            spanishName: "Patada de glúteo en máquina"
        ),
    ]

    /// RepDB's exercises, then our `extras` it doesn't have.
    static func withExtras(_ repdb: [CatalogExercise]) -> [CatalogExercise] {
        repdb + extras.filter { extra in !repdb.contains { $0.id == extra.id } }
    }
}
