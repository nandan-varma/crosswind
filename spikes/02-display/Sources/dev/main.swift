// SPDX-License-Identifier: AGPL-3.0-or-later
// Spike 2: boot the guest and show its windows; `--bench` measures key-to-frame latency.
// Usage: dev <image-dir> <data-disk> [--bench]
import AppKit
import CrosswindKit

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    var vm: GuestVM?
    var server: DisplayServer?
    var sentAt: [UInt64] = []
    var latencies: [Double] = []
    var pendingSince: UInt64?
    var frameBytes: [Int] = []
    var benchStarted = false

    func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        let bench = args.contains("--bench")
        let vm = GuestVM(imageDirectory: URL(fileURLWithPath: args[1]), dataDisk: URL(fileURLWithPath: args[2]))
        vm.onDisplayConnection = { [weak self] connection in
            guard let self else { return }
            let server = DisplayServer(connection: connection)
            self.server = server
            guard bench else { return }
            server.onFrame = { [weak self] window, _, bytes in
                guard let self else { return }
                if let t = self.pendingSince {
                    self.latencies.append(Double(self.now() - t) / 1e6)
                    self.frameBytes.append(bytes)
                    self.pendingSince = nil
                }
                if !self.benchStarted { self.benchStarted = true; self.runBench(window) }
            }
        }
        self.vm = vm
        Task { do { try await vm.start() } catch { print("vm start failed:", error); NSApp.terminate(nil) } }
    }

    func runBench(_ window: UInt32) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            for i in 0..<100 {
                let key: UInt32 = 30 + UInt32(i % 10)
                pendingSince = now()
                server?.inject(window: window, .key(.with { $0.keycode = key; $0.pressed = true }))
                server?.inject(window: window, .key(.with { $0.keycode = key; $0.pressed = false }))
                try? await Task.sleep(for: .milliseconds(100))
            }
            let sorted = latencies.sorted()
            func pct(_ p: Double) -> Double { sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))] }
            print(String(format: "BENCH samples=%d p50=%.1fms p95=%.1fms max=%.1fms avgFrameBytes=%d",
                         sorted.count, pct(0.5), pct(0.95), sorted.last ?? 0, frameBytes.isEmpty ? 0 : frameBytes.reduce(0, +) / frameBytes.count))
            NSApp.terminate(nil)
        }
    }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
