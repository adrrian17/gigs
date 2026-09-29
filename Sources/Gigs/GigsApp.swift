import ServiceManagement
import SwiftUI

@main
struct GigsApp: App {
    @State private var disk = Disk()

    var body: some Scene {
        MenuBarExtra {
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Gigs \(version)")
            }
            Text("\(disk.available) available of \(disk.total)")
            Button("Refresh") { disk.refresh() }.keyboardShortcut("r")
            Button(disk.cleaning ? "Cleaning… \(Int(disk.progress * 100))%" : "Clean Up…") { disk.offerCleanup() }
                .disabled(disk.cleaning)
            if disk.docker != nil {
                Divider()
                Button("Clean Up Docker…") { disk.pruneDocker() }.disabled(disk.cleaning)
            }
            Divider()
            Button("Quit Gigs") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(nsImage: Self.badge(disk.availableGB, free: disk.cleaning ? disk.progress : disk.freeFraction, cleaning: disk.cleaning))
        }
    }

    // MenuBarExtra labels only render Text/Image, so draw the ring into an image.
    // Template images follow the menu bar tint; a colored image is required for red.
    // While cleaning, the ring shows cleanup progress instead of free space.
    private static func badge(_ gb: Int, free: Double, cleaning: Bool) -> NSImage {
        let low = gb < 20 && !cleaning
        let view = ZStack {
            Circle().strokeBorder(lineWidth: 1.5).opacity(0.3)
            Circle().inset(by: 0.75).trim(from: 0, to: free)
                .stroke(lineWidth: 1.5)
                .rotationEffect(.degrees(-90))
            if cleaning {
                Image(systemName: "sparkles").font(.system(size: 8, weight: .bold))
            } else {
                Text("\(gb)")
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(4)
            }
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
    var cleaning = false
    var progress = 0.0
    private var bytes: Int64 = 0
    private var warned = false
    private var timer: Timer?
    // Mole's cleanup script (https://github.com/tw93/mole), bundled by install.sh or read from the repo under `swift run`.
    private let mole = [
        Bundle.main.resourceURL?.appending(path: "Mole/bin/clean.sh"),
        URL(filePath: #filePath).appending(path: "../../../Mole/bin/clean.sh").standardized,
    ].compactMap { $0?.path }.first { FileManager.default.fileExists(atPath: $0) }
    // Docker Desktop and OrbStack both link the CLI into one of these.
    let docker = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", NSHomeDirectory() + "/.orbstack/bin/docker"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    init() {
        // Open at login. Skipped under `swift run`, and once registered so turning it off in System Settings sticks.
        if Bundle.main.bundlePath.hasSuffix(".app"), SMAppService.mainApp.status == .notRegistered {
            try? SMAppService.mainApp.register()
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        // "Important usage" matches Finder's number (counts purgeable space as available).
        bytes = values.volumeAvailableCapacityForImportantUsage ?? 0
        available = Self.format(bytes)
        availableGB = Int(bytes / 1_000_000_000)
        let totalBytes = Int64(values.volumeTotalCapacity ?? 0)
        total = Self.format(totalBytes)
        freeFraction = totalBytes > 0 ? Double(bytes) / Double(totalBytes) : 0
        // Ask once per drop below 20 GB; async so the first check waits for the app to finish launching.
        if availableGB >= 20 { warned = false } else if !warned && !cleaning {
            warned = true
            DispatchQueue.main.async { self.offerCleanup() }
        }
    }

    func offerCleanup() {
        guard let mole else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = availableGB < 20 ? "Only \(available) left on your disk" : "Clean up your disk?"
        alert.informativeText = "This will delete caches, logs, and other files that macOS and your apps rebuild on their own."
        alert.addButton(withTitle: "Clean Up")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        cleaning = true
        progress = 0
        let before = bytes
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [mole]
        // Launch agents get a bare PATH; Mole shells out to Homebrew tools.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        // clean.sh prints a "➤" header as it starts each section; 14 run without sudo.
        // ponytail: hardcoded count, re-count after updating Mole/ (`clean.sh --dry-run | grep -c ➤`).
        let output = Pipe()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            let sections = String(decoding: data, as: UTF8.self).filter { $0 == "➤" }.count
            Task { @MainActor in self.progress = min(self.progress + Double(sections) / 14, 0.99) }
        }
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            Task { @MainActor in self.finishCleanup(before: before) }
        }
        do { try process.run() } catch { cleaning = false }
    }

    // Removes stopped containers, unused networks, all unused images, and build cache (not volumes).
    func pruneDocker() {
        guard let docker else { return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clean up Docker?"
        alert.informativeText = "This will delete stopped containers, unused networks, all images not used by a container, and the build cache. Volumes are kept."
        alert.addButton(withTitle: "Clean Up")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        cleaning = true
        progress = 0
        let process = Process()
        process.executableURL = URL(fileURLWithPath: docker)
        process.arguments = ["system", "prune", "--all", "--force"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do { try process.run() } catch { cleaning = false; return }
        // Read on a background queue until EOF so a long list of deleted images can't fill the pipe and stall docker.
        DispatchQueue.global().async {
            // Freed space lands inside Docker's VM disk, so report Docker's own total ("Total reclaimed space: …") or its error.
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            let summary = text.split(separator: "\n").last.map(String.init) ?? "Docker exited without output."
            Task { @MainActor in
                self.cleaning = false
                self.refresh()
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = "Docker cleanup finished"
                alert.informativeText = summary
                alert.runModal()
            }
        }
    }

    private func finishCleanup(before: Int64) {
        cleaning = false
        refresh()
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Cleanup finished"
        alert.informativeText = "Freed \(Self.format(max(bytes - before, 0))). \(available) available now."
        alert.runModal()
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
