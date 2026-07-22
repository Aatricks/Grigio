import Foundation

public final class AllowlistStore {
    public static let defaultRules: [AppRule] = [
        AppRule(identifier: "com.colliderli.iina", displayName: "IINA", isBrowser: false, defaultEnabled: true),
        AppRule(identifier: "io.mpv", displayName: "mpv", isBrowser: false, defaultEnabled: true),
        AppRule(identifier: "org.videolan.vlc", displayName: "VLC", isBrowser: false, defaultEnabled: true),
        AppRule(identifier: "com.apple.QuickTimePlayerX", displayName: "QuickTime Player", isBrowser: false, defaultEnabled: true),
        AppRule(identifier: "com.apple.Safari", displayName: "Safari", isBrowser: true, defaultEnabled: false),
        AppRule(identifier: "com.google.Chrome", displayName: "Google Chrome", isBrowser: true, defaultEnabled: false),
        AppRule(identifier: "org.mozilla.firefox", displayName: "Firefox", isBrowser: true, defaultEnabled: false),
        AppRule(identifier: "com.microsoft.edgemac", displayName: "Microsoft Edge", isBrowser: true, defaultEnabled: false),
    ]

    private let defaults: UserDefaults
    private let enabledPrefix = "allowlist.enabled."
    private let namesKey = "allowlist.names"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isEnabled(identifier: String) -> Bool {
        let key = enabledPrefix + identifier
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        return Self.defaultRules.first(where: { $0.identifier == identifier })?.defaultEnabled ?? false
    }

    public func setEnabled(_ enabled: Bool, identifier: String, displayName: String) {
        defaults.set(enabled, forKey: enabledPrefix + identifier)
        var names = defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        names[identifier] = displayName
        defaults.set(names, forKey: namesKey)
    }

    public func rules() -> [AppRule] {
        var byIdentifier = Dictionary(uniqueKeysWithValues: Self.defaultRules.map { ($0.identifier, $0) })
        let names = defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        for (identifier, displayName) in names where byIdentifier[identifier] == nil {
            byIdentifier[identifier] = AppRule(
                identifier: identifier,
                displayName: displayName,
                isBrowser: false,
                defaultEnabled: false
            )
        }
        return byIdentifier.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func enabledIdentifiers() -> Set<String> {
        Set(rules().lazy.filter { self.isEnabled(identifier: $0.identifier) }.map(\.identifier))
    }
}
