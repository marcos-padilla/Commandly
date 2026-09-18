import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

/// Availability-erased face of a per-app gain engine, so the mixer can hold engines on any macOS
/// while the implementation requires the process-tap API.
nonisolated protocol MixerGainEngine: AnyObject, Sendable {
    var gain: Float { get set }
    var tappedObjects: [AudioObjectID] { get }
    var outputDeviceUID: String { get }
    /// How many IO callbacks the engine has completed. A count that stops moving while the
    /// tapped app is playing means the aggregate is no longer rendering, so the tap can only
    /// mute.
    var renderCycles: UInt64 { get }
    func stop()
}

/// The audio path for one routed app: a muted process tap feeding a private aggregate device
/// whose IO proc re-renders the samples, scaled by `gain`, onto the chosen output.
///
/// `@unchecked Sendable`: `gain` and `renderCycles` are atomics shared with the realtime thread;
/// the CoreAudio identifiers are written only during `init` and `stop`, which the mixer calls
/// from the main actor, and `stop` hands ownership of the identifiers to its teardown queue
/// before clearing them.
@available(macOS 14.4, *)
nonisolated final class TapGainEngine: MixerGainEngine, @unchecked Sendable {
    let tappedObjects: [AudioObjectID]
    let outputDeviceUID: String

    var gain: Float {
        get { gainBox.value }
        set { gainBox.value = min(max(newValue, 0), Float(MixerRoutingRules.maximumVolume)) }
    }

    var renderCycles: UInt64 { cycleBox.value }

    private let gainBox = AtomicFloatBox(1)
    private let cycleBox = AtomicCycleBox()
    /// How fast the limiter recovers. Kept beside the limiter rather than inside it: the device
    /// can change its rate while this engine keeps rendering, and the audio thread must never
    /// find another thread halfway through writing that state.
    private let releaseBox: AtomicFloatBox

    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProc: AudioDeviceIOProcID?
    /// The retained release box handed to the sample-rate listener, released with the listener.
    private var rateListenerClient: UnsafeMutableRawPointer?

    init?(objects: [AudioObjectID], gain: Float, outputDeviceUID: String) {
        tappedObjects = objects
        self.outputDeviceUID = outputDeviceUID
        releaseBox = AtomicFloatBox(BoostLimiter.release(sampleRate: 48_000))
        self.gain = gain

        let description = CATapDescription(stereoMixdownOfProcesses: objects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return nil
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: CoreAudioProperties.aggregateDeviceName,
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0 else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        let limiter = MixerLimiterBox(
            channelCapacity: CoreAudioProperties.outputChannelCapacity(of: aggregateID)
        )
        releaseBox.value = BoostLimiter.release(
            sampleRate: CoreAudioProperties.nominalSampleRate(of: aggregateID)
        )

        let gain = gainBox
        let cycles = cycleBox
        let release = releaseBox
        let tapChannels = Self.tapChannels(of: tapID)

        guard AudioDeviceCreateIOProcIDWithBlock(
            &ioProc, aggregateID, nil,
            { _, input, _, output, _ in
                let inputBuffers = UnsafeMutableAudioBufferListPointer(
                    UnsafeMutablePointer(mutating: input)
                )
                let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
                guard let tapIndex = MixerRender.tapBufferIndex(
                    in: inputBuffers,
                    tapChannels: tapChannels
                ) else {
                    // No samples to put in the buffer is not a reason to leave it: whatever the
                    // HAL left there would play otherwise.
                    MixerRender.silence(outputBuffers)
                    return
                }
                // `render` silences whatever it does not fill, so every path from here on leaves
                // the output written.
                let frames = MixerRender.render(
                    source: inputBuffers[tapIndex],
                    into: outputBuffers,
                    gain: gain.value
                )
                // Keep the small lookahead delay filled for every live engine, so crossing from
                // attenuation into boost changes level without inserting a block of silence.
                guard frames > 0 else { return }
                cycles.increment()
                let releaseCoefficient = release.value
                if limiter.lookahead.process(
                    outputBuffers, frames: frames, release: releaseCoefficient
                ) == false {
                    limiter.fallback.process(
                        outputBuffers, frames: frames, release: releaseCoefficient
                    )
                }
            }
        ) == noErr else {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        // Installed only once there is something to keep current, so the failure paths above
        // have nothing to undo.
        startWatchingSampleRate()

        guard AudioDeviceStart(aggregateID, ioProc) == noErr else {
            stop()
            return nil
        }
    }

    deinit { stop() }

    func stop() {
        let tapID = self.tapID
        let aggregateID = self.aggregateID
        let ioProc = self.ioProc
        let listenerClient = rateListenerClient
        guard tapID != 0 || aggregateID != 0 || ioProc != nil || listenerClient != nil else {
            return
        }

        self.tapID = 0
        self.aggregateID = 0
        self.ioProc = nil
        rateListenerClient = nil

        // `mutedWhenTapped` suppresses the app's original output only while the tap is being
        // read. Stop that read before returning so audio is handed back immediately; the cleanup
        // calls after it can wait on a broken HAL path and therefore run off the main actor.
        if let ioProc, aggregateID != 0 {
            AudioDeviceStop(aggregateID, ioProc)
        }

        Self.teardownQueue.addOperation {
            if let listenerClient {
                var mayReleaseListener = aggregateID == 0
                if aggregateID != 0 {
                    var address = CoreAudioProperties.nominalSampleRateAddress()
                    mayReleaseListener = AudioObjectRemovePropertyListener(
                        aggregateID, &address, Self.sampleRateListener, listenerClient
                    ) == noErr
                }
                // If the HAL refuses removal, keep the tiny callback box: a late callback is
                // safer than dereferencing released memory.
                if mayReleaseListener {
                    Unmanaged<AtomicFloatBox>.fromOpaque(listenerClient).release()
                }
            }
            if let ioProc, aggregateID != 0 {
                AudioDeviceDestroyIOProcID(aggregateID, ioProc)
            }
            if aggregateID != 0 {
                AudioHardwareDestroyAggregateDevice(aggregateID)
            }
            if tapID != 0 {
                AudioHardwareDestroyProcessTap(tapID)
            }
        }
    }

    /// Keeps the limiter's recovery honest when the output device changes its rate under a
    /// running engine.
    ///
    /// A headset that takes the microphone for a call renegotiates to a call rate and the
    /// aggregate follows it without the IO proc ever stopping. Nothing else would notice, so a
    /// boosted app would keep recovering at the old rate's speed for the life of the engine.
    private func startWatchingSampleRate() {
        var address = CoreAudioProperties.nominalSampleRateAddress()
        let client = Unmanaged.passRetained(releaseBox).toOpaque()
        guard AudioObjectAddPropertyListener(
            aggregateID, &address, Self.sampleRateListener, client
        ) == noErr else {
            Unmanaged<AtomicFloatBox>.fromOpaque(client).release()
            return
        }
        rateListenerClient = client
    }

    /// Where a new rate is read, away from whatever thread the notification arrived on. Serial,
    /// so two changes in a row cannot land out of order.
    private static let rateQueue = DispatchQueue(
        label: "com.businessmate360.Commandly.mixer.rate",
        qos: .userInitiated
    )

    /// How many teardowns may sit in the HAL at once.
    ///
    /// A broken HAL path can park inside teardown. Serialized, one parked call would leave every
    /// later engine's aggregate and tap alive behind it. Overlapping them lets the rest through,
    /// under a bound so parked operations cannot take the shared thread pool with them.
    private static let teardownQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.businessmate360.Commandly.mixer.teardown"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 4
        return queue
    }()

    /// The smallest possible answer: the system decides which thread this arrives on. Reading
    /// the audio system here would park that thread behind the very device being reconfigured.
    private static let sampleRateListener: AudioObjectPropertyListenerProc = { deviceID, _, _, client in
        guard let client else { return noErr }
        // Held for the hop, so the engine can stop and hand back its registration without the
        // read landing in memory that is gone.
        let box = Unmanaged<AtomicFloatBox>.fromOpaque(client).takeUnretainedValue()
        rateQueue.async {
            box.value = BoostLimiter.release(
                sampleRate: CoreAudioProperties.nominalSampleRate(of: deviceID)
            )
        }
        return noErr
    }

    /// How many channels the tap hands over, used to find it among the aggregate's input
    /// buffers. A stereo mixdown is what the tap is asked for, so that is also the fallback.
    private static func tapChannels(of tapID: AudioObjectID) -> Int {
        var format = AudioStreamBasicDescription()
        guard CoreAudioProperties.read(tapID, kAudioTapPropertyFormat, &format),
              format.mChannelsPerFrame > 0 else { return 2 }
        return Int(format.mChannelsPerFrame)
    }
}

/// One limiter pair per engine, preallocated so the realtime thread never allocates.
///
/// `@unchecked Sendable`: created before the IO proc starts and touched only by the realtime
/// thread afterwards.
private nonisolated final class MixerLimiterBox: @unchecked Sendable {
    let lookahead: BoostLookaheadBufferListLimiter
    var fallback = BoostBufferListLimiter()

    init(channelCapacity: Int) {
        lookahead = BoostLookaheadBufferListLimiter(channelCapacity: channelCapacity)
    }
}

/// A single atomically exchanged float, shared between the audio thread and whoever sets it.
///
/// A class rather than a bare `Atomic`, because an atomic is non-copyable and the realtime
/// callback has to capture something it can hold on to.
///
/// `@unchecked Sendable`: the one stored value is an atomic.
private nonisolated final class AtomicFloatBox: @unchecked Sendable {
    private let bits: Atomic<UInt32>

    init(_ value: Float) {
        bits = Atomic<UInt32>(value.bitPattern)
    }

    var value: Float {
        get { Float(bitPattern: bits.load(ordering: .relaxed)) }
        set { bits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

/// A monotonically rising render counter the audio thread bumps once per filled callback.
///
/// `@unchecked Sendable`: the one stored value is an atomic.
private nonisolated final class AtomicCycleBox: @unchecked Sendable {
    private let bits = Atomic<UInt64>(0)

    var value: UInt64 { bits.load(ordering: .relaxed) }

    func increment() { bits.wrappingAdd(1, ordering: .relaxed) }
}
