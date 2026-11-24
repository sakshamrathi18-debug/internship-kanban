// Captures one of a process's windows by title (child popovers and sheets are
// included by the system). Only that window's pixels — never the rest of the screen.
// usage: capture_windows <pid> <out.png> [window title]
import AppKit
let pid = Int32(CommandLine.arguments[1])!, out = CommandLine.arguments[2]
let title = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "Kanban Board"
let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
guard let window = all.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowName as String] as? String) == title }),
      let id = window[kCGWindowNumber as String] as? Int else { print("no window titled \(title)"); exit(1) }
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-x", "-o", "-l", "\(id)", out]
try! p.run(); p.waitUntilExit()
print("captured → \(out)")
