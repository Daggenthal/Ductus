import Foundation
import Testing
@testable import DuctusEngine

@Suite struct StudyTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func words(_ count: Int) -> StudySet {
        let tsv = (0..<count).map { "w\($0)\tr\($0)\tt\($0)\tmeaning \($0)" }.joined(separator: "\n")
        return StudySet(id: "test", language: .chinese, tsv: tsv)
    }

    @Test func hskSetsLoad() throws {
        let hsk1 = try StudySet.bundled("hsk1")
        #expect(hsk1.words.count > 250)
        let nihao = hsk1.words.first { $0.native == "你" }
        #expect(nihao?.typed == "ni")
        #expect(hsk1.words.allSatisfy { $0.typed.allSatisfy { $0.isASCII && $0.isLetter } })
        for (id, _) in StudySet.catalog { #expect(try StudySet.bundled(id).words.count > 150) }
    }

    @Test func goodAnswersSpaceOutAndAgainComesBack() {
        let fsrs = FSRS()
        var card = fsrs.first(.good, now: start)
        let firstGap = card.due.timeIntervalSince(start) / 86_400
        #expect(firstGap >= 2 && firstGap <= 4)  // about 3 days
        var now = card.due
        card = fsrs.review(card, .good, now: now)
        let secondGap = card.due.timeIntervalSince(now) / 86_400
        #expect(secondGap > firstGap * 2)
        now = card.due
        let forgotten = fsrs.review(card, .again, now: now)
        #expect(forgotten.stability < card.stability)
        #expect(forgotten.lapses == 1)
        #expect(forgotten.due.timeIntervalSince(now) <= 2 * 86_400)
        let easy = fsrs.review(card, .easy, now: now)
        let hard = fsrs.review(card, .hard, now: now)
        #expect(easy.stability > hard.stability)
        #expect(easy.difficulty < hard.difficulty)
    }

    @Test func gradesComeFromTyping() {
        #expect(StudyGrader.grade(StudyAttempt(misses: 0, keys: 5, duration: 2.0)) == .easy)
        #expect(StudyGrader.grade(StudyAttempt(misses: 0, keys: 5, duration: 6.0)) == .good)
        #expect(StudyGrader.grade(StudyAttempt(misses: 0, keys: 5, duration: 30)) == .hard)
        #expect(StudyGrader.grade(StudyAttempt(misses: 1, keys: 6, duration: 2)) == .hard)
        #expect(StudyGrader.grade(StudyAttempt(misses: 3, keys: 6, duration: 2)) == .again)
        #expect(StudyGrader.grade(StudyAttempt(misses: 0, keys: 6, duration: 2, usedHint: true)) == .again)
    }

    @Test func dailyPlanLimitsNewWords() {
        let set = words(30)
        var progress = StudyProgress()
        var plan = progress.plan(for: set, now: start, newPerDay: 10, calendar: utc)
        #expect(plan.new.count == 10 && plan.reviews.isEmpty)
        for word in plan.new { progress.record(word, .good, now: start, calendar: utc) }
        plan = progress.plan(for: set, now: start, newPerDay: 10, calendar: utc)
        #expect(plan.new.isEmpty)  // today's 10 are done
        plan = progress.plan(for: set, now: start, newPerDay: 10, extraNew: 5, calendar: utc)
        #expect(plan.new.count == 5 && plan.new.first?.native == "w10")  // Keep Going
        let later = start.addingTimeInterval(5 * 86_400)
        plan = progress.plan(for: set, now: later, newPerDay: 10, calendar: utc)
        #expect(plan.reviews.count == 10 && plan.new.count == 10)
    }

    @Test func knownAfterLongStability() {
        let set = words(1)
        var progress = StudyProgress()
        var now = start
        progress.record(set.words[0], .good, now: now, calendar: utc)
        #expect(!progress.isKnown(set.words[0]))
        for _ in 0..<4 {
            now = progress.cards["w0"]!.due
            progress.record(set.words[0], .good, now: now, calendar: utc)
        }
        #expect(progress.isKnown(set.words[0]))
        #expect(progress.known(in: set).count == 1)
    }

    @Test func sessionLearnsThenRecallsAndRepeatsMisses() {
        let set = words(4)
        var session = StudySession(plan: StudyPlan(reviews: [], new: set.words), gap: 3)
        let order = session.queue.map { step -> String in
            switch step {
            case .learn(let w): "L\(w.native)"
            case .recall(let w): "R\(w.native)"
            }
        }
        #expect(order == ["Lw0", "Lw1", "Lw2", "Rw0", "Lw3", "Rw1", "Rw2", "Rw3"])
        #expect(session.answer(.good) == nil)  // learn steps are not graded
        _ = session.answer(.good)
        _ = session.answer(.good)
        #expect(session.answer(.again) == .again)  // recall w0, missed: graded once
        #expect(session.queue.contains(.recall(set.words[0])))
        while let step = session.current {
            let grade = session.answer(.good)
            if step == .recall(set.words[0]) { #expect(grade == nil) }  // the repeat is not graded again
        }
        #expect(session.isFinished)
    }

    @Test func progressRoundTripsThroughJSON() throws {
        var progress = StudyProgress()
        progress.record(words(1).words[0], .hard, now: start, calendar: utc)
        let data = try JSONEncoder().encode(progress)
        #expect(try JSONDecoder().decode(StudyProgress.self, from: data) == progress)
    }

    @Test func iKnowThisWordAndUndo() throws {
        let set = words(5)
        var progress = StudyProgress()
        progress.markKnown(set.words[0], now: start)
        #expect(progress.isKnown(set.words[0]))
        #expect(progress.cards["w0"]?.markedKnown == true)
        #expect(progress.startedToday(now: start, calendar: utc) == 0)  // does not use a new-word slot
        var plan = progress.plan(for: set, now: start, newPerDay: 2, calendar: utc)
        #expect(plan.new.map(\.native) == ["w1", "w2"])
        plan = progress.plan(for: set, now: start.addingTimeInterval(100 * 86_400), newPerDay: 0, calendar: utc)
        #expect(plan.reviews.isEmpty)  // far in the back
        progress.reset(set.words[0])
        plan = progress.plan(for: set, now: start, newPerDay: 1, calendar: utc)
        #expect(plan.new.first?.native == "w0")  // back as new

        var session = StudySession(plan: StudyPlan(reviews: [], new: Array(set.words.prefix(3))), gap: 3)
        session.skipCurrentWord()
        #expect(!session.queue.contains { $0.word == set.words[0] })
    }

    @Test func historyNumbers() throws {
        let set = words(3)
        var progress = StudyProgress()
        progress.record(set.words[0], .good, now: start, calendar: utc)
        progress.record(set.words[1], .good, now: start.addingTimeInterval(60), calendar: utc)
        #expect(progress.recent(in: set).map(\.word.native) == ["w1", "w0"])
        #expect(progress.answersPerDay.values.reduce(0, +) == 2)
        let forecast = progress.dueForecast(in: set, days: 7, now: start, calendar: utc)
        #expect(forecast.reduce(0, +) == 2)
        // Progress saved before answersPerDay existed still loads.
        let old = #"{"cards":{},"startedPerDay":{"2026-11-14":3}}"#
        let decoded = try JSONDecoder().decode(StudyProgress.self, from: Data(old.utf8))
        #expect(decoded.startedPerDay["2026-11-14"] == 3 && decoded.answersPerDay.isEmpty)
    }

    @Test func grammarLoads() throws {
        let grammar = try #require(GrammarSet.bundled("hsk1"))
        #expect(grammar.points.count > 50)
        let modal = try #require(grammar.points.first { $0.items == "会、能" })
        #expect(!modal.english.isEmpty && !modal.examples.isEmpty)
        for example in modal.examples {
            #expect(example.chunks.count == example.tones.count)
            #expect(example.chunks.count == example.typed.split(separator: " ").count)
        }
        // 只 as a measure word reads zhī, as "only" zhǐ.
        let measure = grammar.points.flatMap(\.examples).first { $0.text == "我喜欢这只狗。" }
        #expect(measure?.pinyin.contains("zhī") == true)
        #expect(!GrammarSet.authors().isEmpty)
        for (id, _) in StudySet.catalog { #expect(GrammarSet.bundled(id) != nil) }
    }
}
