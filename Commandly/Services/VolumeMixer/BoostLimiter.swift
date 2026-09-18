import CoreAudio
import Foundation

/// Shared constants for the mixer's peak limiters.
///
/// A boost above 100% pushes loud material past full scale, and clamping the overshoot sample by
/// sample flattens every peak into harsh crackle. A peak limiter instead turns the whole signal
/// down for exactly as long as a peak would not fit, which the ear reads as loudness rather than
/// distortion.
nonisolated enum BoostLimiter {
    /// Loudest sample the limiter lets out, about half a decibel below full scale.
    static let ceiling: Float = 0.944

    /// How long the gain takes to recover after a peak, chosen so speech and music breathe
    /// instead of pumping.
    static let releaseMilliseconds: Double = 160

    /// Frames of lookahead, so a peak is known before the sample it belongs to is emitted.
    static let lookaheadFrames = 256

    /// How much of the previous level survives one sample, so recovery lasts the same fraction
    /// of a second whatever the rate.
    ///
    /// This lives outside the limiters on purpose: a device can change its rate while the audio
    /// path stays up — exactly what a headset does when a call takes the microphone — and the
    /// engine must be able to hand the limiter a new figure without reaching into the state the
    /// audio thread is using.
    static func release(sampleRate: Double) -> Float {
        let rate = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        return Float(exp(-1_000.0 / (rate * releaseMilliseconds)))
    }
}

/// Lookahead limiter applied across every buffer in an AudioBufferList with one linked gain.
///
/// Non-interleaved stereo and wider devices must share a gain; limiting each buffer
/// independently moves the stereo image. The delay line is allocated with the engine, never in
/// the realtime callback.
///
/// `@unchecked Sendable`: the instance is created before the IO proc starts and touched only by
/// the realtime thread afterwards, so it is never accessed from two threads at once.
nonisolated final class BoostLookaheadBufferListLimiter: @unchecked Sendable {
    private let channelCapacity: Int
    private var delay: ContiguousArray<Float>
    private var position = 0
    private var filledFrames = 0
    private var activeChannels = 0
    private var gain: Float = 1
    private var targetGain: Float = 1
    private var attackFrames = 0
    private var attackStep: Float = 0
    private var holdFrames = 0

    init(channelCapacity: Int) {
        self.channelCapacity = max(1, channelCapacity)
        delay = ContiguousArray(
            repeating: 0,
            count: BoostLimiter.lookaheadFrames * self.channelCapacity
        )
    }

    /// Limits the buffers in place. Returns `false` when the shape does not fit the delay line,
    /// so the caller can fall back to the zero-lookahead limiter.
    @discardableResult
    func process(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        release: Float
    ) -> Bool {
        let channels = buffers.reduce(0) { partial, buffer in
            partial + (buffer.mData == nil ? 0 : Int(buffer.mNumberChannels))
        }
        guard frames > 0, channels > 0, channels <= channelCapacity else { return false }
        if channels != activeChannels { reset(activeChannels: channels) }

        let ceiling = BoostLimiter.ceiling
        for frame in 0..<frames {
            var peak: Float = 0
            for buffer in buffers {
                let count = Int(buffer.mNumberChannels)
                guard count > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * count
                for channel in 0..<count {
                    peak = max(peak, abs(samples[base + channel]))
                }
            }

            let requiredGain = peak > ceiling ? ceiling / peak : 1
            let isOverCeiling = requiredGain < 1
            if requiredGain < targetGain {
                targetGain = requiredGain
                let nextStep = (targetGain - gain) / Float(BoostLimiter.lookaheadFrames)
                // Restarting the deadline cannot violate an earlier one: the faster ramp wins.
                attackStep = attackFrames > 0 ? min(attackStep, nextStep) : nextStep
                attackFrames = BoostLimiter.lookaheadFrames
            }
            if isOverCeiling { holdFrames = BoostLimiter.lookaheadFrames }

            if attackFrames > 0 {
                gain += attackStep
                attackFrames -= 1
                if gain <= targetGain {
                    gain = targetGain
                    attackFrames = 0
                }
            } else if isOverCeiling == false, holdFrames > 0 {
                holdFrames -= 1
            } else if isOverCeiling == false {
                gain = 1 + (gain - 1) * release
                targetGain = gain
            }

            emit(frame: frame, in: buffers)
        }
        return true
    }

    private func emit(frame: Int, in buffers: UnsafeMutableAudioBufferListPointer) {
        let delayedBase = position * channelCapacity
        var channelIndex = 0
        for buffer in buffers {
            let count = Int(buffer.mNumberChannels)
            guard count > 0,
                  let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let base = frame * count
            for channel in 0..<count {
                let delayed = filledFrames >= BoostLimiter.lookaheadFrames
                    ? delay[delayedBase + channelIndex]
                    : 0
                delay[delayedBase + channelIndex] = samples[base + channel]
                samples[base + channel] = delayed * gain
                channelIndex += 1
            }
        }
        position += 1
        if position == BoostLimiter.lookaheadFrames { position = 0 }
        if filledFrames < BoostLimiter.lookaheadFrames { filledFrames += 1 }
    }

    private func reset(activeChannels channels: Int) {
        delay.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress?.update(repeating: 0, count: buffer.count)
        }
        position = 0
        filledFrames = 0
        gain = 1
        targetGain = 1
        attackFrames = 0
        attackStep = 0
        holdFrames = 0
        activeChannels = channels
    }
}

/// Zero-lookahead fallback for an unexpected output shape. It still links every buffer, so the
/// whole callback shares one gain.
nonisolated struct BoostBufferListLimiter: Sendable {
    private var envelope: Float = 0

    mutating func process(
        _ buffers: UnsafeMutableAudioBufferListPointer,
        frames: Int,
        release: Float
    ) {
        guard frames > 0 else { return }
        for frame in 0..<frames {
            var peak: Float = 0
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * channels
                for channel in 0..<channels { peak = max(peak, abs(samples[base + channel])) }
            }
            // Instant attack, exponential decay toward the current level.
            envelope = peak > envelope ? peak : peak + (envelope - peak) * release
            guard envelope > BoostLimiter.ceiling else { continue }
            let gain = BoostLimiter.ceiling / envelope
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0,
                      let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let base = frame * channels
                for channel in 0..<channels { samples[base + channel] *= gain }
            }
        }
    }
}
