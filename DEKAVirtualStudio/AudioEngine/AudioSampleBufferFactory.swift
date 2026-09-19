//
//  AudioSampleBufferFactory.swift
//  AudioChunk (Int16 interleaved) → CMSampleBuffer for AVAssetWriter.
//

import CoreMedia
import AudioToolbox

enum AudioSampleBufferFactory {

    private static var formatCache: [String: CMAudioFormatDescription] = [:]
    private static let lock = Locked(0)

    static func formatDescription(sampleRate: Double, channels: Int) -> CMAudioFormatDescription? {
        let key = "\(sampleRate)-\(channels)"
        return lock.mutate { (_: inout Int) -> CMAudioFormatDescription? in
            if let f = formatCache[key] { return f }
            var asbd = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
                mBytesPerPacket: UInt32(2 * channels),
                mFramesPerPacket: 1,
                mBytesPerFrame: UInt32(2 * channels),
                mChannelsPerFrame: UInt32(channels),
                mBitsPerChannel: 16,
                mReserved: 0)
            var fmt: CMAudioFormatDescription?
            let status = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                                                        layoutSize: 0, layout: nil,
                                                        magicCookieSize: 0, magicCookie: nil,
                                                        extensions: nil, formatDescriptionOut: &fmt)
            guard status == noErr, let fmt else { return nil }
            formatCache[key] = fmt
            return fmt
        }
    }

    static func makeSampleBuffer(_ chunk: AudioChunk) -> CMSampleBuffer? {
        guard let fmt = formatDescription(sampleRate: chunk.sampleRate, channels: chunk.channels) else { return nil }
        let length = chunk.samples.count * MemoryLayout<Int16>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: length, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: length,
                                                 flags: kCMBlockBufferAssureMemoryNowFlag,
                                                 blockBufferOut: &block) == kCMBlockBufferNoErr,
              let block else { return nil }
        let copied = chunk.samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: length)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        var sb: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: fmt,
            sampleCount: chunk.frameCount, presentationTimeStamp: chunk.presentationTime,
            packetDescriptions: nil, sampleBufferOut: &sb)
        return status == noErr ? sb : nil
    }
}
