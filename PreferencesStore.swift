import Combine
import Foundation

@MainActor
final class PreferencesStore: ObservableObject {
  static let storageKey = "userPreferences"

  @Published var preferences: UserPreferences {
    didSet {
      scheduleSave()
    }
  }

  private let defaults: UserDefaults
  private var pendingSave: DispatchWorkItem?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    preferences = Self.load(from: defaults)
  }

  func flush() {
    pendingSave?.cancel()
    pendingSave = nil
    saveNow()
  }

  private func scheduleSave() {
    pendingSave?.cancel()

    let workItem = DispatchWorkItem { [weak self] in
      self?.saveNow()
    }
    pendingSave = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
  }

  private func saveNow() {
    var normalizedPreferences = preferences
    normalizedPreferences.normalize()

    let storedPreferences = StoredPreferences(
      schemaVersion: UserPreferences.currentSchemaVersion,
      preferences: normalizedPreferences
    )

    guard let data = try? JSONEncoder().encode(storedPreferences) else {
      return
    }

    defaults.set(data, forKey: Self.storageKey)
  }

  private static func load(from defaults: UserDefaults) -> UserPreferences {
    guard
      let data = defaults.data(forKey: storageKey),
      let storedPreferences = try? JSONDecoder().decode(StoredPreferences.self, from: data),
      storedPreferences.schemaVersion <= UserPreferences.currentSchemaVersion
    else {
      return UserPreferences()
    }

    var preferences = storedPreferences.preferences
    preferences.migrateFilenameSuffixIfNeeded(from: storedPreferences.schemaVersion)
    preferences.normalize()
    return preferences
  }
}
