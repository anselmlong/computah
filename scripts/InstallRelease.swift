import AppKit

// Run only after verifying the published archive. Keep a rollback copy until launch succeeds.
let files = FileManager.default
guard CommandLine.arguments.count == 3 else { fatalError("Expected source and destination app paths") }
let source = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let destination = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
let identifier = "com.lvl8.computah"
guard source != destination, Bundle(url: source)?.bundleIdentifier == identifier,
      destination.lastPathComponent == "Computah.app" else { fatalError("Unexpected app bundle") }
let parent = destination.deletingLastPathComponent()
try files.createDirectory(at: parent, withIntermediateDirectories: true)
let staging = parent.appendingPathComponent(".Computah-\(UUID().uuidString).app")
let backup = parent.appendingPathComponent(".Computah-previous-\(UUID().uuidString).app")
try files.copyItem(at: source, to: staging)
defer { try? files.removeItem(at: staging) }
let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
for app in running { app.terminate() }
let deadline = Date().addingTimeInterval(15)
while running.contains(where: { !$0.isTerminated }), Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
}
guard running.allSatisfy({ $0.isTerminated }) else { fatalError("Computah did not quit; update cancelled") }
let hadPrevious = files.fileExists(atPath: destination.path)
if hadPrevious { try files.moveItem(at: destination, to: backup) }
do {
    try files.moveItem(at: staging, to: destination)
    var completed = false
    var launchError: Error?
    var launched: NSRunningApplication?
    NSWorkspace.shared.openApplication(at: destination, configuration: .init()) { app, error in
        launched = app; launchError = error; completed = true
    }
    let launchDeadline = Date().addingTimeInterval(20)
    while !completed, Date() < launchDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    guard completed, launchError == nil, let app = launched else {
        throw launchError ?? NSError(domain: "ComputahRelease", code: 1)
    }
    let checkUntil = Date().addingTimeInterval(3)
    while Date() < checkUntil { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
    guard !app.isTerminated, app.bundleURL?.standardizedFileURL == destination else {
        throw NSError(domain: "ComputahRelease", code: 2)
    }
    if hadPrevious { try? files.removeItem(at: backup) }
    print("Running \(destination.path), PID \(app.processIdentifier)")
} catch {
    try? files.removeItem(at: destination)
    if hadPrevious {
        try files.moveItem(at: backup, to: destination)
        NSWorkspace.shared.openApplication(at: destination, configuration: .init()) { _, _ in }
    }
    throw error
}
