import CoreMedia

struct CameraClockPoint {
    let host: Double
    let position: Double
    let rate: Double
    let changedAt: Double
}

enum CameraPlaybackClock {
    /// Read the rate and matching anchors atomically, including parent timebases.
    /// Player items can inherit their speed from a parent timebase.
    static func read(_ timebase: CMTimebase) -> CameraClockPoint? {
        let clock = CMClockGetHostTimeClock()
        var rate = 0.0
        var mediaAnchor = CMTime.invalid
        var hostAnchor = CMTime.invalid
        guard CMSyncGetRelativeRateAndAnchorTime(timebase, relativeTo: clock,
            relativeRateOut: &rate, anchorTimeOut: &mediaAnchor,
            relativeToAnchorTimeOut: &hostAnchor) == noErr else { return nil }
        let host = CMClockGetTime(clock).seconds
        let changed = hostAnchor.seconds
        let position = mediaAnchor.seconds + (host - changed) * rate
        guard host.isFinite, changed.isFinite, position.isFinite, rate.isFinite else { return nil }
        return CameraClockPoint(host: host, position: max(0, position), rate: rate, changedAt: changed)
    }
}
