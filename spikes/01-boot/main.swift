// SPDX-License-Identifier: AGPL-3.0-or-later
// Spike 1: boot an arm64 Linux kernel+initramfs on Virtualization.framework and time it.
import Foundation
import Virtualization

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: vmboot <kernel> <initramfs> [cmdline]"); exit(2) }
let t0 = DispatchTime.now()
func ms() -> Int { Int(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6) }

let boot = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: args[1]))
boot.initialRamdiskURL = URL(fileURLWithPath: args[2])
boot.commandLine = args.count > 3 ? args[3] : "console=hvc0 quiet"

let cfg = VZVirtualMachineConfiguration()
cfg.bootLoader = boot
cfg.cpuCount = 2
cfg.memorySize = 1 << 30
cfg.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
cfg.socketDevices = [VZVirtioSocketDeviceConfiguration()]
cfg.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

let inPipe = Pipe(), outPipe = Pipe()
let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
serial.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: inPipe.fileHandleForReading,
                                                     fileHandleForWriting: outPipe.fileHandleForWriting)
cfg.serialPorts = [serial]
do { try cfg.validate() } catch { print("invalid config: \(error)"); exit(1) }

let vm = VZVirtualMachine(configuration: cfg)
var seen = ""
outPipe.fileHandleForReading.readabilityHandler = { h in
    let s = String(decoding: h.availableData, as: UTF8.self)
    FileHandle.standardError.write(Data(s.utf8))
    seen += s
    if seen.contains("login:") || seen.contains("Welcome to Alpine") {
        print("MARK userspace-up \(ms()) ms")
        // idle RSS of the VM process after a settle period
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-o", "rss=,comm=", "-p", "\(getpid())"]; try? p.run(); p.waitUntilExit()
            vm.stop { _ in exit(0) }
        }
        seen = ""
    }
}
vm.start { r in
    switch r {
    case .success: print("MARK vm-started \(ms()) ms")
    case .failure(let e): print("start failed: \(e)"); exit(1)
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("TIMEOUT"); exit(3) }
RunLoop.main.run()
