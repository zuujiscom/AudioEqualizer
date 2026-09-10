import Foundation
import Combine

/// Per-output-device EQ profiles, persisted next to the custom presets.
///
/// A profile is captured automatically as the EQ is adjusted and re-applied
/// when that device becomes the system output again, so a curve dialled in for
/// headphones does not follow you to the TV.
@MainActor
final class DeviceProfileStore: ObservableObject {
    @Published private(set) var profiles: [String: DeviceProfile] = [:]

    /// Off means profiles are neither captured nor applied; whatever is on the
    /// sliders stays put across device changes.
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private static let enabledKey = "deviceProfilesEnabled"
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("AudioEqualizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        storageURL = appDir.appendingPathComponent("deviceProfiles.json")

        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            isEnabled = true
        } else {
            isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        load()
    }

    var sortedProfiles: [DeviceProfile] {
        profiles.values.sorted { $0.deviceName.localizedCaseInsensitiveCompare($1.deviceName) == .orderedAscending }
    }

    func profile(forUID uid: String) -> DeviceProfile? { profiles[uid] }

    func save(_ profile: DeviceProfile) {
        profiles[profile.deviceUID] = profile
        persist()
    }

    func remove(uid: String) {
        profiles.removeValue(forKey: uid)
        persist()
    }

    func removeAll() {
        profiles.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([DeviceProfile].self, from: data) else { return }
        profiles = Dictionary(uniqueKeysWithValues: decoded.map { ($0.deviceUID, $0) })
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sortedProfiles) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
