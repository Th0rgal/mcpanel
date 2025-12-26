import Foundation
import CoreGraphics
import ImageIO

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "OfflineCinema"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "window.png"

let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray? as? [[String: Any]] ?? []

func intVal(_ v: Any?) -> Int? {
    if let n = v as? Int { return n }
    if let n = v as? NSNumber { return n.intValue }
    return nil
}

var candidates: [[String: Any]] = []
for w in windowInfoList {
    if (w[kCGWindowOwnerName as String] as? String) == owner {
        if intVal(w[kCGWindowLayer as String]) == 0 {
            candidates.append(w)
        }
    }
}

guard let win = candidates.sorted(by: { (intVal($0[kCGWindowNumber as String]) ?? 0) > (intVal($1[kCGWindowNumber as String]) ?? 0) }).first,
      let windowID = intVal(win[kCGWindowNumber as String])
else {
    fputs("NO_WINDOW\n", stderr)
    exit(2)
}

guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(windowID), [.bestResolution]) else {
    fputs("CAPTURE_FAILED\n", stderr)
    exit(3)
}

let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fputs("DEST_FAILED\n", stderr)
    exit(4)
}

CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) {
    fputs("FINALIZE_FAILED\n", stderr)
    exit(5)
}

print(out)
