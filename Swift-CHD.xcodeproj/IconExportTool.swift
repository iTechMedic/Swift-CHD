import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit

@MainActor
func exportCHDManIconPNG(to url: URL) throws {
    let view = CHDManIconView()
    let hosting = NSHostingView(rootView: view)
    hosting.frame = NSRect(x: 0, y: 0, width: 1024, height: 1024)

    guard let bitmapRep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        throw NSError(domain: "IconExport", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create bitmap rep"])
    }
    hosting.cacheDisplay(in: hosting.bounds, to: bitmapRep)

    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconExport", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }

    try pngData.write(to: url)
}

// Simple entry point when run in a command-line context
@main
struct IconExportCLI {
    static func main() async {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let outputURL: URL
        if let arg = CommandLine.arguments.dropFirst().first {
            outputURL = URL(fileURLWithPath: arg).standardizedFileURL
        } else {
            outputURL = home.appendingPathComponent("CHDManIcon.png")
        }
        do {
            try await MainActor.run {
                try exportCHDManIconPNG(to: outputURL)
            }
            fputs("Exported icon to: \(outputURL.path)\n", stdout)
        } catch {
            fputs("Icon export failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
#endif
