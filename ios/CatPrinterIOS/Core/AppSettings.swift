import Foundation

final class AppSettings {
    private let defaultsKey = "catprinter.settings.v1"
    private(set) var values: [String: Any]

    init() {
        let base: [String: Any] = [
            "version": 4,
            "first_run": true,
            "is_android": false,
            "scan_time": 1.0,
            "dry_run": false,
            "energy": 64,
            "quality": 36,
            "flip": false,
            "flip_h": false,
            "flip_v": false,
            "force_rtl": false,
            "no_animation": false,
            "large_font": false,
            "dark_theme": false,
            "high_contrast": false,
            "mono_algorithm": "algo-random-threshold",
            "text_mode": false,
            "language": "en-US"
        ]
        let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
        self.values = base.merging(stored) { _, new in new }
    }

    func update(with payload: [String: Any]) {
        for (key, value) in payload {
            switch value {
            case is NSNumber, is String, is Bool, is Double, is Int:
                values[key] = value
            default:
                continue
            }
        }
        UserDefaults.standard.set(values, forKey: defaultsKey)
    }

    func asJSONData() throws -> Data {
        try JSONSerialization.data(withJSONObject: values, options: [])
    }
}
