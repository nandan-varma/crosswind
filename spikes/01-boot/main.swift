// SPDX-License-Identifier: AGPL-3.0-or-later
// Spike 1: boot the Crosswind guest image on Virtualization.framework; time it and read idle RAM.
import Foundation
import Virtualization

let a = CommandLine.arguments
guard a.count >= 3 else { print("usage: vmboot <image-dir> <data.img> [seconds]"); exit(2) }
let dir = URL(fileURLWithPath: a[1])
let seconds = a.count > 3 ? Double(a[3])! : 20
let t0 = DispatchTime.now()
func ms() -> Int { Int(Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6) }

let boot = VZLinuxBootLoader(kernelURL: dir.appendingPathComponent("Image"))
boot.initialRamdiskURL = dir.appendingPathComponent("initramfs")
boot.commandLine = "console=hvc0 root=/dev/vda ro quiet"

let cfg = VZVirtualMachineConfiguration()
cfg.bootLoader = boot
cfg.cpuCount = 4
cfg.memorySize = 2 << 30
cfg.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
cfg.socketDevices = [VZVirtioSocketDeviceConfiguration()]
cfg.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
let sys = try! VZDiskImageStorageDeviceAttachment(url: dir.appendingPathComponent("system.erofs"), readOnly: true)
let data = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: a[2]), readOnly: false)
cfg.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: sys), VZVirtioBlockDeviceConfiguration(attachment: data)]
let net = VZVirtioNetworkDeviceConfiguration(); net.attachment = VZNATNetworkDeviceAttachment()
cfg.networkDevices = [net]

let outPipe = Pipe()
let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
serial.attachment = VZFileHandleSerialPortAttachment(fileHandleForReading: Pipe().fileHandleForReading,
                                                     fileHandleForWriting: outPipe.fileHandleForWriting)
cfg.serialPorts = [serial]
do { try cfg.validate() } catch { print("invalid config: \(error)"); exit(1) }

let vm = VZVirtualMachine(configuration: cfg)
outPipe.fileHandleForReading.readabilityHandler = { h in
    for line in String(decoding: h.availableData, as: UTF8.self).split(whereSeparator: \.isNewline) {
        print(String(format: "[%5d ms] ", ms()) + line)
    }
}
vm.start { r in
    if case .failure(let e) = r { print("start failed: \(e)"); exit(1) }
    print("MARK vm.start returned \(ms()) ms")
}
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "rss=", "-p", "\(getpid())"]
    let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
    print("MARK host-process RSS KiB:", String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    exit(0)
}
RunLoop.main.run()
