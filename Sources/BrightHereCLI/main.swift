import BrightHereCore
import CoreGraphics
import Foundation

func printDisplay(_ display: ManagedDisplay, brightness: BrightnessControlling, includeMode: Bool = false) {
    let value = brightness.brightness(for: display.id).map { String(format: "%.3f", $0) } ?? "n/a"
    let width = Int(display.bounds.width)
    let height = Int(display.bounds.height)
    let x = Int(display.bounds.origin.x)
    let y = Int(display.bounds.origin.y)
    let tags = display.roleDescription.isEmpty ? "" : " [\(display.roleDescription)]"
    var fields = "#\(display.index) id=\(display.id) brightness=\(value) bounds=\(width)x\(height)+\(x)+\(y)\(tags)"

    if includeMode {
        if let mode = CGDisplayCopyDisplayMode(display.id) {
            fields += " mode=\(mode.width)x\(mode.height)@\(String(format: "%.2f", mode.refreshRate))Hz pixel=\(mode.pixelWidth)x\(mode.pixelHeight)"
        } else {
            fields += " mode=n/a"
        }
    }

    print(fields)
}

func usage(exitCode: Int32 = 0) -> Never {
    let executable = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "bright-here-cli"
    fputs("""
    Usage:
      \(executable) list
      \(executable) diagnose
      \(executable) set <index|id:display-id> <0..1>

    Examples:
      \(executable) list
      \(executable) diagnose
      \(executable) set 1 0.55
      \(executable) set id:69733248 0.30

    """, exitCode == 0 ? stdout : stderr)
    exit(exitCode)
}

func resolveDisplay(_ token: String, displays: [ManagedDisplay]) -> ManagedDisplay? {
    if token.hasPrefix("id:") {
        let rawID = String(token.dropFirst(3))
        guard let id = UInt32(rawID) else {
            return nil
        }
        return displays.first(where: { $0.id == id })
    }

    guard let number = UInt32(token) else {
        return nil
    }

    return displays.first(where: { UInt32($0.index) == number })
}

let args = CommandLine.arguments.dropFirst()
let displayProvider = CoreGraphicsDisplayProvider()
let brightness = NativeBrightnessController()
let displays = displayProvider.allKnownDisplays()

guard let command = args.first else {
    usage(exitCode: 2)
}

switch command {
case "list":
    print("Backend: \(brightness.backendSummary)")
    print("Known displays: \(displays.count)")
    for display in displays {
        printDisplay(display, brightness: brightness)
    }

case "diagnose":
    print("Backend: \(brightness.backendSummary)")
    let online = displayProvider.onlineDisplays()
    print("Online displays: \(online.count)")
    for display in online {
        printDisplay(display, brightness: brightness, includeMode: true)
    }

    let active = displayProvider.activeDisplays()
    print("Active displays: \(active.count)")
    for display in active {
        printDisplay(display, brightness: brightness, includeMode: true)
    }

case "set":
    let rest = Array(args.dropFirst())
    guard rest.count == 2 else {
        usage(exitCode: 2)
    }
    guard let display = resolveDisplay(rest[0], displays: displays) else {
        fputs("No display matches '\(rest[0])'. Run 'bright-here-cli list'.\n", stderr)
        exit(1)
    }
    guard let value = Float(rest[1]), value >= 0, value <= 1 else {
        fputs("Brightness must be a number from 0 to 1.\n", stderr)
        exit(1)
    }

    if brightness.setBrightness(value, for: display.id) {
        let readback = brightness.brightness(for: display.id).map { String(format: "%.3f", $0) } ?? "n/a"
        print("Set display #\(display.index) id=\(display.id) to \(String(format: "%.3f", value)); readback=\(readback)")
    } else {
        fputs("No working brightness setter was found for display id \(display.id).\n", stderr)
        exit(1)
    }

case "help", "-h", "--help":
    usage()

default:
    usage(exitCode: 2)
}
