import Foundation

public struct PlaybackTracker: Sendable {
    private var lastPositiveTimes: [pid_t: TimeInterval] = [:]

    public init() {}

    public mutating func update(
        allowlistedPIDs: Set<pid_t>,
        observation: Set<pid_t>?,
        now: TimeInterval
    ) -> Set<pid_t> {
        // Removing a PID from the allowlist must clear it immediately.
        var updatedTimes = lastPositiveTimes.filter { allowlistedPIDs.contains($0.key) }

        // Distinguish IOPM query/bridge failure (unknown observation) from successful empty observation.
        if let observedPIDs = observation {
            for pid in observedPIDs {
                if allowlistedPIDs.contains(pid) {
                    updatedTimes[pid] = now
                }
            }
        }

        // Prune entries at the exact 2.0-second boundary.
        updatedTimes = updatedTimes.filter { now - $0.value < 2.0 }
        self.lastPositiveTimes = updatedTimes

        // Return the stored keys (the active playback PIDs).
        return Set(updatedTimes.keys)
    }
}
