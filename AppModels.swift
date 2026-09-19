import Foundation

enum AppearanceMode: String, Codable, CaseIterable, Sendable {
  case light
  case dark

  var systemImage: String { self == .light ? "sun.max" : "moon" }
}

extension CodingUserInfoKey {
  static let fallbackAppearance = CodingUserInfoKey(rawValue: "tesviye.fallbackAppearance")!
}

enum OutputFormat: String, Codable, CaseIterable, Sendable {
  case jpeg
  case png
  case webP

  nonisolated var fileExtension: String {
    switch self {
    case .jpeg:
      return "jpg"
    case .png:
      return "png"
    case .webP:
      return "webp"
    }
  }

  nonisolated var typeIdentifier: String {
    switch self {
    case .jpeg:
      return "public.jpeg"
    case .png:
      return "public.png"
    case .webP:
      return "org.webmproject.webp"
    }
  }

  var displayName: String {
    switch self {
    case .jpeg:
      return "JPEG"
    case .png:
      return "PNG"
    case .webP:
      return "WebP"
    }
  }

  var supportsQualityAdjustment: Bool {
    self != .png
  }
}

enum QualityMode: String, Codable, CaseIterable, Sendable {
  case automatic
  case manual
}

enum ResizePreset: String, Codable, CaseIterable, Identifiable, Sendable {
  case original
  case fullHD
  case hd
  case square
  case social
  case small
  case custom

  var id: String { rawValue }

  var dimensions: (width: Int, height: Int)? {
    switch self {
    case .fullHD:
      return (1920, 1080)
    case .hd:
      return (1280, 720)
    case .square:
      return (1080, 1080)
    case .social:
      return (1200, 630)
    case .small:
      return (800, 800)
    case .original, .custom:
      return nil
    }
  }

  static var visiblePresets: [ResizePreset] {
    [.original, .fullHD, .hd, .square, .social, .small, .custom]
  }
}

struct RGBColor: Codable, Equatable, Sendable {
  static let white = RGBColor(red: 1, green: 1, blue: 1)

  var red: Double
  var green: Double
  var blue: Double

  mutating func normalize() {
    red = min(max(red, 0), 1)
    green = min(max(green, 0), 1)
    blue = min(max(blue, 0), 1)
  }

  var hexString: String {
    let redValue = Int((red * 255).rounded())
    let greenValue = Int((green * 255).rounded())
    let blueValue = Int((blue * 255).rounded())
    return String(format: "#%02X%02X%02X", redValue, greenValue, blueValue)
  }
}

struct OutputDirectoryPreference: Codable, Equatable, Sendable {
  let path: String
  let bookmarkData: Data?

  init(url: URL) {
    let standardizedURL = url.standardizedFileURL
    path = standardizedURL.path
    bookmarkData = try? standardizedURL.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  init(path: String, bookmarkData: Data? = nil) {
    self.path = path
    self.bookmarkData = bookmarkData
  }

  nonisolated var resolvedURL: URL {
    if let bookmarkData {
      var isStale = false
      if let bookmarkedURL = try? URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) {
        return bookmarkedURL.standardizedFileURL
      }
    }

    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
  }
}

struct UserPreferences: Codable, Equatable, Sendable {
  static let currentSchemaVersion = 7

  private static let legacyDefaultFilenameSuffixes = [
    "-yeniden-boyutlandirildi",
    "-resized",
  ]

  var appearanceMode: AppearanceMode = .light
  var selectedPreset: ResizePreset = .fullHD
  var width = 1920
  var height = 1080
  var preservesAspectRatio = true
  var allowsUpscaling = false
  var overwritesOriginal = false
  var outputFormat: OutputFormat = .jpeg
  var qualityMode: QualityMode = .automatic
  var quality = 0.85
  var filenameSuffix = "_1920x1080"
  var usesFilenameSuffix = true
  var outputDirectory: OutputDirectoryPreference?
  var preservesMetadata = true
  var removesLocationMetadata = true
  var jpegBackgroundColor = RGBColor.white

  private enum CodingKeys: String, CodingKey {
    case appearanceMode
    case selectedPreset
    case width
    case height
    case preservesAspectRatio
    case allowsUpscaling
    case overwritesOriginal
    case outputFormat
    case qualityMode
    case quality
    case filenameSuffix
    case usesFilenameSuffix
    case outputDirectory
    case preservesMetadata
    case removesLocationMetadata
    case jpegBackgroundColor
  }

  init(appearanceMode: AppearanceMode = .light) {
    self.appearanceMode = appearanceMode
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let storedAppearance = try container.decodeIfPresent(String.self, forKey: .appearanceMode)
    appearanceMode =
      storedAppearance.flatMap(AppearanceMode.init(rawValue:))
      ?? decoder.userInfo[.fallbackAppearance] as? AppearanceMode ?? .light
    selectedPreset =
      try container.decodeIfPresent(
        ResizePreset.self,
        forKey: .selectedPreset
      ) ?? .fullHD
    width = try container.decodeIfPresent(Int.self, forKey: .width) ?? 1920
    height = try container.decodeIfPresent(Int.self, forKey: .height) ?? 1080
    preservesAspectRatio =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .preservesAspectRatio
      ) ?? true
    allowsUpscaling =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .allowsUpscaling
      ) ?? false
    overwritesOriginal =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .overwritesOriginal
      ) ?? false
    outputFormat =
      try container.decodeIfPresent(
        OutputFormat.self,
        forKey: .outputFormat
      ) ?? .jpeg
    qualityMode =
      try container.decodeIfPresent(
        QualityMode.self,
        forKey: .qualityMode
      ) ?? .automatic
    quality = try container.decodeIfPresent(Double.self, forKey: .quality) ?? 0.85
    filenameSuffix =
      try container.decodeIfPresent(
        String.self,
        forKey: .filenameSuffix
      ) ?? Self.dimensionFilenameSuffix(width: width, height: height)
    usesFilenameSuffix =
      try container.decodeIfPresent(Bool.self, forKey: .usesFilenameSuffix) ?? true
    outputDirectory = try container.decodeIfPresent(
      OutputDirectoryPreference.self,
      forKey: .outputDirectory
    )
    preservesMetadata =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .preservesMetadata
      ) ?? true
    removesLocationMetadata =
      try container.decodeIfPresent(
        Bool.self,
        forKey: .removesLocationMetadata
      ) ?? true
    jpegBackgroundColor =
      try container.decodeIfPresent(
        RGBColor.self,
        forKey: .jpegBackgroundColor
      ) ?? .white
  }

  mutating func selectPreset(_ preset: ResizePreset) {
    let updatesAutomaticSuffix = isUsingAutomaticDimensionFilenameSuffix
    guard let dimensions = preset.dimensions else {
      selectedPreset = preset
      if updatesAutomaticSuffix { filenameSuffix = dimensionFilenameSuffix }
      return
    }

    selectedPreset = preset
    width = dimensions.width
    height = dimensions.height
    if updatesAutomaticSuffix {
      filenameSuffix = dimensionFilenameSuffix
    }
  }

  mutating func swapDimensions() {
    let updatesAutomaticSuffix = isUsingAutomaticDimensionFilenameSuffix
    (width, height) = (height, width)
    selectedPreset = .custom
    if updatesAutomaticSuffix {
      filenameSuffix = dimensionFilenameSuffix
    }
  }

  mutating func updateWidth(_ value: Int) {
    let updatesAutomaticSuffix = isUsingAutomaticDimensionFilenameSuffix
    width = value
    selectedPreset = .custom
    if updatesAutomaticSuffix {
      filenameSuffix = dimensionFilenameSuffix
    }
  }

  mutating func updateHeight(_ value: Int) {
    let updatesAutomaticSuffix = isUsingAutomaticDimensionFilenameSuffix
    height = value
    selectedPreset = .custom
    if updatesAutomaticSuffix {
      filenameSuffix = dimensionFilenameSuffix
    }
  }

  mutating func toggleQualityMode() {
    qualityMode = qualityMode == .automatic ? .manual : .automatic
  }

  mutating func selectOutputDirectory(_ url: URL) {
    outputDirectory = OutputDirectoryPreference(url: url)
    overwritesOriginal = false
  }

  mutating func resetOutputDirectory() {
    outputDirectory = nil
  }

  mutating func updatePresetSelection() {
    selectedPreset =
      ResizePreset.visiblePresets.first {
        $0.dimensions?.width == width && $0.dimensions?.height == height
      } ?? .custom
  }

  mutating func normalize() {
    width = min(max(width, 1), 100_000)
    height = min(max(height, 1), 100_000)
    quality = min(max(quality, 0.01), 1)

    let trimmedSuffix = filenameSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
    filenameSuffix = trimmedSuffix.isEmpty ? dimensionFilenameSuffix : trimmedSuffix
    if let outputDirectory {
      let trimmedPath = outputDirectory.path.trimmingCharacters(in: .whitespacesAndNewlines)
      self.outputDirectory = trimmedPath.isEmpty ? nil : outputDirectory
      if self.outputDirectory != nil {
        overwritesOriginal = false
      }
    }
    jpegBackgroundColor.normalize()
    if selectedPreset != .original && selectedPreset != .custom { updatePresetSelection() }
  }

  mutating func migrateFilenameSuffixIfNeeded(from schemaVersion: Int) {
    guard
      schemaVersion < 5,
      Self.legacyDefaultFilenameSuffixes.contains(filenameSuffix)
    else {
      return
    }
    filenameSuffix = dimensionFilenameSuffix
  }

  var dimensionFilenameSuffix: String {
    selectedPreset == .original
      ? "_original" : Self.dimensionFilenameSuffix(width: width, height: height)
  }

  var effectiveFilenameSuffix: String {
    guard usesFilenameSuffix else { return "" }
    let trimmedSuffix = filenameSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedSuffix.isEmpty ? dimensionFilenameSuffix : trimmedSuffix
  }

  private var isUsingAutomaticDimensionFilenameSuffix: Bool {
    filenameSuffix == dimensionFilenameSuffix
      || Self.legacyDefaultFilenameSuffixes.contains(filenameSuffix)
  }

  private static func dimensionFilenameSuffix(width: Int, height: Int) -> String {
    "_\(width)x\(height)"
  }

  var isManualQualityControlEnabled: Bool {
    outputFormat.supportsQualityAdjustment && qualityMode == .manual
  }
}

struct StoredPreferences: Codable, Sendable {
  let schemaVersion: Int
  let preferences: UserPreferences
}

struct SelectedImage: Identifiable, Hashable, Sendable {
  let url: URL
  let byteCount: Int64

  var id: URL { url }
}

struct ResizeConfiguration: Sendable {
  let preservesOriginalSize: Bool
  let width: Int
  let height: Int
  let preservesAspectRatio: Bool
  let allowsUpscaling: Bool
  let overwritesOriginal: Bool
  let outputFormat: OutputFormat
  let qualityMode: QualityMode
  let quality: Double
  let filenameSuffix: String
  let outputDirectory: OutputDirectoryPreference?
  let preservesMetadata: Bool
  let removesLocationMetadata: Bool
  let jpegBackgroundColor: RGBColor

  init(preferences: UserPreferences) {
    preservesOriginalSize = preferences.selectedPreset == .original
    width = preferences.width
    height = preferences.height
    preservesAspectRatio = preferences.preservesAspectRatio
    allowsUpscaling = preferences.allowsUpscaling
    overwritesOriginal = preferences.overwritesOriginal && preferences.outputDirectory == nil
    outputFormat = preferences.outputFormat
    qualityMode = preferences.qualityMode
    quality = preferences.quality
    filenameSuffix = preferences.effectiveFilenameSuffix
    outputDirectory = preferences.outputDirectory
    preservesMetadata = preferences.preservesMetadata
    removesLocationMetadata = preferences.removesLocationMetadata
    jpegBackgroundColor = preferences.jpegBackgroundColor
  }
}

enum ResizeResultStatus: Equatable, Sendable {
  case success
  case failure
}

struct ResizeResult: Identifiable, Sendable {
  let id = UUID()
  let sourceURL: URL
  let outputURL: URL?
  let status: ResizeResultStatus
  let message: String?
}

enum BatchResultStatus: Equatable {
  case completed
  case completedWithErrors
  case failed
  case cancelled
}

struct BatchResultSummary {
  let successCount: Int
  let failureCount: Int
  let remainingCount: Int

  init(results: [ResizeResult], total: Int) {
    successCount = results.filter { $0.status == .success }.count
    failureCount = results.filter { $0.status == .failure }.count
    remainingCount = max(0, total - results.count)
  }

  var status: BatchResultStatus {
    if remainingCount > 0 { return .cancelled }
    if failureCount == 0 { return .completed }
    return successCount == 0 ? .failed : .completedWithErrors
  }
}

struct BatchProgress: Equatable, Sendable {
  var completed = 0
  var total = 0

  var fraction: Double {
    guard total > 0 else { return 0 }
    return Double(completed) / Double(total)
  }
}
