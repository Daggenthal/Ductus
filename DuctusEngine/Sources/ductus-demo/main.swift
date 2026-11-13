// Simulates a learner using the engine so you can watch drills adapt and
// keys unlock, without any UI.
//
//   swift run ductus-demo                  Dvorak home row, seed 1
//   swift run ductus-demo --qwerty         QWERTY home row
//   swift run ductus-demo --seed 7 --drills 300

import DuctusEngine
import DuctusLog
import Foundation

var startingKeys = Array("aoeuidhtns")
var seed: UInt64 = 1
var maxDrills = 400

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--qwerty": startingKeys = Array("asdfghjkl")
    case "--seed": seed = args.next().flatMap(UInt64.init) ?? seed
    case "--drills": maxDrills = args.next().flatMap(Int.init) ?? maxDrills
    default:
        Log.error("Unknown argument: \(arg)")
        exit(2)
    }
}

/// A fake learner. Each key starts slow and error-prone and improves with
/// practice. A few keys are harder than others, to give the engine something to find.
struct SimulatedTypist {
    var practice: [Character: Int] = [:]
    let difficulty: [Character: Double] = ["l": 1.6, "r": 1.4, "c": 1.5, "q": 1.8, "z": 1.8, "x": 1.6]

    mutating func press(_ key: Character, rng: inout SeededGenerator) -> (latency: Double, correct: Bool) {
        let n = Double(practice[key, default: 0])
        practice[key, default: 0] += 1
        let hard = difficulty[key, default: 1]
        let latency = (0.14 + 0.7 * hard * exp(-n / 60)) * Double.random(in: 0.8...1.2, using: &rng)
        let errorRate = 0.015 + 0.2 * hard * exp(-n / 40)
        return (latency, Double.random(in: 0..<1, using: &rng) >= errorRate)
    }
}

let wordList: WordList
do {
    wordList = try WordList.bundledEnglish()
} catch {
    Log.error("Could not load word list: \(error)")
    exit(1)
}

var rng = SeededGenerator(seed: seed)
var trainer = Trainer(wordList: wordList, startingKeys: startingKeys)
var typist = SimulatedTypist()
var clock = 0.0

Log.success("Loaded \(wordList.entries.count) words")
Log.info("Unlock order: \(String(trainer.curriculum.order))")
Log.info("Starting keys: \(String(trainer.curriculum.unlocked))\n")

for drillNumber in 1...maxDrills {
    let focus = trainer.focusKey
    guard let text = trainer.nextDrill(using: &rng) else {
        Log.error("No words can be typed with the unlocked letters.")
        exit(1)
    }
    var session = TypingSession(text: text)
    var unlockedThisDrill: [Character] = []

    while let expected = session.currentExpected {
        let (latency, correct) = typist.press(expected, rng: &rng)
        clock += latency
        let typed: Character = correct ? expected : "#"
        if let keystroke = session.type(typed, at: clock), let unlocked = trainer.record(keystroke) {
            unlockedThisDrill.append(unlocked)
        }
    }

    // Print the first few drills, every unlock, and every 25th drill.
    let summary = session.summary!
    if drillNumber <= 3 || !unlockedThisDrill.isEmpty || drillNumber % 25 == 0 {
        let wpm = String(format: "%.0f", summary.wpm ?? 0)
        let accuracy = String(format: "%.0f%%", summary.accuracy * 100)
        Log.info("#\(drillNumber)  focus: \(focus.map(String.init) ?? "-")  \(wpm) WPM  \(accuracy)")
        Log.info("  \(text)")
    }
    for key in unlockedThisDrill {
        Log.success("  Unlocked \"\(key)\" after drill \(drillNumber). Now: \(String(trainer.curriculum.unlocked))")
    }

    if trainer.curriculum.isFullyUnlocked {
        Log.success("\nAll letters unlocked after \(drillNumber) drills.")
        break
    }
}

if !trainer.curriculum.isFullyUnlocked {
    Log.warning("\nStopped after \(maxDrills) drills with \(trainer.curriculum.unlockedCount) of \(trainer.curriculum.order.count) letters unlocked.")
}

Log.info("\nWeakest keys right now:")
let ranked = trainer.curriculum.unlocked.sorted { trainer.weakness(of: $0) > trainer.weakness(of: $1) }
for key in ranked.prefix(5) {
    let stats = trainer.stats.stats(for: key)
    let wpm = stats?.wpm.map { String(format: "%.0f WPM", $0) } ?? "-"
    let accuracy = stats?.accuracy.value.map { String(format: "%.0f%%", $0 * 100) } ?? "-"
    Log.info("  \(key)  weakness \(String(format: "%.2f", trainer.weakness(of: key)))  \(wpm)  \(accuracy)")
}
