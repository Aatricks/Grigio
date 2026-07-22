import CPrivateAPIs

public enum GlobalGrayscaleBackend {
    public static var isAvailable: Bool {
        GrayscaleGlobalAPIAvailable()
    }

    public static var isGrayscaleEnabled: Bool {
        GrayscaleUsesForceToGray()
    }

    @discardableResult
    public static func setGrayscale(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        GrayscaleForceToGray(enabled)
        return isGrayscaleEnabled == enabled
    }

    public static func installCleanupHandlers() {
        GrayscaleInstallCleanupHandlers()
    }
}
