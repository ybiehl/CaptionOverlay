import AVFoundation
import CoreAudio
import Foundation

// SystemAudioTap: the Mac's system sound through a Core Audio process tap
// (macOS 14.2+). Adapted from reference/GBSystemAudioTap.swift.
//
// The tap covers every process except this app and is UNMUTED: the sound
// keeps playing normally, we only get a copy.
//
// Reading a tap = a private aggregate device with the tap in its tap list
// and the current output as its clock; its IOProc's input is the tapped
// mix. Needs the "System Audio Recording" permission; without it macOS
// delivers silence, so `heardSound` tells the app whether anything
// non-zero ever came through.
//
// The aggregate is tied to the output device it was built with, so the tap
// rebuilds itself when the default output changes (headphones, a display
// with speakers, DisplayBridge moving the sound).

public final class SystemAudioTap {
    public enum TapError: Error, CustomStringConvertible {
        case step(String, OSStatus)
        public var description: String {
            switch self {
            case .step(let what, let status): return "\(what) failed (\(status))"
            }
        }
    }

    /// The rate both speech engines are fed with.
    public static let sampleRate: Double = 16000

    /// Mono Float32 at `sampleRate`. Called on the tap's own queue.
    public var onAudio: (([Float]) -> Void)?
    /// Anything but digital silence arrived (permission check).
    public private(set) var heardSound = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "app.captionoverlay.system-audio-tap",
                                      qos: .userInitiated)
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var running = false

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    public init() {}

    deinit { stop() }

    public func start() throws {
        stop()
        try build()
        running = true
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // On `queue`. A failed rebuild leaves the tap down; the app
            // notices through the missing sound.
            guard let self, self.running else { return }
            self.teardown()
            try? self.build()
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, queue, listener)
    }

    /// Idempotent.
    public func stop() {
        running = false
        if let outputListener {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, queue,
                outputListener)
        }
        outputListener = nil
        teardown()
    }

    private func build() throws {
        // Everything but ourselves (the app makes no sound, but a tap that
        // includes its own process can feed back).
        var excluded: [AudioObjectID] = []
        if let own = Self.processObject(pid: getpid()) { excluded.append(own) }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "CaptionOverlay"
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr else { throw TapError.step("create tap", status) }
        tapID = tap

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        guard status == noErr, let format = AVAudioFormat(streamDescription: &asbd) else {
            teardown()
            throw TapError.step("read tap format", status)
        }
        // Resample only; the channels are averaged by hand in `deliver`
        // (AVAudioConverter's own stereo-to-mono drops a channel).
        guard let output = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate,
            channels: format.channelCount, interleaved: false),
            let converter = AVAudioConverter(from: format, to: output)
        else {
            teardown()
            throw TapError.step("make converter", -1)
        }
        inputFormat = format
        outputFormat = output
        self.converter = converter

        guard let outputUID = Self.defaultOutputUID() else {
            teardown()
            throw TapError.step("find output device", -1)
        }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "CaptionOverlay Tap",
            kAudioAggregateDeviceUIDKey: "app.captionoverlay.tap." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate)
        guard status == noErr else {
            teardown()
            throw TapError.step("create aggregate device", status)
        }
        aggregateID = aggregate

        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) {
            [weak self] _, inputData, _, _, _ in
            self?.deliver(inputData)
        }
        guard status == noErr, let procID else {
            teardown()
            throw TapError.step("create IO proc", status)
        }
        ioProcID = procID
        status = AudioDeviceStart(aggregate, procID)
        guard status == noErr else {
            teardown()
            throw TapError.step("start", status)
        }
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
        converter = nil
    }

    // On `queue`.
    private func deliver(_ input: UnsafePointer<AudioBufferList>) {
        guard let inputFormat, let outputFormat, let converter,
              let source = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                            bufferListNoCopy: input, deallocator: nil),
              source.frameLength > 0 else { return }
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else { return }
        var consumed = false
        var error: NSError?
        let result = converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return source
        }
        guard result != .error, error == nil, output.frameLength > 0,
              let channels = output.floatChannelData else { return }
        let frames = Int(output.frameLength)
        let channelCount = Int(outputFormat.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frames { mono[frame] += samples[frame] }
        }
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for frame in 0..<frames { mono[frame] *= scale }
        }
        if !heardSound, mono.contains(where: { $0 != 0 }) { heardSound = true }
        onAudio?(mono)
    }

    private static func processObject(pid: pid_t) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func defaultOutputUID() -> String? {
        var address = defaultOutputAddress
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                         0, nil, &size, &device) == noErr, device != 0
        else { return nil }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? uid as String : nil
    }
}
