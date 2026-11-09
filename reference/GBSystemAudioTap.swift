import AVFoundation
import CoreAudio
import Foundation

// GBSystemAudioTap — system sound through a Core Audio process tap
// (macOS 14.2+), the experimental alternative to ScreenCaptureKit audio
// for the "iMac only" route.
//
// The tap covers every process except DisplayBridge and is MUTED: macOS
// hands us the sound and sends none of it to this Mac's speakers
// (CATapMuted). So the speakers never have to be muted — their volume and
// mute stay free for the keys, which GBAudioRouter's volume mirror then
// forwards to the iMac. The earlier attempt muted the speakers and re-muted
// them after every key press; a few ms of sound leaked each time (user
// test 2026-10-27). A tap also skips ScreenCaptureKit's ~57 ms of audio
// buffering.
//
// Reading a tap = a private aggregate device with the tap in its tap list
// and the current output as its clock; its IOProc's input is the tapped
// mix. Needs the "System Audio Recording" permission; without it macOS
// delivers silence, so `heardSound` tells the session whether anything
// non-zero ever came through.

@available(macOS 14.2, *)
public final class GBSystemAudioTap {
    public enum TapError: Error, CustomStringConvertible {
        case step(String, OSStatus)
        public var description: String {
            switch self {
            case .step(let what, let status): return "\(what) failed (\(status))"
            }
        }
    }

    /// Interleaved s16 stereo 48 kHz (the receiver's format, protocol
    /// 0x23), plus how old the chunk's first sample is and its length, ms.
    public var onAudio: ((Data, Double, Double) -> Void)?
    /// Anything but digital silence arrived (permission check).
    public private(set) var heardSound = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "app.displaybridge.system-audio-tap",
                                      qos: .userInteractive)
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat = {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
        return AVAudioFormat(streamDescription: &asbd)!
    }()

    public init() {}

    deinit { stop() }

    public func start() throws {
        stop()
        // Everything but ourselves (the receiver engine child plays only
        // when this Mac is the display, not while it sends).
        var excluded: [AudioObjectID] = []
        if let own = Self.processObject(pid: getpid()) { excluded.append(own) }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "DisplayBridge"
        description.isPrivate = true
        description.muteBehavior = .muted

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
            stop()
            throw TapError.step("read tap format", status)
        }
        inputFormat = format
        converter = AVAudioConverter(from: format, to: outputFormat)

        guard let outputUID = Self.defaultOutputUID() else {
            stop()
            throw TapError.step("find output device", -1)
        }
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DisplayBridge Tap",
            kAudioAggregateDeviceUIDKey: "app.displaybridge.tap." + UUID().uuidString,
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
            stop()
            throw TapError.step("create aggregate device", status)
        }
        aggregateID = aggregate

        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) {
            [weak self] now, inputData, inputTime, _, _ in
            self?.deliver(inputData, inputTime: inputTime.pointee, now: now.pointee)
        }
        guard status == noErr, let procID else {
            stop()
            throw TapError.step("create IO proc", status)
        }
        ioProcID = procID
        status = AudioDeviceStart(aggregate, procID)
        guard status == noErr else {
            stop()
            throw TapError.step("start", status)
        }
    }

    /// Idempotent. Destroying the tap gives the sound back to the speakers.
    public func stop() {
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
    }

    // On `queue`.
    private func deliver(_ input: UnsafePointer<AudioBufferList>,
                         inputTime: AudioTimeStamp, now: AudioTimeStamp) {
        guard let inputFormat, let converter,
              let source = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                            bufferListNoCopy: input, deallocator: nil),
              source.frameLength > 0 else { return }
        if !heardSound, let channels = source.floatChannelData {
            let count = Int(source.frameLength) * (inputFormat.isInterleaved ? Int(inputFormat.channelCount) : 1)
            for channel in 0..<(inputFormat.isInterleaved ? 1 : Int(inputFormat.channelCount))
            where (0..<count).contains(where: { channels[channel][$0] != 0 }) {
                heardSound = true
                break
            }
        }
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
              let samples = output.int16ChannelData else { return }
        let data = Data(bytes: samples.pointee, count: Int(output.frameLength) * 4)
        var ageMs = 0.0
        if inputTime.mFlags.contains(.hostTimeValid), now.mFlags.contains(.hostTimeValid),
           now.mHostTime >= inputTime.mHostTime {
            ageMs = Double(AudioConvertHostTimeToNanos(now.mHostTime - inputTime.mHostTime)) / 1e6
        }
        let chunkMs = Double(source.frameLength) / inputFormat.sampleRate * 1000
        onAudio?(data, ageMs, chunkMs)
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
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
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
