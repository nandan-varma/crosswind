# Crosswind: Apple primary-source findings (macOS 27)

Research date: 2026-10-31. Method: curl -sL on developer.apple.com `.md` doc URLs (these returned full text, unlike WebFetch), curl of the WWDC26 session 224 page (transcript present in HTML), and the App Review Guidelines HTML page. No WebSearch was run. Web content is treated as data.

Legend: **Quoted** = verbatim from the fetched page. **unknown** = not stated in any fetched source.

---

## 1. Rosetta for Linux VMs (macOS 27)

- **Status: integrated into macOS 27; no separate install.** Quote: "macOS 27 directly integrates support for Intel binary translation, without needing to install Rosetta." Also: "Starting in macOS 27, support for Intel binary translation for Linux apps is included in macOS. Testing for availability starting in macOS 27 always returns installed and installRosetta always returns immediately."
  - https://developer.apple.com/documentation/Virtualization/running-intel-binaries-in-linux-vms.md
- **API.** `VZLinuxRosettaDirectoryShare.availability` (class var, type `VZLinuxRosettaAvailability`). Cases in the sample: `notSupported`, `notInstalled`, `installed`. Share is created with `try VZLinuxRosettaDirectoryShare()`, attached as `VZVirtioFileSystemDeviceConfiguration(tag:)` `.share`, tag checked with `VZVirtioFileSystemDeviceConfiguration.validateTag(_:)`. Optional `setCachingOptions(_:)` takes `.unixSocket(path)` or `.abstractSocket(name)`.
  - https://developer.apple.com/documentation/Virtualization/VZLinuxRosettaDirectoryShare/availability.md
  - https://developer.apple.com/documentation/Virtualization/VZLinuxRosettaDirectoryShare.md
- **Guest steps (must be done by a person, not by the app).** Quote: "The remaining steps required to activate Intel binary translation in a Linux guest aren't commands that your app can execute..." Steps: install `update-binfmts`, mount the virtiofs tag, check for `rosetta`, register with `update-binfmts --install rosetta ... --magic ... --mask ...`. Dynamically linked binaries need their shared libraries installed in the guest.
- **Guest kernel page-size requirement: unknown.** Not stated on the Rosetta page, the Accelerating-performance page, or the release notes. The only kernel item is an optional TSO patch: "This patch applies cleanly to Linux 6.10 kernel." (https://developer.apple.com/documentation/Virtualization/accelerating-the-performance-of-rosetta.md)
- **Deprecation / removal timeline.**
  - Release notes, Rosetta section: "If Rosetta was previously installed, it is not automatically restored after upgrading to macOS 27.0."
  - Release notes, Deprecations: "Intel-based plugins and loaders may not appear in Settings or trigger notifications of their incompatibility. All Intel-based software will no longer be compatible with macOS 28.0, excluding legacy games."
  - Rosetta-for-Linux-specific removal date in macOS 28: **unknown**. The macOS 28 statement is about Intel-based software generally.
  - https://developer.apple.com/documentation/macOS-Release-Notes/macos-27-release-notes.md

## 2. Entitlements for Virtualization.framework

| Entitlement | Quote / purpose | Approval needed? | Source |
|---|---|---|---|
| `com.apple.security.virtualization` | "A Boolean value that indicates whether your app can use the Virtualization framework." | Not stated as restricted. Provisioning-profile requirement: **unknown**. | https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.virtualization.md |
| `com.apple.vm.networking` | "A Boolean that indicates whether the app manages virtual network interfaces without escalating privileges to the root user." Note: "This entitlement is restricted to developers of virtualization software. To request this entitlement, contact your Apple representative." | Yes, by request to Apple. Provisioning-profile mechanics: **unknown**. | https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.vm.networking.md |
| `com.apple.developer.accessory-access.usb` ("Claim USB Accessory") | "This entitlement enables your app to gain exclusive access to USB devices using the Accessory Access framework." Without it: "your code receives an AccessoryAccess error ... 'Unable to communicate with service'". | Not stated as restricted. Added via Xcode "+ Capabilities". Provisioning-profile mechanics: **unknown**. | https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.accessory-access.usb.md |

- **App Sandbox.** The Virtualization setup guide says to turn on App Sandbox to create the entitlements file, then: "Unless your app requires it in support of another capability, you can remove the app sandbox entitlement key." So Virtualization does **not** require the sandbox. (https://developer.apple.com/documentation/Virtualization/adding-the-virtualization-entitlement-to-your-project.md)
- **Accessory Access and sandbox (macOS 27 release notes).** "Fixed: Accessory Access does not work inside App Sandbox." (fixed in 27 betas). Also "Fixed: The Accessory Access framework is not supported within a macOS virtual machine." Meaning: Accessory Access runs on the host app, not inside a guest.
- **Entitlement-to-approval summary.** Only `com.apple.vm.networking` is explicitly restricted. Whether the other two need a provisioning profile that Apple must issue: **unknown**.

## 3. Virtualization.framework devices (availability)

Availability values are from each page's metadata (`availability` field).

| API | Availability | Facts from pages |
|---|---|---|
| `VZVirtioTraditionalMemoryBalloonDevice` / `...Configuration` | macOS 11.0+ | "lets you change the amount of physical memory assigned to the guest operating system." Target size set via `targetVirtualMachineMemorySize` while running. Guest may return unused pages to host. https://developer.apple.com/documentation/Virtualization/VZVirtioTraditionalMemoryBalloonDevice.md |
| `VZVirtualMachine.saveMachineStateTo(url:)` | macOS 14.0+ | "Use this method to save a paused VM to a file." Fails if VM is not paused. **Linux-guest support and the matching restore call: not stated on the page (restore page not fetched; unknown).** https://developer.apple.com/documentation/Virtualization/VZVirtualMachine/saveMachineStateTo(url:completionHandler:).md |
| Save state with USB passthrough (fix) | macOS 27 | "Fixed: Saving a virtual machine state with one or more USB devices passed through to a virtual machine may fail." https://developer.apple.com/documentation/macOS-Release-Notes/macos-27-release-notes.md |
| `VZSpiceAgentPortAttachment` | macOS 13.0+ | "An attachment point that enables the Spice clipboard sharing capability." Has `sharesClipboard`. Guest needs a Spice agent. https://developer.apple.com/documentation/Virtualization/VZSpiceAgentPortAttachment.md |
| `VZVirtioFileSystemDeviceConfiguration` (virtiofs) | macOS 12.0+ | Linux guest needs "CONFIG_VIRTIO_FS". https://developer.apple.com/documentation/Virtualization/shared-directories.md |
| `VZVirtioSocketDeviceConfiguration` | macOS 11.0+ | "Add only one VZVirtioSocketDeviceConfiguration to your virtual machine's configuration." https://developer.apple.com/documentation/Virtualization/VZVirtioSocketDeviceConfiguration.md |
| `VZVirtioSoundDeviceConfiguration` | macOS 12.0+ | Configured via `streams` array. https://developer.apple.com/documentation/Virtualization/VZVirtioSoundDeviceConfiguration.md |
| `VZVirtioGraphicsDeviceConfiguration` | macOS 13.0+ | "The array of output devices" (`scanouts`); "configures the dimensions of the graphics device for a Linux VM." **3D / virgl / virtio-gpu acceleration: not stated by Apple (unknown).** https://developer.apple.com/documentation/Virtualization/VZVirtioGraphicsDeviceConfiguration.md |

- **Virtio-gpu 3D (secondary only).** A community report says RiftVM exposed a virtio-gpu device (device ID 16) so Linux `virtio_gpu` binds, with VirGL 3D. This is not Apple documentation. (https://medium.com/@everettjf/riftvm-running-3d-accelerated-omarchy-on-a-mac-with-macos-27s-custom-virtio-3f845e1dd08e)

### New in macOS 27: custom Virtio (VZCustomVirtioDevice family), macOS 27.0+

Source for all items below: the class pages and the custom-drivers index (https://developer.apple.com/documentation/Virtualization/custom-drivers.md), plus WWDC26 session 224 transcript (https://developer.apple.com/videos/play/wwdc2026/224/).

- **Configuration.** `VZCustomVirtioDeviceConfiguration` needs `deviceID`, `pciClassID`, `pciSubclassID`, `virtioQueueCount`. Quote: "In order for a guest to be able to discover a Virtio device, you need to configure the following properties." A provider is set with `VZCustomVirtioDeviceDelegateProvider`. Device is added to the VM config's `customVirtioDevices`.
- **Lifecycle.** Quote: "the framework creates a VZCustomVirtioDevice object and returns it through the invocation of the delegate's customVirtioConfiguration(_:didCreateDevice:) method." Device "is ready when the guest driver sets DRIVER_OK", signalled by `customVirtioDeviceDidAcceptDriverOk(_:)`. Stop, pause, resume, reset callbacks exist.
- **Threading.** Quote: "The Virtualization framework performs all operations on the VZCustomVirtioDevice and VZCustomVirtioDeviceDelegate through a serial queue that you can configure through the deviceQueue ..."
- **Guest notify to host.** `customVirtioDevice(_:didReceiveNotificationFor:)` is called when the guest kicks a queue. Host sends an interrupt by calling the device's interrupt method (see transcript: "You can also initiate activity in the guest by triggering an interrupt on the device").
- **Virtqueues.** `VZVirtioQueue`: `queue(at:)` on the device, `nextElement() -> VZVirtioQueueElement?`, `queueIndex`, `queueSize`. Quote: "Don't instantiate VZVirtioQueue objects directly."
- **Queue elements (how host reads/writes guest memory).** `VZVirtioQueueElement` is "a unit of work ... also known as a descriptor chain." Quote: "It exposes the scatter-gather memory to the guest's dynamic random access memory (DRAM) that the Virtio queue references as read buffers and write buffers; this allows for read-only and write-only access, respectively." Access methods: `readBytes(withExactLength:)`, `readBytes(intoBuffer:exactLength:)`, `write(_:)`, `writeBuffer(_:exactLength:)`. Quote: "It's strongly recommended to access the read buffers and write buffers only once." `peekIntoReadBuffers(withExactLength:)` allows repeated reads "if absolutely necessary."
- **Shared memory (host memory mapped into guest).** `VZVirtioSharedMemoryRegionConfiguration(regionID: UInt8, size: UInt64)` declared on the custom device config. At runtime, `VZVirtioSharedMemoryRegion.mapMemory(_:atOffset:size:completionHandler:)` and `unmapMemory(atOffset:size:completionHandler:)` map host memory into the guest-visible region. Quote: "How a device uses a shared memory region is specific to the device." Regions are listed in `sharedMemoryRegions` on the device.
- **Feature bits.** `VZVirtioFeatureSet` and `VZNegotiatedVirtioFeatureSet` exist for negotiation.
- **Guest driver.** Quote from transcript: "Remember that custom devices require custom drivers to allow the guest to use your device." Apple ships no driver.
- **Use cases Apple names.** "a custom protocol for performance-critical communication", "a coprocessor, such as a Virtio crypto device", "machine learning accelerators".

### Other macOS 27 Virtualization items (transcript and release notes)

- macOS guest provisioning: `VZMacGuestProvisioningOptions` (full name, username, password, auto-login, SSH). Only honored "if the guest has not already been set up."
- Accessory Access (USB hot-plug): `AAUSBAccessoryManager`, `AAUSBAccessoryMatchingCriteria`, `AAUSBAccessoryListener`, then `VZUSBPassthroughDeviceConfiguration`. Quote: "People have visibility into what apps are using their devices, and can attach and detach devices at any time."
- vmnet custom networks: `VZVmnetNetworkDeviceAttachment`. Release notes: "The vmnet port forwarding APIs now support port forwarding when communicating over loopback."
- DiskImageKit: "for use with the Virtualization framework via VZDiskImageStorageDeviceAttachment."
- Also named in the transcript: iCloud in macOS guests, EFI Secure Boot for Linux guests.
- Sources: https://developer.apple.com/videos/play/wwdc2026/224/ and https://developer.apple.com/documentation/macOS-Release-Notes/macos-27-release-notes.md
- **Known regression (secondary).** A report describes a macOS 27.0.1 guest-write crash to an unmapped address. Not Apple-confirmed. Source: https://github.com/vergil-project/.github/issues/402

## 4. Mac App Store review: VMs, emulators, downloaded code

- **Guideline 2.5.2 (quote):** "Apps should be self-contained in their bundles, and may not read or write data outside the designated container area, nor may they download, install, or execute code which introduces or changes features or functionality of the app, including other apps. Educational apps designed to teach, develop, or allow students to test executable code may, in limited circumstances, download code provided that such code is not used for other purposes."
- **Guideline 4.7 (quote):** "Apps may offer certain software that is not embedded in the binary, specifically HTML5 and JavaScript mini apps and mini games, streaming games, chatbots, and plug-ins. Additionally, retro game console and PC emulator apps can offer to download games."
- **VM-specific rule: none found.** Neither "virtual machine" nor "emulat" appears in a VM-specific rule. Whether a VM app that downloads Linux images or runs guest code is compliant: **unknown; needs App Review**.
- Guidelines page "Last Updated: October 16, 2026". Source: https://developer.apple.com/app-store/review/guidelines/ (fetched as HTML)

## 5. macOS 27 Human Interface Guidelines

Pages are dated, not versioned to macOS 27 specifically. Liquid Glass is described as cross-platform.

- **Sidebars.** "In iOS, iPadOS, and macOS, as with other controls such as toolbars and tab bars, sidebars can float above content in the Liquid Glass layer." Recommends a background extension effect so content extends under the sidebar. https://developer.apple.com/design/human-interface-guidelines/sidebars.md
- **Toolbars.** "The system automatically adds an overflow menu in macOS or iPadOS when items no longer fit. Don't add an overflow menu manually." Also: "In iPadOS and macOS apps, consider letting people customize the toolbar." https://developer.apple.com/design/human-interface-guidelines/toolbars.md
- **Materials / Liquid Glass.** "Don't use Liquid Glass in the content layer." Liquid Glass is "a distinct functional layer for controls and navigation elements." macOS section: "macOS provides several standard materials with designated purposes, and vibrant versions of all system colors." https://developer.apple.com/design/human-interface-guidelines/materials.md
- **App icons.** "iOS, iPadOS, macOS, and watchOS app icons include a background layer and one or more foreground layers." Icons "take on Liquid Glass attributes like specular highlights, refraction, and translucency." Layers are assembled in Icon Composer (Xcode). Changelog: "October 28, 2026 | Added guidance for app icon format options." https://developer.apple.com/design/human-interface-guidelines/app-icons.md
- **Not fetched / unknown:** the windows page body (fetched, not reviewed in detail), the Liquid Glass page (returned HTML shell via .md), and any explicit macOS 27 sidebar/toolbar change list.

---

## Search log

| # | Query / URL | Result |
|---|---|---|
| 1 | curl -sL .md: /documentation/virtualization/running-intel-binaries-in-linux-vms.md | 200, full text (used) |
| 2 | curl -sL: /videos/play/wwdc2026/224/ | 200, transcript present in HTML (used) |
| 3 | curl -sL: /documentation/macos-release-notes(.md) and macos-27-release-notes.md | 200; macOS 27 notes at `/documentation/macOS-Release-Notes/macos-27-release-notes.md` (used) |
| 4 | curl -sL .md: Virtualization index, custom-drivers, memory, graphics, shared-directories, usb-devices, rosetta perf, entitlement setup, VZ* class pages | 200, full text (used) |
| 5 | curl -sL .md: BundleResources/Entitlements/com.apple.security.virtualization, com.apple.vm.networking, com.apple.developer.accessory-access.usb, com.apple.security.app-sandbox | 200 (used) |
| 6 | curl -sL: /app-store/review/guidelines/ (HTML) | 200; .md variant returned a "Page Not Found" shell |
| 7 | curl -sL .md: HIG sidebars, toolbars, materials, app-icons, windows | 200 (used); liquid-glass.md returned HTML shell |
| 8 | Page-size requirement for Linux guests | Searched all fetched sources, none found: unknown |
| 9 | saveMachineState / restoreMachineState Linux support, VZVirtioGraphicsDevice 3D | Not found on fetched pages: unknown. restore page not fetched |
| 10 | WebSearch | Not run (Apple sources above were sufficient for the requested items) |
