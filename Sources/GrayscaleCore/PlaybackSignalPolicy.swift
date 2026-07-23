import Darwin

public enum PlaybackSignalPolicy {
    public static func mediaRemoteObservation(
        isPlaying: Bool?,
        clientBundleIdentifier: String?,
        parentApplicationBundleIdentifier: String?,
        allowlistedBundleMap: [pid_t: String]
    ) -> Set<pid_t>? {
        guard let isPlaying else { return nil }
        guard isPlaying else { return [] }

        var matchingPIDs = Set<pid_t>()
        if let parent = parentApplicationBundleIdentifier {
            for (pid, bundleID) in allowlistedBundleMap where bundleID == parent {
                matchingPIDs.insert(pid)
            }
        }
        if matchingPIDs.isEmpty, let client = clientBundleIdentifier {
            for (pid, bundleID) in allowlistedBundleMap where bundleID == client {
                matchingPIDs.insert(pid)
            }
        }
        return matchingPIDs
    }

    public static func combine(
        powerAssertions: Set<pid_t>?,
        mediaRemote: Set<pid_t>?
    ) -> Set<pid_t>? {
        if powerAssertions == nil && mediaRemote == nil {
            return nil
        }
        return (powerAssertions ?? []).union(mediaRemote ?? [])
    }
}
