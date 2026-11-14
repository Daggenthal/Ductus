// DuctusUpdater: installs a Ductus update the person asked for.
//
// Ductus runs in the app sandbox, which cannot replace its own app bundle, so
// it downloads and checks the update, starts this helper and quits. This
// helper (not sandboxed, no window) then:
//   1. waits for Ductus to quit,
//   2. unzips the update and checks it is Ductus,
//   3. clears the download flag so macOS does not block the new copy,
//   4. swaps the new app in, keeping the old one until the swap worked,
//   5. opens Ductus again (with --update-failed if anything went wrong).
//
// Ductus passes the details in a small JSON request file, because macOS does
// not pass launch arguments from a sandboxed app: {"pid": .., "archive": "..", "target": ".."}.
// It lives in Ductus's sandbox folder (Library/Application Support/DuctusUpdate/request.json)
// and is deleted once read. --pid/--archive/--target arguments also work.
// Log: ~/Library/Logs/DuctusUpdater.log
import Foundation

let expectedBundleID = "dev.daggenthal.ductus"
let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DuctusUpdater.log")

func log(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
    try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let handle = try? FileHandle(forWritingTo: logURL) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
        try? handle.close()
    } else {
        try? Data(line.utf8).write(to: logURL)
    }
}

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
    return args[index + 1]
}

@discardableResult
func run(_ tool: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        log("could not run \(tool): \(error)")
        return -1
    }
}

func reopen(_ app: URL, failed: Bool) -> Never {
    run("/usr/bin/open", failed ? [app.path, "--args", "--update-failed"] : [app.path])
    exit(failed ? 1 : 0)
}

struct Request: Decodable {
    let pid: Int32
    let archive: String
    let target: String
}

/// The request from Ductus: its sandbox folder first, then the unsandboxed location.
func readRequest() -> Request? {
    if let pid = argument("--pid").flatMap(Int32.init), let archive = argument("--archive"), let target = argument("--target") {
        return Request(pid: pid, archive: archive, target: target)
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let places = [
        "Library/Containers/\(expectedBundleID)/Data/Library/Application Support/DuctusUpdate/request.json",
        "Library/Application Support/DuctusUpdate/request.json",
    ].map { home.appendingPathComponent($0) }
    for file in places {
        guard let data = try? Data(contentsOf: file) else { continue }
        try? FileManager.default.removeItem(at: file)
        if let request = try? JSONDecoder().decode(Request.self, from: data) { return request }
    }
    return nil
}

guard let request = readRequest() else {
    log("no update request found")
    exit(2)
}
let pid = pid_t(request.pid)
let archivePath = request.archive
let targetPath = request.target
let archive = URL(fileURLWithPath: archivePath)
let target = URL(fileURLWithPath: targetPath)
log("updating \(target.path) from \(archive.lastPathComponent)")

// 1. Wait for Ductus to quit (up to a minute).
for _ in 0..<600 where kill(pid, 0) == 0 {
    usleep(100_000)
}
guard kill(pid, 0) != 0 else {
    log("Ductus did not quit, giving up")
    exit(3)
}
log("Ductus has quit")

// 2. Unzip next to nothing important, and check it really is Ductus.
let work = FileManager.default.temporaryDirectory.appendingPathComponent("DuctusUpdate-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: work) }
try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
guard run("/usr/bin/ditto", ["-x", "-k", archive.path, work.path]) == 0 else {
    log("could not unzip the update")
    reopen(target, failed: true)
}
log("unzipped")
let newApp = work.appendingPathComponent("Ductus.app")
guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
      info["CFBundleIdentifier"] as? String == expectedBundleID else {
    log("the update is not Ductus")
    reopen(target, failed: true)
}
guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0 else {
    log("the update's signature is broken")
    reopen(target, failed: true)
}

log("checked")

// 3. The person chose to install it and it passed its checksum in Ductus, so
// the download flag is cleared; otherwise macOS would block the new copy.
run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

// 4. Swap: move the old app aside, copy the new one in, and only then delete the old one.
let backup = target.deletingLastPathComponent().appendingPathComponent(".Ductus-old-\(UUID().uuidString).app")
do {
    try FileManager.default.moveItem(at: target, to: backup)
} catch {
    log("could not move the old app aside: \(error)")
    reopen(target, failed: true)
}
guard run("/usr/bin/ditto", [newApp.path, target.path]) == 0 else {
    log("could not copy the new app, putting the old one back")
    try? FileManager.default.removeItem(at: target)
    try? FileManager.default.moveItem(at: backup, to: target)
    reopen(target, failed: true)
}
try? FileManager.default.removeItem(at: backup)
try? FileManager.default.removeItem(at: archive)
log("updated to \(info["CFBundleShortVersionString"] as? String ?? "?")")

// 5. Open the new Ductus.
reopen(target, failed: false)
