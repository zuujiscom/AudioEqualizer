import Foundation
import AVFoundation
import Accelerate
import CoreAudio

@MainActor
final class AudioEngine: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var bands: [EQBand] = EQPreset.defaultBands
    @Published var isBypassed: Bool = false
    @Published var isRunning: Bool = false
    /// Always tracks the system's current default output device — there is no
    /// manual override; see `syncToSystemDefaultOutput()`.
    @Published private(set) var selectedOutputDeviceID: AudioDeviceID = 0 {
        didSet {
            guard oldValue != selectedOutputDeviceID else { return }
            rebuildRoute()
        }
    }
    @Published var availableOutputDevices: [AudioDevice] = []
    /// Format of the captured system audio (the process tap's stream).
    @Published var inputFormat: String = "—"
    @Published var outputFormat: String = "—"
    @Published var routeErrorMessage: String?

    /// Level/spectrum live on their own observable object: they update ~20x a
    /// second, and publishing them from `AudioEngine` would invalidate every
    /// view that observes the engine (including all the band sliders) on every
    /// tick, which is enough SwiftUI churn to peg a core.
    let meters = MeterState()

    // MARK: - Amplification

    /// Master amplification multiplier (1.0 = unity, 2.0 = +6dB, 4.0 = +12dB).
    /// Applied via `AVAudioUnitEQ.globalGain` (+24 dB max).
    @Published var masterGain: Double = 1.0 {
        didSet {
            applyMasterGain()
        }
    }

    static let maxGain: Double = 15.85   // ≈ +24 dB
    static let maxBandGain: Double = 24.0
    static let minBandGain: Double = -24.0

    var amplificationDB: Double {
        20.0 * log10(max(0.001, masterGain))
    }

    /// Setter that clamps without re-triggering the property's didSet.
    func setMasterGain(_ value: Double) {
        let clamped = min(Self.maxGain, max(0, value))
        masterGain = clamped
    }

    private func applyMasterGain() {
        guard let eqNode else { return }
        // globalGain range: -96...24 dB
        let db = amplificationDB.clamped(to: -96.0...24.0)
        eqNode.globalGain = Float(db)
    }

    // MARK: - Core Audio

    /// Replaced for every processing session — see `stopProcessing()`.
    private var engine = AVAudioEngine()
    private var eqNode: AVAudioUnitEQ!
    private var fftAnalyzer = SpectrumAnalyzer()
    private var isSetup = false

    private var devicePropertyListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?

    // System-audio capture (Core Audio Process Tap + private Aggregate Device).
    private var processTapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var currentTapUID: String?
    private let aggregateUID = "com.audioequalizer.aggregate.\(UUID().uuidString)"

    private var renderer = SystemAudioRenderer()
    private var sourceNode: AVAudioSourceNode?
    private var ioProcID: AudioDeviceIOProcID?
    private var meterTimer: Timer?

    private enum AudioRouteError: Error, CustomStringConvertible {
        case noOutputDevice
        case tapCreationFailed(OSStatus)
        case tapUIDUnavailable
        case aggregateCreationFailed(OSStatus)
        case aggregateDeviceUnavailable
        case tapFormatUnavailable
        case outputFormatUnavailable
        case manualRenderingFailed(String)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)

        var description: String {
            switch self {
            case .noOutputDevice: return "No output device available"
            case .tapCreationFailed(let status): return "AudioHardwareCreateProcessTap failed (\(status))"
            case .tapUIDUnavailable: return "Could not read the created tap's UID"
            case .aggregateCreationFailed(let status): return "AudioHardwareCreateAggregateDevice failed (\(status))"
            case .aggregateDeviceUnavailable: return "The system audio route did not become ready"
            case .tapFormatUnavailable: return "Could not read the tap's stream format"
            case .outputFormatUnavailable: return "Could not read the output device's stream format"
            case .manualRenderingFailed(let reason): return "Manual rendering setup failed: \(reason)"
            case .ioProcCreationFailed(let status): return "AudioDeviceCreateIOProcIDWithBlock failed (\(status))"
            case .deviceStartFailed(let status): return "AudioDeviceStart failed (\(status))"
            }
        }
    }

    // MARK: - Init

    override init() {
        super.init()

        enumerateDevices()
        setupEngine()
    }

    deinit {
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
        }
        if let block = defaultOutputListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
        }
        guard let block = devicePropertyListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - Device Enumeration

    func enumerateDevices() {
        availableOutputDevices = Self.getDevices(direction: .output)
        syncToSystemDefaultOutput()
    }

    static func getDevices(direction: DeviceDirection) -> [AudioDevice] {
        var devices: [AudioDevice] = []

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )
        guard sizeStatus == noErr else { return devices }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return devices }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        for deviceID in deviceIDs {
            guard let name = getDeviceName(deviceID: deviceID) else { continue }
            let hasInput = getDeviceChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeInput) > 0
            let hasOutput = getDeviceChannelCount(deviceID: deviceID, scope: kAudioDevicePropertyScopeOutput) > 0

            switch direction {
            case .input where hasInput: break
            case .output where hasOutput: break
            default: continue
            }

            let lower = name.lowercased()
            let isBuiltIn = lower.contains("built") || lower.contains("internal") ||
                            lower.contains("macbook") || lower.contains("computer")

            devices.append(AudioDevice(
                id: deviceID,
                name: name,
                isBuiltIn: isBuiltIn,
                channelCount: getDeviceChannelCount(
                    deviceID: deviceID,
                    scope: direction == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
                )
            ))
        }

        return devices
    }

    static func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)
        return status == noErr ? (name as String) : nil
    }

    static func getDeviceUID(deviceID: AudioObjectID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)
        return status == noErr ? (uid as String) : nil
    }

    static func getDefaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    static func getDefaultOutputDeviceUID() -> String? {
        guard let deviceID = getDefaultOutputDeviceID() else { return nil }
        return getDeviceUID(deviceID: deviceID)
    }

    /// Translates this process's PID into the Core Audio "process object" ID
    /// that CATapDescription's exclude/include lists expect.
    static func selfProcessObjectID() -> AudioObjectID? {
        var pid = ProcessInfo.processInfo.processIdentifier
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var objectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &pid) { pidPtr -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<pid_t>.size),
                pidPtr,
                &dataSize,
                &objectID
            )
        }
        guard status == noErr, objectID != kAudioObjectUnknown else { return nil }
        return objectID
    }

    /// Swift-native wrapper (macOS 15+) around the tap's AudioObjectID — avoids
    /// hand-rolled AudioObjectGetPropertyData/kAudioTapPropertyUID boilerplate.
    static func getTapUID(tapID: AudioObjectID) -> String? {
        try? AudioHardwareTap(id: tapID).uid
    }

    static func getDeviceChannelCount(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        // AudioBufferList has a flexible trailing array. Some virtual devices
        // (including the Xbox headset bridge) report more than one buffer, so
        // a stack AudioBufferList with space for one entry would overflow here.
        guard dataSize >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        bufferList.initializeMemory(as: UInt8.self, repeating: 0, count: Int(dataSize))
        defer { bufferList.deallocate() }

        let dataStatus = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, bufferList
        )
        guard dataStatus == noErr else { return 0 }

        var channelCount: UInt32 = 0
        let list = UnsafeMutableAudioBufferListPointer(
            bufferList.assumingMemoryBound(to: AudioBufferList.self)
        )
        for buffer in list {
            channelCount += buffer.mNumberChannels
        }
        return Int(channelCount)
    }

    /// The per-buffer channel counts of a device's input stream configuration,
    /// in Core Audio's own buffer order. `getDeviceChannelCount` collapses this
    /// to a total; the tap plumbing needs the individual buffers.
    static func inputBufferChannelCounts(deviceID: AudioDeviceID) -> [UInt32] {
        guard deviceID != kAudioObjectUnknown else { return [] }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr,
              dataSize >= MemoryLayout<AudioBufferList>.size else { return [] }

        let bufferList = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        bufferList.initializeMemory(as: UInt8.self, repeating: 0, count: Int(dataSize))
        defer { bufferList.deallocate() }

        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferList) == noErr else {
            return []
        }

        let list = UnsafeMutableAudioBufferListPointer(
            bufferList.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.map { $0.mNumberChannels }
    }

    enum DeviceDirection {
        case input, output
    }

    /// Points `selectedOutputDeviceID` at whatever the system is actually
    /// playing through right now (e.g. AirPods, an external interface) —
    /// there's no manual picker, so this is the only thing that sets it
    /// after initial setup.
    private func syncToSystemDefaultOutput() {
        guard let defaultID = Self.getDefaultOutputDeviceID() else { return }
        selectedOutputDeviceID = defaultID
    }

    // MARK: - Hardware Change Listening

    private func startHardwareListening() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.enumerateDevices()
            }
        }
        devicePropertyListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )

        // Fires when the user changes the system's output device (e.g. in the
        // menu bar or System Settings) so we follow along automatically.
        var defaultOutputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let defaultOutputBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                self?.syncToSystemDefaultOutput()
            }
        }
        defaultOutputListenerBlock = defaultOutputBlock

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutputAddress,
            DispatchQueue.main,
            defaultOutputBlock
        )
    }

    private func stopHardwareListening() {
        if let block = defaultOutputListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            defaultOutputListenerBlock = nil
        }

        guard let block = devicePropertyListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        devicePropertyListenerBlock = nil
    }

    // MARK: - System Audio Route (Process Tap + Aggregate Device)

    /// Builds a private aggregate device that combines a system-wide Core Audio
    /// process tap (everything except this app) with the real output device, then
    /// points the engine's I/O unit at it. This is what lets the EQ apply to
    /// whatever the Mac is actually playing, not just this app's own audio.
    private func buildSystemAudioRoute() throws {
        teardownSystemAudioRoute()

        guard let outputUID = Self.getDeviceUID(deviceID: selectedOutputDeviceID) ?? Self.getDefaultOutputDeviceUID() else {
            throw AudioRouteError.noOutputDevice
        }

        // Exclude our own process from the tap. This is critical: the tap mutes
        // every process it captures, so if we're in the tap we mute ourselves and
        // the processed audio never reaches the speakers. Exclude by bundle ID as
        // well as process object — at launch we haven't played any audio yet, so
        // Core Audio often has no process object for us to reference.
        let excludedProcesses = Self.selfProcessObjectID().map { [$0] } ?? []
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excludedProcesses)
        description.name = "Audio Equalizer System Tap"
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        if let bundleID = Bundle.main.bundleIdentifier {
            description.bundleIDs = [bundleID]
        }

        var tapID: AudioObjectID = kAudioObjectUnknown
        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr else {
            throw AudioRouteError.tapCreationFailed(tapStatus)
        }
        processTapID = tapID

        guard let tapUID = Self.getTapUID(tapID: tapID) else {
            throw AudioRouteError.tapUIDUnavailable
        }
        currentTapUID = tapUID

        var newAggregateID: AudioObjectID = kAudioObjectUnknown
        let aggStatus = AudioHardwareCreateAggregateDevice(
            aggregateComposition(outputUID: outputUID, tapUID: tapUID) as CFDictionary,
            &newAggregateID
        )
        guard aggStatus == noErr else {
            throw AudioRouteError.aggregateCreationFailed(aggStatus)
        }
        aggregateDeviceID = newAggregateID
        guard waitForAggregateDevice(newAggregateID) else {
            throw AudioRouteError.aggregateDeviceUnavailable
        }

    }

    /// The Core Audio aggregate-device composition dictionary: the real output
    /// device as the sole subdevice (so it drives clocking/IO) plus our system
    /// process tap as the input-stream source.
    private func aggregateComposition(outputUID: String, tapUID: String) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey: "Audio Equalizer Output",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            // The tap must start with the aggregate. If it remains inactive,
            // `.mutedWhenTapped` still silences the original system stream but
            // the aggregate supplies only zeroed capture buffers.
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]
    }

    /// Aggregate creation returns before Core Audio has finished activating its
    /// tap stream. Starting the IO proc too early can yield silent buffers even
    /// though the process tap is already muting the original system output.
    private func waitForAggregateDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        for _ in 0..<30 {
            var isAlive: UInt32 = 0
            var dataSize = UInt32(MemoryLayout<UInt32>.size)
            let status = AudioObjectGetPropertyData(
                deviceID, &address, 0, nil, &dataSize, &isAlive
            )
            if status == noErr, isAlive != 0 {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }

    private func teardownSystemAudioRoute() {
        if engine.isRunning {
            engine.stop()
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if processTapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = kAudioObjectUnknown
        }
        currentTapUID = nil
    }

    /// Re-points the route at the new system output device.
    ///
    /// This rebuilds the tap and aggregate from scratch rather than
    /// reconfiguring in place. An in-place `setComposition` still requires
    /// stopping the IOProc, and that permanently deactivates the aggregate's
    /// auto-started tap: the device would come back reporting no error while
    /// playing silence. A full rebuild is the only path known to restore audio.
    private func rebuildRoute() {
        // While the EQ is off there is intentionally no tap/aggregate; the route
        // gets built fresh on the next start(), so don't resurrect it here.
        guard isSetup, isRunning, aggregateDeviceID != kAudioObjectUnknown else { return }

        guard let outputUID = Self.getDeviceUID(deviceID: selectedOutputDeviceID) ?? Self.getDefaultOutputDeviceUID() else {
            routeErrorMessage = "\(AudioRouteError.noOutputDevice)"
            return
        }

        NSLog("Switching output device to \(outputUID)")
        stopProcessing()
        teardownSystemAudioRoute()
        isRunning = false
        start()
    }

    // MARK: - Audio Engine Setup

    /// Prepares the EQ node only. The tap/aggregate route is deliberately *not*
    /// built here — it's built in `start()`, so simply launching the app never
    /// touches anyone else's audio.
    private func setupEngine() {
        eqNode = AVAudioUnitEQ(numberOfBands: bands.count)
        syncEQNode()

        // Amplification is applied via AVAudioUnitEQ.globalGain (+24 dB max),
        // the native boost on the EQ processor.
        applyMasterGain()

        // The EQ node is attached in `startProcessing()`, which builds the
        // graph on a fresh AVAudioEngine each time.
        startHardwareListening()
        isSetup = true
    }

    private func syncEQNode() {
        guard let eqNode else { return }
        for (i, band) in bands.enumerated() where i < eqNode.bands.count {
            let f = eqNode.bands[i]
            f.filterType = band.filterType.avType
            f.frequency = Float(band.frequency)
            f.gain = Float(band.gain)
            f.bandwidth = Float(band.bandwidth)
            f.bypass = !band.isEnabled || isBypassed
        }
    }

    private func formatDescription(_ format: AVAudioFormat) -> String {
        guard format.sampleRate > 0 else { return "—" }
        return "\(Int(format.sampleRate / 1000))kHz \(format.channelCount)ch"
    }

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }

        do {
            // The tap is created here rather than at launch: a live tap mutes
            // every process it captures, so it must not exist while the EQ is off.
            if aggregateDeviceID == kAudioObjectUnknown {
                try buildSystemAudioRoute()
            }
            try startProcessing()
            routeErrorMessage = nil
            isRunning = true
            startMetering()
            NSLog("Started — in=\(inputFormat) out=\(outputFormat) amplification %.2fx (%+.1f dB)", masterGain, amplificationDB)
        } catch {
            routeErrorMessage = "\(error)"
            NSLog("Cannot start: \(error)")
            stopProcessing()
            teardownSystemAudioRoute()
        }
    }

    func stop() {
        guard isRunning else { return }
        stopMetering()
        stopProcessing()
        isRunning = false
        // Destroying the tap is what un-mutes everyone else's audio — without
        // this, system audio stays silent until the app quits.
        teardownSystemAudioRoute()
    }

    // MARK: - Realtime Processing
    //
    // AVAudioEngine's `inputNode` cannot see an aggregate device's tap streams
    // (it reports 0 input channels no matter when the device is assigned), so
    // the I/O is driven by a raw AudioDeviceIOProc on the aggregate instead:
    // the callback receives the tap's captured audio and the real device's
    // output buffers together, already clock-synced. The EQ graph runs in
    // manual rendering mode so `AVAudioUnitEQ` still does the actual filtering.

    private func startProcessing() throws {
        try buildRenderGraph()
        try startIOProc()
    }

    /// Builds the EQ graph and points the renderer at it. Deliberately separate
    /// from the IOProc: stopping the aggregate's IOProc also deactivates its
    /// auto-started tap, and the tap does not come back when a new IOProc
    /// starts — the capture buffers stay zeroed while the tap keeps muting the
    /// real output, which is exactly what "changing the band count mutes it"
    /// looked like.
    private func buildRenderGraph() throws {
        var tapASBD = try tapStreamFormat()
        guard let tapFormat = AVAudioFormat(streamDescription: &tapASBD), tapFormat.channelCount > 0 else {
            throw AudioRouteError.tapFormatUnavailable
        }

        let outputASBD = try outputStreamFormat()
        guard let renderFormat = AVAudioFormat(
            standardFormatWithSampleRate: tapFormat.sampleRate,
            channels: tapFormat.channelCount
        ) else {
            throw AudioRouteError.outputFormatUnavailable
        }

        let ctx = renderer
        ctx.inputASBD = tapASBD
        ctx.outputASBD = outputASBD
        ctx.maxFrames = 4096
        ctx.inputBufferOffset = tapBufferOffset(tapChannels: tapFormat.channelCount)

        // The graph runs in the standard non-interleaved float format that
        // AVAudioUnitEQ requires; the renderer converts the tap's layout to match.
        // Build the graph on a brand-new AVAudioEngine. Reusing one instance
        // across sessions means repeatedly enabling and disabling manual
        // rendering mode, which leaves the graph alive but rendering silence —
        // that is why changing the band count used to mute the output.
        let engine = AVAudioEngine()
        self.engine = engine

        if let owner = eqNode.engine {
            owner.detach(eqNode)
        }
        engine.attach(eqNode)

        let source = AVAudioSourceNode(format: renderFormat) { _, _, frameCount, ablPtr in
            ctx.copyCapturedAudio(into: ablPtr, frameCount: frameCount)
        }
        sourceNode = source
        engine.attach(source)
        engine.connect(source, to: eqNode, format: renderFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: renderFormat)

        do {
            try engine.enableManualRenderingMode(.realtime, format: renderFormat, maximumFrameCount: ctx.maxFrames)
            engine.prepare()
            try engine.start()
        } catch {
            throw AudioRouteError.manualRenderingFailed(error.localizedDescription)
        }

        ctx.setRenderTarget(
            block: engine.manualRenderingBlock,
            buffer: AVAudioPCMBuffer(pcmFormat: renderFormat, frameCapacity: ctx.maxFrames)
        )

        inputFormat = formatDescription(tapFormat)
        outputFormat = "\(Int(outputASBD.mSampleRate / 1000))kHz \(outputASBD.mChannelsPerFrame)ch"
    }

    /// Tears the EQ graph down while leaving the IOProc (and therefore the tap)
    /// running. The renderer outputs silence until a new graph is installed.
    private func teardownRenderGraph() {
        renderer.setRenderTarget(block: nil, buffer: nil)

        if engine.isRunning { engine.stop() }
        if let source = sourceNode {
            engine.detach(source)
            sourceNode = nil
        }
        if let eqNode, eqNode.engine != nil {
            engine.detach(eqNode)
        }
        // Drop the whole engine rather than disabling manual rendering on it:
        // the next graph gets a clean instance.
        engine = AVAudioEngine()
    }

    private func startIOProc() throws {
        let ctx = renderer
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, nil) { _, inInput, _, outOutput, _ in
            ctx.process(input: inInput, output: outOutput)
        }
        guard status == noErr, let procID else {
            throw AudioRouteError.ioProcCreationFailed(status)
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard startStatus == noErr else {
            throw AudioRouteError.deviceStartFailed(startStatus)
        }
    }

    private func stopIOProc() {
        guard let procID = ioProcID else { return }
        AudioDeviceStop(aggregateDeviceID, procID)
        AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        ioProcID = nil
    }

    private func stopProcessing() {
        stopIOProc()
        teardownRenderGraph()
    }

    /// Index of the tap's first buffer inside the aggregate device's *input*
    /// stream configuration.
    ///
    /// An aggregate lists each sub-device's own input buffers before the tap's.
    /// Most output devices have no inputs, so the tap normally starts at 0 —
    /// but a device that also captures (the Xbox headset bridge publishes a
    /// microphone alongside its output) shifts the tap along. Reading buffer 0
    /// unconditionally then feeds the EQ that microphone instead of the system
    /// audio, which sounds exactly like the device has been muted.
    private func tapBufferOffset(tapChannels: UInt32) -> Int {
        let aggregate = Self.inputBufferChannelCounts(deviceID: aggregateDeviceID)
        let subDevice = Self.inputBufferChannelCounts(deviceID: selectedOutputDeviceID)

        if subDevice.count < aggregate.count,
           Array(aggregate.prefix(subDevice.count)) == subDevice {
            return subDevice.count
        }

        // Composition didn't line up (an unexpected aggregate layout): fall back
        // to the first buffer whose width matches the tap's own format.
        if let index = aggregate.firstIndex(of: tapChannels) {
            return index
        }
        return 0
    }

    private func tapStreamFormat() throws -> AudioStreamBasicDescription {
        guard processTapID != kAudioObjectUnknown,
              let format = try? AudioHardwareTap(id: processTapID).format else {
            throw AudioRouteError.tapFormatUnavailable
        }
        return format
    }

    private func outputStreamFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(aggregateDeviceID, &address, 0, nil, &size, &asbd)
        guard status == noErr, asbd.mChannelsPerFrame > 0 else {
            throw AudioRouteError.outputFormatUnavailable
        }
        return asbd
    }

    // MARK: - Metering
    //
    // Levels and spectrum are sampled off the realtime thread: the IOProc only
    // copies rendered frames into a preallocated scratch buffer.

    private func startMetering() {
        stopMetering()
        // .common so the display keeps updating while a slider is being dragged.
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMeters() }
        }
        meterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        meters.snapshot = MeterSnapshot()
    }

    private func updateMeters() {
        guard let buffer = renderer.copyLatestFrames() else { return }
        meters.snapshot = MeterSnapshot(
            spectrum: fftAnalyzer.analyze(buffer: buffer),
            level: min(1.0, buffer.rms * 3.0),
            latencyMs: renderer.latencyMs
        )
    }

    // MARK: - Band Controls

    func setGain(_ gain: Double, forBand index: Int) {
        guard index >= 0, index < bands.count else { return }
        bands[index].gain = gain.clamped(to: Self.minBandGain...Self.maxBandGain)
        applyBandToNode(index)
    }

    func setFrequency(_ freq: Double, forBand index: Int) {
        guard index >= 0, index < bands.count else { return }
        bands[index].frequency = freq
        applyBandToNode(index)
    }

    func setBandwidth(_ bw: Double, forBand index: Int) {
        guard index >= 0, index < bands.count else { return }
        bands[index].bandwidth = bw.clamped(to: 0.1...5.0)
        applyBandToNode(index)
    }

    func setFilterType(_ type: EQBand.FilterType, forBand index: Int) {
        guard index >= 0, index < bands.count else { return }
        bands[index].filterType = type
        applyBandToNode(index)
    }

    func toggleBand(_ index: Int, enabled: Bool) {
        guard index >= 0, index < bands.count else { return }
        bands[index].isEnabled = enabled
        applyBandToNode(index)
    }

    func applyBandToNode(_ index: Int) {
        guard let eqNode, index < eqNode.bands.count, index < bands.count else { return }
        let band = bands[index]
        let f = eqNode.bands[index]
        f.filterType = band.filterType.avType
        f.frequency = Float(band.frequency)
        f.gain = Float(band.gain)
        f.bandwidth = Float(band.bandwidth)
        f.bypass = !band.isEnabled || isBypassed
    }

    func applyAllBands() {
        syncEQNode()
    }

    func applyPreset(_ preset: EQPreset) {
        // A built-in preset is a curve, so it can be resampled onto whatever
        // band layout the user is on — selecting one in 31-band mode keeps 31
        // bands instead of snapping back to ten. Custom and imported presets
        // only have a band list, so those still set the layout.
        if let curve = preset.curve {
            bands = curve.applied(to: bands)
            applyAllBands()
            return
        }

        bands = preset.bands
        if eqNode.bands.count != bands.count {
            rebuildEQNode()
        }
        applyAllBands()
    }

    /// Swaps in a new EQ node when the band count changes.
    ///
    /// Only the render graph is rebuilt — the IOProc, aggregate device and tap
    /// all stay up. Stopping the IOProc here would deactivate the tap for good
    /// and leave the output silently muted until the user toggled the engine
    /// off and on again. The renderer emits silence for the few milliseconds
    /// the graph is missing.
    private func rebuildEQNode() {
        let wasProcessing = isRunning
        if wasProcessing { teardownRenderGraph() }

        if let existing = eqNode, let owner = existing.engine {
            owner.detach(existing)
        }
        eqNode = AVAudioUnitEQ(numberOfBands: bands.count)
        syncEQNode()
        applyMasterGain()

        guard wasProcessing else { return }
        do {
            try buildRenderGraph()
            routeErrorMessage = nil
        } catch {
            routeErrorMessage = "\(error)"
            NSLog("Failed to rebuild the EQ graph: \(error)")
            stop()
        }
    }

    func resetToFlat() {
        for i in bands.indices {
            bands[i].gain = 0
        }
        applyAllBands()
    }

    func toggleBypass() {
        isBypassed.toggle()
        guard let eqNode else { return }
        for i in eqNode.bands.indices {
            eqNode.bands[i].bypass = isBypassed || (bands[safe: i]?.isEnabled ?? true) == false
        }
    }

    // MARK: - Band Count

    func setBandCount(_ count: Int) {
        guard count != bands.count else { return }
        let freqs: [Double]
        switch count {
        case 31: freqs = EQPreset.extendedFrequencies
        case 15: freqs = EQPreset.fifteenBandFrequencies
        default: freqs = EQPreset.defaultFrequencies
        }

        let oldBands = bands
        bands = freqs.map { f in
            let closest = oldBands.min { abs($0.frequency - f) < abs($1.frequency - f) }
            return EQBand(
                frequency: f,
                gain: closest?.gain ?? 0,
                bandwidth: closest?.bandwidth ?? 1.0,
                filterType: closest?.filterType ?? .parametric
            )
        }

        rebuildEQNode()
        applyAllBands()
    }

}

// MARK: - Meters

struct MeterSnapshot {
    var spectrum: [Float] = Array(repeating: 0, count: 64)
    var level: Double = 0
    var latencyMs: Double = 0
}

@MainActor
final class MeterState: ObservableObject {
    @Published var snapshot = MeterSnapshot()
}

// MARK: - Realtime Renderer

/// Owns everything touched on the Core Audio IO thread. Kept separate from
/// `AudioEngine` (which is `@MainActor`) so realtime code never touches
/// main-actor state.
final class SystemAudioRenderer: @unchecked Sendable {

    /// Swapped from the main actor while the IOProc keeps running, so it is
    /// guarded by a lock the realtime thread only ever `try()`s.
    private let renderLock = NSLock()
    private var renderBlock: AVAudioEngineManualRenderingBlock?
    private var renderBuffer: AVAudioPCMBuffer?

    /// Points the IOProc at a new EQ graph (or, with `nil`, at silence while
    /// one is being rebuilt). Blocks only for the length of one render call.
    func setRenderTarget(block: AVAudioEngineManualRenderingBlock?, buffer: AVAudioPCMBuffer?) {
        renderLock.lock()
        renderBlock = block
        renderBuffer = buffer
        renderLock.unlock()
    }

    var inputASBD = AudioStreamBasicDescription()
    var outputASBD = AudioStreamBasicDescription()
    var maxFrames: AVAudioFrameCount = 4096
    /// Where the tap's buffers start inside the IOProc's input buffer list —
    /// see `AudioEngine.tapBufferOffset(tapChannels:)`.
    var inputBufferOffset: Int = 0
    private(set) var latencyMs: Double = 0

    /// The current IOProc cycle's captured audio, valid only for the duration
    /// of that callback.
    private var capturedInput: UnsafePointer<AudioBufferList>?

    /// Rolling window of recent rendered mono samples. Sized for one FFT window
    /// so the spectrum always has a full frame to analyse, regardless of the
    /// device's IO buffer size.
    private static let analysisWindow = 1024
    private let scratchLock = NSLock()
    private var scratch = [Float](repeating: 0, count: SystemAudioRenderer.analysisWindow)
    private var scratchWriteIndex = 0
    private var scratchFilled = false
    private var scratchSampleRate: Double = 48000
    private var snapshotBuffer: AVAudioPCMBuffer?

    /// Called from the source node while the EQ graph renders: hands the graph
    /// the audio the tap just captured.
    func copyCapturedAudio(into ablPtr: UnsafeMutablePointer<AudioBufferList>, frameCount: AVAudioFrameCount) -> OSStatus {
        let out = UnsafeMutableAudioBufferListPointer(ablPtr)

        guard let input = capturedInput else {
            silence(out)
            return noErr
        }

        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let inputIsInterleaved = (inputASBD.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        guard src.count > 0 else {
            silence(out)
            return noErr
        }
        // Skip any buffers the aggregate's sub-device contributed ahead of the tap.
        let offset = inputBufferOffset < src.count ? inputBufferOffset : 0

        if inputIsInterleaved, let base = src[offset].mData {
            let first = src[offset]
            // One buffer holding L,R,L,R… — spread it across the graph's
            // separate per-channel buffers.
            let interleaved = base.assumingMemoryBound(to: Float.self)
            let sourceChannels = max(1, Int(first.mNumberChannels))
            let available = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * sourceChannels)
            let frames = min(Int(frameCount), available)

            for channel in 0..<out.count {
                guard let dest = out[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                let sourceChannel = min(channel, sourceChannels - 1)
                vDSP_vgathr_stride(interleaved, sourceChannel, sourceChannels, dest, frames)
                if frames < Int(frameCount) {
                    memset(dest + frames, 0, (Int(frameCount) - frames) * MemoryLayout<Float>.size)
                }
            }
            return noErr
        }

        for index in 0..<out.count {
            guard let dest = out[index].mData else { continue }
            let sourceIndex = offset + index
            if sourceIndex < src.count, let source = src[sourceIndex].mData {
                let bytes = min(Int(out[index].mDataByteSize), Int(src[sourceIndex].mDataByteSize))
                memcpy(dest, source, bytes)
                if bytes < Int(out[index].mDataByteSize) {
                    memset(dest + bytes, 0, Int(out[index].mDataByteSize) - bytes)
                }
            } else {
                memset(dest, 0, Int(out[index].mDataByteSize))
            }
        }
        return noErr
    }

    /// Copies every `stride`-th float starting at `offset` into a contiguous
    /// buffer. Runs on the realtime thread, so it uses vDSP's strided copy
    /// rather than a scalar loop.
    private func vDSP_vgathr_stride(_ source: UnsafePointer<Float>, _ offset: Int, _ stride: Int, _ dest: UnsafeMutablePointer<Float>, _ frames: Int) {
        guard frames > 0 else { return }
        if stride > 0 {
            vDSP_mmov(source + offset, dest, vDSP_Length(1), vDSP_Length(frames), vDSP_Length(stride), vDSP_Length(1))
            return
        }
        var index = offset
        for frame in 0..<frames {
            dest[frame] = source[index]
            index += stride
        }
    }

    /// The IOProc body: EQ the tap's audio and write it to the real device.
    func process(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let outList = UnsafeMutableAudioBufferListPointer(output)
        guard let firstOut = outList.first else { return }

        // Never leave the output buffers untouched: the IOProc stays alive
        // across graph rebuilds, and whatever the device left there would play
        // as noise.
        guard renderLock.try() else {
            silence(outList)
            return
        }
        defer { renderLock.unlock() }

        guard let renderBlock, let renderBuffer else {
            silence(outList)
            return
        }

        let bytesPerFrame = max(1, outputASBD.mBytesPerFrame)
        let frames = AVAudioFrameCount(firstOut.mDataByteSize / bytesPerFrame)
        guard frames > 0, frames <= maxFrames else { return }

        capturedInput = input
        defer { capturedInput = nil }

        renderBuffer.frameLength = frames
        var status: OSStatus = noErr
        let result = renderBlock(frames, renderBuffer.mutableAudioBufferList, &status)
        guard result == .success, status == noErr else {
            silence(outList)
            return
        }

        write(renderBuffer, frames: frames, to: outList)
        captureForMetering(renderBuffer, frames: frames)
    }

    private func silence(_ outList: UnsafeMutableAudioBufferListPointer) {
        for buffer in outList {
            if let data = buffer.mData {
                memset(data, 0, Int(buffer.mDataByteSize))
            }
        }
    }

    /// Copies the rendered (non-interleaved float) frames into whatever layout
    /// the output device expects.
    private func write(_ buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount, to outList: UnsafeMutableAudioBufferListPointer) {
        guard let rendered = buffer.floatChannelData else {
            silence(outList)
            return
        }

        let renderedChannels = Int(buffer.format.channelCount)
        let isInterleaved = (outputASBD.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0

        if isInterleaved {
            guard let first = outList.first, let dest = first.mData, renderedChannels > 0 else { return }
            let outChannels = Int(outputASBD.mChannelsPerFrame)
            let out = dest.assumingMemoryBound(to: Float.self)
            // Strided scatter per channel — vDSP rather than a scalar loop,
            // since this runs on the realtime thread for every IO cycle.
            for channel in 0..<outChannels {
                let source = rendered[min(channel, renderedChannels - 1)]
                vDSP_mmov(source, out + channel, vDSP_Length(1), vDSP_Length(frames), vDSP_Length(1), vDSP_Length(outChannels))
            }
        } else {
            for index in 0..<outList.count {
                guard let dest = outList[index].mData else { continue }
                let source = rendered[min(index, renderedChannels - 1)]
                let bytes = min(Int(outList[index].mDataByteSize), Int(frames) * MemoryLayout<Float>.size)
                memcpy(dest, source, bytes)
            }
        }
    }

    private func captureForMetering(_ buffer: AVAudioPCMBuffer, frames: AVAudioFrameCount) {
        guard let channelData = buffer.floatChannelData, scratchLock.try() else { return }
        defer { scratchLock.unlock() }

        let capacity = scratch.count
        let source = channelData[0]
        var remaining = min(Int(frames), capacity)
        var sourceOffset = Int(frames) - remaining

        while remaining > 0 {
            let chunk = min(remaining, capacity - scratchWriteIndex)
            scratch.withUnsafeMutableBufferPointer { dest in
                if let base = dest.baseAddress {
                    memcpy(base + scratchWriteIndex, source + sourceOffset, chunk * MemoryLayout<Float>.size)
                }
            }
            scratchWriteIndex = (scratchWriteIndex + chunk) % capacity
            if scratchWriteIndex == 0 { scratchFilled = true }
            sourceOffset += chunk
            remaining -= chunk
        }

        scratchSampleRate = buffer.format.sampleRate
        latencyMs = Double(frames) / buffer.format.sampleRate * 1000
    }

    /// Snapshot of the most recent rendered audio, oldest sample first, for
    /// level and spectrum display. Reuses one buffer — this runs 20x a second.
    func copyLatestFrames() -> AVAudioPCMBuffer? {
        scratchLock.lock()
        defer { scratchLock.unlock() }

        let available = scratchFilled ? scratch.count : scratchWriteIndex
        guard available > 0 else { return nil }

        if snapshotBuffer == nil || snapshotBuffer?.format.sampleRate != scratchSampleRate {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: scratchSampleRate, channels: 1) else {
                return nil
            }
            snapshotBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(scratch.count))
        }

        guard let buffer = snapshotBuffer, let dest = buffer.floatChannelData else { return nil }
        buffer.frameLength = AVAudioFrameCount(available)

        scratch.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            if scratchFilled {
                // Unwrap the ring so the newest sample lands at the end.
                let tail = scratch.count - scratchWriteIndex
                memcpy(dest[0], base + scratchWriteIndex, tail * MemoryLayout<Float>.size)
                memcpy(dest[0] + tail, base, scratchWriteIndex * MemoryLayout<Float>.size)
            } else {
                memcpy(dest[0], base, available * MemoryLayout<Float>.size)
            }
        }
        return buffer
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

extension AVAudioPCMBuffer {
    /// RMS level normalized to ~0...1
    var rms: Double {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        let length = Int(frameLength)
        var sumSquares: Float = 0
        vDSP_svesq(data[0], 1, &sumSquares, vDSP_Length(length))
        let rms = sqrtf(sumSquares / Float(length))
        // RMS ≈ -3dB of peak; scale for display
        return Double(rms * 1.4)
    }
}
