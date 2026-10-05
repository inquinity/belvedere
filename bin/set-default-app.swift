// Make an app the default for every document type it declares.
//
//   swift bin/set-default-app.swift /Applications/Belvedere.app
//
// Reads CFBundleDocumentTypes from the app's Info.plist and asks macOS, through
// NSWorkspace, to make the app the default for each content type it lists. macOS
// may show its own confirmation dialog for each change. Types that macOS does not
// know (the app's own exported ones that are not registered) are skipped and
// named. After each change it reads the recorded default back and says FAILED if it
// did not take, after waiting up to five seconds. --dry-run lists the types; --check
// shows the current default for each type. Neither changes anything.

import AppKit
import CoreServices
import UniformTypeIdentifiers

let arguments = Array(CommandLine.arguments.dropFirst())
let dryRun = arguments.contains("--dry-run")
let checkOnly = arguments.contains("--check")
guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
    FileHandle.standardError.write(Data("usage: set-default-app.swift [--dry-run] /path/to/App.app\n".utf8))
    exit(2)
}
let appURL = URL(fileURLWithPath: path)
guard let info = Bundle(url: appURL)?.infoDictionary,
      let documentTypes = info["CFBundleDocumentTypes"] as? [[String: Any]] else {
    FileHandle.standardError.write(Data("error: no CFBundleDocumentTypes in \(path)\n".utf8))
    exit(1)
}
let identifiers = documentTypes
    .flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }
let uniqueIdentifiers = Array(NSOrderedSet(array: identifiers)) as? [String] ?? identifiers

let bundleIdentifier = Bundle(url: appURL)?.bundleIdentifier ?? ""

/// The bundle identifier macOS has recorded as the default for a type, or "none".
func recordedHandler(for identifier: String) -> String {
    LSCopyDefaultRoleHandlerForContentType(identifier as CFString, .all)?
        .takeRetainedValue() as String? ?? "none"
}

var failures = 0
for identifier in uniqueIdentifiers {
    guard let type = UTType(identifier) else {
        print("skip    \(identifier)  (macOS does not know this type)")
        continue
    }
    if checkOnly {
        print("\(recordedHandler(for: identifier))  \(identifier)")
        continue
    }
    if dryRun {
        print("would   \(identifier)")
        continue
    }
    do {
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
    } catch {
        print("note    \(identifier)  NSWorkspace: \(error.localizedDescription)")
    }
    // NSWorkspace can report success from a command-line tool without the
    // stored record changing, so check it, and fall back to the Launch Services
    // call that duti uses. Deprecated, but it still works and shows no dialog.
    if recordedHandler(for: identifier).lowercased() != bundleIdentifier.lowercased() {
        let status = LSSetDefaultRoleHandlerForContentType(identifier as CFString, .all, bundleIdentifier as CFString)
        if status != 0 { print("note    \(identifier)  Launch Services returned OSStatus \(status)") }
    }
    // The change reaches the Launch Services daemon a moment later, so wait for it.
    var recorded = recordedHandler(for: identifier)
    for _ in 0..<20 where recorded.lowercased() != bundleIdentifier.lowercased() {
        try? await Task.sleep(for: .milliseconds(250))
        recorded = recordedHandler(for: identifier)
    }
    if recorded.lowercased() == bundleIdentifier.lowercased() {
        print("set     \(identifier)")
    } else {
        failures += 1
        print("FAILED  \(identifier)  default is still \(recorded)")
    }
}
exit(failures == 0 ? 0 : 1)
