import Testing
@testable import DuctusLog

@Suite struct LogTests {
    @Test func plainWhenColorOff() {
        for level in LogLevel.allCases where level != .debug {
            #expect(Log.format("hi", level: level, colored: false) == "hi")
        }
    }

    @Test func colorsMatchConventions() {
        #expect(Log.format("x", level: .error, colored: true) == "\u{1B}[31mx\u{1B}[0m")
        #expect(Log.format("x", level: .crashHeader, colored: true) == "\u{1B}[1;31mx\u{1B}[0m")
        #expect(Log.format("x", level: .stackFrame, colored: true) == "\u{1B}[36mx\u{1B}[0m")
        #expect(Log.format("x", level: .warning, colored: true) == "\u{1B}[33mx\u{1B}[0m")
        #expect(Log.format("x", level: .success, colored: true) == "\u{1B}[32mx\u{1B}[0m")
        #expect(Log.format("x", level: .info, colored: true) == "x")
    }

    @Test func debugPrefix() {
        #expect(Log.format("x", level: .debug, colored: false) == "[debug] x")
    }

    @Test func colorRules() {
        #expect(Log.shouldUseColor(environment: [:], isTTY: true))
        #expect(!Log.shouldUseColor(environment: [:], isTTY: false))
        #expect(!Log.shouldUseColor(environment: ["DUCTUS_NO_COLOR": "1"], isTTY: true))
        #expect(!Log.shouldUseColor(environment: ["NO_COLOR": "1"], isTTY: true))
    }
}
