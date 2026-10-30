// Print the window number of the first on-screen window owned by a process name.
// CGWindowList needs no Accessibility permission, unlike System Events.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "sView"
let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly],
    kCGNullWindowID
) as? [[String: Any]] ?? []
for window in list where (window[kCGWindowOwnerName as String] as? String) == owner {
    if let number = window[kCGWindowNumber as String] as? Int {
        print(number)
        exit(0)
    }
}
exit(1)
