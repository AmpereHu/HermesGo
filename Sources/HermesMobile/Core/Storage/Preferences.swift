import Foundation

public final class Preferences: @unchecked Sendable {
    public static let shared = Preferences()

    private enum Keys {
        static let serverURL = "hermesmobile.serverURL"
        static let lastSessionId = "hermesmobile.lastSessionId"
        static let lastStreamId = "hermesmobile.lastStreamId"
        static let lastBackgroundDate = "hermesmobile.lastBackgroundDate"
        static let preferredModel = "hermesmobile.preferredModel"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var serverURL: URL? {
        get {
            guard let raw = defaults.string(forKey: Keys.serverURL) else { return nil }
            return URL(string: raw)
        }
        set {
            if let url = newValue {
                defaults.set(url.absoluteString, forKey: Keys.serverURL)
            } else {
                defaults.removeObject(forKey: Keys.serverURL)
            }
        }
    }

    public var lastSessionId: String? {
        get { defaults.string(forKey: Keys.lastSessionId) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: Keys.lastSessionId)
            } else {
                defaults.removeObject(forKey: Keys.lastSessionId)
            }
        }
    }

    public var lastStreamId: String? {
        get { defaults.string(forKey: Keys.lastStreamId) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: Keys.lastStreamId)
            } else {
                defaults.removeObject(forKey: Keys.lastStreamId)
            }
        }
    }

    public var lastBackgroundDate: Date? {
        get {
            let timestamp = defaults.double(forKey: Keys.lastBackgroundDate)
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            if let date = newValue {
                defaults.set(date.timeIntervalSince1970, forKey: Keys.lastBackgroundDate)
            } else {
                defaults.removeObject(forKey: Keys.lastBackgroundDate)
            }
        }
    }

    public var preferredModel: String? {
        get { defaults.string(forKey: Keys.preferredModel) }
        set {
            if let value = newValue {
                defaults.set(value, forKey: Keys.preferredModel)
            } else {
                defaults.removeObject(forKey: Keys.preferredModel)
            }
        }
    }

    public func reset() {
        for key in [
            Keys.serverURL,
            Keys.lastSessionId,
            Keys.lastStreamId,
            Keys.lastBackgroundDate,
            Keys.preferredModel
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
