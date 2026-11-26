import Foundation

/// A transport interval in the camera host clock. A nil source records silence.
struct CameraAudioSegment: Codable, Equatable {
    let hostStart: Double
    let hostEnd: Double
    let sourceKey: String?
    let sourceStart: Double
    let rate: Double
    let preservesPitch: Bool

    init(hostStart: Double, hostEnd: Double, sourceKey: String? = nil,
         sourceStart: Double = 0, rate: Double = 1, preservesPitch: Bool = true) {
        self.hostStart = hostStart
        self.hostEnd = hostEnd
        self.sourceKey = sourceKey
        self.sourceStart = sourceStart
        self.rate = rate
        self.preservesPitch = preservesPitch
    }

    private enum CodingKeys: String, CodingKey {
        case hostStart, hostEnd, sourceKey, sourceStart, rate, preservesPitch
    }

    init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        hostStart = try data.decode(Double.self, forKey: .hostStart)
        hostEnd = try data.decode(Double.self, forKey: .hostEnd)
        sourceKey = try data.decodeIfPresent(String.self, forKey: .sourceKey)
        sourceStart = try data.decode(Double.self, forKey: .sourceStart)
        rate = try data.decode(Double.self, forKey: .rate)
        // Takes recorded before pitch control always preserved pitch.
        preservesPitch = try data.decodeIfPresent(Bool.self, forKey: .preservesPitch) ?? true
    }
}

struct CameraExportError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum CameraTimeline {
    /// Clip to the actual movie frames, preserving pauses and buffering gaps.
    static func clip(_ segments: [CameraAudioSegment], videoStart: Double,
                     duration: Double) throws -> [CameraAudioSegment] {
        let end = videoStart + duration
        guard videoStart.isFinite, duration.isFinite, duration > 0, end.isFinite else {
            throw CameraExportError("The camera timing is unavailable. Your original video is kept.")
        }
        var result: [CameraAudioSegment] = []
        var cursor = videoStart
        for segment in segments.sorted(by: { $0.hostStart < $1.hostStart }) {
            guard segment.hostStart.isFinite, segment.hostEnd.isFinite,
                  segment.hostEnd >= segment.hostStart, segment.sourceStart.isFinite,
                  segment.sourceStart >= 0, segment.rate.isFinite,
                  segment.sourceKey == nil || (!segment.sourceKey!.isEmpty && (0.5...2).contains(segment.rate)) else {
                throw CameraExportError("The music timing could not be verified. Your original video is kept.")
            }
            let first = max(videoStart, segment.hostStart)
            let last = min(end, segment.hostEnd)
            guard last > first else { continue }
            guard first >= cursor - 0.001 else {
                throw CameraExportError("The music timeline overlaps. Your original video is kept for retry.")
            }
            let start = max(cursor, first)
            if start > cursor {
                result.append(CameraAudioSegment(hostStart: cursor, hostEnd: start))
            }
            guard last > start else { continue }
            let rate = segment.sourceKey == nil ? 1 : segment.rate
            let sourceStart = segment.sourceKey == nil ? 0 :
                segment.sourceStart + (start - segment.hostStart) * rate
            result.append(CameraAudioSegment(hostStart: start, hostEnd: last,
                                             sourceKey: segment.sourceKey, sourceStart: sourceStart, rate: rate,
                                             preservesPitch: segment.preservesPitch))
            cursor = last
        }
        if cursor < end { result.append(CameraAudioSegment(hostStart: cursor, hostEnd: end)) }
        return result
    }

    static func duration(_ segments: [CameraAudioSegment], restoreTempo: Bool) -> Double {
        segments.reduce(0) { total, segment in
            total + (segment.hostEnd - segment.hostStart) *
                (restoreTempo && segment.sourceKey != nil ? segment.rate : 1)
        }
    }
}
