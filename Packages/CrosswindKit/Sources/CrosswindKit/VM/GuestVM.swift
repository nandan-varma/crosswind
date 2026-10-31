// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation
import Virtualization

public enum DisplayPort { public static let display: UInt32 = 5000 }
public enum ControlPort { public static let control: UInt32 = 5001 }

/// The hidden Linux VM. Boots the Crosswind guest image directly (no firmware) and exposes the display channel.
@MainActor
public final class GuestVM: NSObject {
    public struct Resources: Sendable {
        /// Read from `Preferences` each time a VM is created, so changes apply at the next start.
        public var cpuCount = Preferences.cpuCount
        public var memoryBytes = UInt64(Preferences.memoryGiB) << 30
        public var dataDiskBytes: UInt64 = 64 << 30
        public init() {}
    }

    public let imageDirectory: URL
    public let dataDisk: URL
    private let resources: Resources
    private var machine: VZVirtualMachine?
    private var listeners: [VZVirtioSocketListener] = []
    private let console = Pipe()

    /// Called on the main actor for every accepted display connection.
    public var onDisplayConnection: ((DisplayConnection) -> Void)?
    /// Called on the main actor for every accepted control connection.
    public var onControlConnection: ((ControlConnection) -> Void)?

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

        let socketDevice = machine.socketDevices.compactMap { $0 as? VZVirtioSocketDevice }.first
        for port in [DisplayPort.display, ControlPort.control] {
            let listener = VZVirtioSocketListener()
            listener.delegate = self
            socketDevice?.setSocketListener(listener, forPort: port)
            listeners.append(listener)
        }
        self.machine = machine

        console.fileHandleForReading.readabilityHandler = { handle in
            let text = String(bytes: handle.availableData, encoding: .utf8) ?? ""
            for line in text.split(whereSeparator: \.isNewline) {
                Log.vm.info("guest: \(line, privacy: .public)")
            }
        }
        try await machine.start()
        Log.vm.info("vm started")
    }

    /// Balloons the guest down to `bytes` of usable memory (the guest returns the rest to the host), or back to the
    /// configured size when nil. Only works while the VM runs; the balloon device is always configured.
    public func setMemoryTarget(_ bytes: UInt64?) {
        guard let balloon = machine?.memoryBalloonDevices.first as? VZVirtioTraditionalMemoryBalloonDevice else {
            return
        }
        balloon.targetVirtualMachineMemorySize = min(bytes ?? resources.memoryBytes, resources.memoryBytes)
    }

    /// Replaces the shared folders while the VM runs. The guest sees the change at once.
    public func updateSharedFolders(_ folders: SharedFolders) {
        guard let device = machine?.directorySharingDevices.first as? VZVirtioFileSystemDevice else { return }
        device.share = ShareLayout.share(for: folders)
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

        // Shared folders: only the granted folders and the staging directory are exported (see `ShareLayout`).
        try FileManager.default.createDirectory(at: Staging.root, withIntermediateDirectories: true)
        let shares = VZVirtioFileSystemDeviceConfiguration(tag: SharedFolders.mountTag)
        shares.share = ShareLayout.share(for: try SharedFolders.load(from: SharedFolders.defaultFile))
        config.directorySharingDevices = [shares]

        let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
        serial.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: Pipe().fileHandleForReading,
            fileHandleForWriting: console.fileHandleForWriting
        )
        config.serialPorts = [serial]

        config.audioDevices = [makeSoundDevice()]
        return config
    }

    /// Output always goes to the Mac's default output. Input (the Mac's microphone) is added only when enabled.
    private func makeSoundDevice() -> VZVirtioSoundDeviceConfiguration {
        let output = VZVirtioSoundDeviceOutputStreamConfiguration()
        output.sink = VZHostAudioOutputStreamSink()
        var streams: [VZVirtioSoundDeviceStreamConfiguration] = [output]
        if Preferences.microphoneEnabled {
            let input = VZVirtioSoundDeviceInputStreamConfiguration()
            input.source = VZHostAudioInputStreamSource()
            streams.append(input)
        }
        let sound = VZVirtioSoundDeviceConfiguration()
        sound.streams = streams
        return sound
    }
}

extension GuestVM: VZVirtioSocketListenerDelegate {
    nonisolated public func listener(
        _ listener: VZVirtioSocketListener, shouldAcceptNewConnection connection: VZVirtioSocketConnection,
        from socketDevice: VZVirtioSocketDevice
    ) -> Bool {
        switch connection.destinationPort {
        case DisplayPort.display:
            let framed = DisplayConnection(fd: connection.fileDescriptor, owner: connection)
            MainActor.assumeIsolated { onDisplayConnection?(framed) }
        case ControlPort.control:
            let framed = ControlConnection(fd: connection.fileDescriptor, owner: connection)
            MainActor.assumeIsolated { onControlConnection?(framed) }
        default:
            return false
        }
        return true
    }
}
