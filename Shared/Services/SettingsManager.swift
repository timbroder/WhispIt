import Foundation

struct SettingsManager {
    static let shared = SettingsManager()

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: WhispItConstants.appGroupID)) {
        self.defaults = defaults ?? .standard
    }

    enum Key: String {
        case silenceTimeoutSeconds
    }

    var silenceTimeoutSeconds: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.silenceTimeoutSeconds.rawValue)
            return stored == 0 ? 2.0 : stored
        }
        nonmutating set {
            defaults.set(newValue, forKey: Key.silenceTimeoutSeconds.rawValue)
        }
    }
}
