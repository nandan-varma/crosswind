// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Virtualization

public enum DisplayPort { public static let display: UInt32 = 5000 }

/// The hidden Linux VM. Boots the Crosswind guest image directly (no firmware) and exposes the display channel.
@MainActor
public final class GuestVM: NSObject {
    public struct Resources: Sendable {
        public var cpuCount = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
        public var memoryBytes: UInt64 = 4 << 30
        public var dataDiskBytes: UInt64 = 64 << 30
        public init() {}
    }

    public let imageDirectory: URL
    public let dataDisk: URL
    private let resources: Resources
    private var machine: VZVirtualMachine?
    private var listener: VZVirtioSocketListener?
    private let console = Pipe()

    /// Called on the main actor for every accepted display connection.
    public var onDisplayConnection: ((FramedConnection) -> Void)?

    public init(imageDirectory: URL, dataDisk: URL, resources: Resources = .init()) {
        self.imageDirectory = imageDirectory
        self.dataDisk = dataDisk
        self.resources = resources
    }

    public func start() async throws {
        let interval = Log.signposter.beginInterval("vm.boot")
        defer { Log.signposter.endInterval("vm.boot", interval) }

        try createDataDiskIfNeeded()
        let config = try makeConfiguration()
        try config.validate()
        let machine = VZVirtualMachine(configuration: config)

        let listener = VZVirtioSocketListener()
        listener.delegate = self
        machine.socketDevices.compactMap { $0 as? VZVirtioSocketDevice }.first?.setSocketListener(
            listener, forPort: DisplayPort.display)
        self.listener = listener
        self.machine = machine

        console.fileHandleForReading.readabilityHandler = { handle in
            for line in String(data: handle.availableData, encoding: .utf8) ?? "".split(whereSeparator: \.isNewline) {
                Log.vm.info("guest: \(line, privacy: .public)")
            }
        }
        try await machine.start()
        Log.vm.info("vm started")
    }

    public func stop() async throws {
        try await machine?.stop()
        machine = nil
    }

    private func createDataDiskIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: dataDisk.path) else { return }
        try FileManager.default.createDirectory(
            at: dataDisk.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dataDisk.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dataDisk)
        try handle.truncate(atOffset: resources.dataDiskBytes)
        try handle.close()
    }

    private func makeConfiguration() throws -> VZVirtualMachineConfiguration {
        let boot = VZLinuxBootLoader(kernelURL: imageDirectory.appending(path: "Image"))
        boot.initialRamdiskURL = imageDirectory.appending(path: "initramfs")
        boot.commandLine = "console=hvc0 root=/dev/vda ro quiet"

        let config = VZVirtualMachineConfiguration()
        config.bootLoader = boot
        config.cpuCount = resources.cpuCount
        config.memorySize = resources.memoryBytes
        config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
        config.socketDevices = [VZVirtioSocketDeviceConfiguration()]
        config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

        let system = try VZDiskImageStorageDeviceAttachment(
            url: imageDirectory.appending(path: "system.erofs"), readOnly: true)
        let data = try VZDiskImageStorageDeviceAttachment(url: dataDisk, readOnly: false)
        config.storageDevices = [
            VZVirtioBlockDeviceConfiguration(attachment: system), VZVirtioBlockDeviceConfiguration(attachment: data),
        ]

        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        config.networkDevices = [network]

        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: Pipe().fileHandleForReading,
            fileHandleForWriting: console.fileHandleForWriting
        )
        config.serialPorts = [serial]
        return config
    }
}

extension GuestVM: VZVirtioSocketListenerDelegate {
    nonisolated public func listener(
        _ listener: VZVirtioSocketListener, shouldAcceptNewConnection connection: VZVirtioSocketConnection,
        from socketDevice: VZVirtioSocketDevice
    ) -> Bool {
        let framed = FramedConnection(fd: connection.fileDescriptor, owner: connection)
        MainActor.assumeIsolated { onDisplayConnection?(framed) }
        return true
    }
}
