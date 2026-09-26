import SwiftUI

@main
struct GigsApp: App {
    @State private var disk = Disk()

    var body: some Scene {
        MenuBarExtra {
            Text("\(disk.available) available of \(disk.total)")
            Button("Refresh") { disk.refresh() }.keyboardShortcut("r")
            Divider()
            Button("Quit Gigs") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: Self.badge(disk.availableGB, free: disk.freeFraction))
        }
    }

    // MenuBarExtra labels only render Text/Image, so draw the ring into an image.
    // Template images follow the menu bar tint; a colored image is required for red.
    private static func badge(_ gb: Int, free: Double) -> NSImage {
        let low = gb < 20
        let view = ZStack {
            Circle().strokeBorder(lineWidth: 1.5).opacity(0.3)
            Circle().inset(by: 0.75).trim(from: 0, to: free)
                .stroke(lineWidth: 1.5)
                .rotationEffect(.degrees(-90))
            Text("\(gb)")
                .font(.system(size: 8, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(4)
        }
        .foregroundStyle(low ? Color.red : Color.primary)
        .frame(width: 18, height: 18)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = !low
        return image
    }
}

@Observable
@MainActor
final class Disk {
    var available = "—"
    var availableGB = 0
    var freeFraction = 0.0
    var total = "—"
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        // "Important usage" matches Finder's number (counts purgeable space as available).
        let bytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        available = Self.format(bytes)
        availableGB = Int(bytes / 1_000_000_000)
        let totalBytes = Int64(values.volumeTotalCapacity ?? 0)
        total = Self.format(totalBytes)
        freeFraction = totalBytes > 0 ? Double(bytes) / Double(totalBytes) : 0
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
