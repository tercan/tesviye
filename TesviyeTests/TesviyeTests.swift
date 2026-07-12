import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import tesviye

@MainActor
final class TesviyeTests: XCTestCase {
  func testNativeImageOpenPanelSupportsMultipleImageSelection() {
    let panel = NativeOpenPanelFactory.makeImagePanel()

    XCTAssertTrue(panel.canChooseFiles)
    XCTAssertFalse(panel.canChooseDirectories)
    XCTAssertTrue(panel.allowsMultipleSelection)
    XCTAssertTrue(panel.resolvesAliases)
    XCTAssertEqual(panel.allowedContentTypes, [.image])
  }

  func testNativeOutputDirectoryPanelSelectsOneFolder() {
    let initialDirectory = FileManager.default.temporaryDirectory
    let panel = NativeOpenPanelFactory.makeOutputDirectoryPanel(
      initialDirectory: initialDirectory
    )

    XCTAssertFalse(panel.canChooseFiles)
    XCTAssertTrue(panel.canChooseDirectories)
    XCTAssertTrue(panel.canCreateDirectories)
    XCTAssertFalse(panel.allowsMultipleSelection)
    XCTAssertEqual(panel.directoryURL, initialDirectory)
  }

  func testRadiuslessWindowConfigurationRemovesNativeFrameAndContentRounding() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 740, height: 688),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )

    RadiuslessWindowConfiguration.apply(to: window)

    XCTAssertEqual(window.identifier, RadiuslessWindowConfiguration.identifier)
    XCTAssertFalse(window.styleMask.contains(.titled))
    XCTAssertFalse(window.styleMask.contains(.resizable))
    XCTAssertTrue(window.styleMask.contains(.closable))
    XCTAssertTrue(window.styleMask.contains(.miniaturizable))
    XCTAssertTrue(window.isMovableByWindowBackground)
    XCTAssertTrue(window.hasShadow)
    XCTAssertEqual(window.contentView?.layer?.cornerRadius, 0)
    XCTAssertEqual(window.contentView?.layer?.masksToBounds, true)
  }

  func testAppearanceCycleReturnsToSystem() {
    XCTAssertEqual(AppearanceMode.system.next, .light)
    XCTAssertEqual(AppearanceMode.light.next, .dark)
    XCTAssertEqual(AppearanceMode.dark.next, .system)
  }

  func testColorPanelPositionsBesideColorWellWhenSpaceIsAvailable() {
    let origin = ColorPanelPositioning.origin(
      anchorFrame: CGRect(x: 100, y: 400, width: 20, height: 20),
      panelSize: CGSize(width: 240, height: 300),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
      trailingClearance: 70
    )

    XCTAssertEqual(origin.x, 198)
    XCTAssertEqual(origin.y, 120)
  }

  func testColorPanelMovesLeftAndStaysOnScreenWhenRightSideIsUnavailable() {
    let origin = ColorPanelPositioning.origin(
      anchorFrame: CGRect(x: 950, y: 10, width: 30, height: 20),
      panelSize: CGSize(width: 240, height: 300),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
      trailingClearance: 70
    )

    XCTAssertEqual(origin.x, 702)
    XCTAssertEqual(origin.y, 0)
  }

  func testExternalImageOpenCoordinatorDeduplicatesAndDrainsURLs() {
    let coordinator = ExternalImageOpenCoordinator()
    let firstURL = URL(fileURLWithPath: "/tmp/first.jpg")
    let secondURL = URL(fileURLWithPath: "/tmp/second.png")

    let importURL = try! XCTUnwrap(
      FinderImportPayload.makeURL(for: [firstURL, firstURL, secondURL])
    )

    coordinator.handleExternalOpen([importURL])

    XCTAssertEqual(coordinator.pendingURLs, [firstURL, secondURL])
    XCTAssertEqual(coordinator.drainPendingURLs(), [firstURL, secondURL])
    XCTAssertTrue(coordinator.pendingURLs.isEmpty)
  }

  func testApplicationDeclaresImageDocumentSupport() {
    let documentTypes =
      Bundle.main
      .object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]]
    let declaredContentTypes = documentTypes?
      .compactMap { $0["LSItemContentTypes"] as? [String] }
      .flatMap { $0 }

    XCTAssertTrue(declaredContentTypes?.contains("public.image") == true)

    let urlTypes =
      Bundle.main
      .object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
    let declaredSchemes = urlTypes?
      .compactMap { $0["CFBundleURLSchemes"] as? [String] }
      .flatMap { $0 }

    XCTAssertTrue(declaredSchemes?.contains(FinderImportPayload.scheme) == true)
  }

  func testApplicationPackagesConfiguredAppIcon() {
    XCTAssertEqual(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
      "Tesviye"
    )
    XCTAssertEqual(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
      "Tesviye"
    )
    XCTAssertEqual(
      Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
      "AppIcon"
    )
    XCTAssertNotNil(Bundle.main.url(forResource: "AppIcon", withExtension: "icns"))
  }

  func testFinderActionPackagesBrandedTemplateIcon() throws {
    let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
    let extensionURL = plugInsURL.appendingPathComponent("TesviyeFinderAction.appex")
    let extensionBundle = try XCTUnwrap(Bundle(url: extensionURL))
    let extensionConfiguration = try XCTUnwrap(
      extensionBundle.object(forInfoDictionaryKey: "NSExtension") as? [String: Any]
    )
    let attributes = try XCTUnwrap(
      extensionConfiguration["NSExtensionAttributes"] as? [String: Any]
    )

    XCTAssertEqual(
      attributes["NSExtensionServiceFinderPreviewIconName"] as? String,
      "ResizeActionIconTemplate"
    )
    XCTAssertNotNil(extensionBundle.url(forResource: "Assets", withExtension: "car"))
  }

  func testFinderImportPayloadRejectsUnrelatedURLs() {
    XCTAssertNil(FinderImportPayload.fileURLs(from: URL(string: "https://example.com")!))
    XCTAssertNil(FinderImportPayload.makeURL(for: []))
  }

  func testExternalOpenAddsSupportedImagesAndDismissesTransientModals() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let imageURL = directory.appendingPathComponent("external.png")
    let textURL = directory.appendingPathComponent("unsupported.txt")
    try createPNG(at: imageURL, width: 20, height: 10)
    try Data("not an image".utf8).write(to: textURL)

    let viewModel = MainViewModel()
    viewModel.isShowingResults = true
    viewModel.isShowingSelectionList = true

    let secondImageURL = directory.appendingPathComponent("second.jpg")
    try createPNG(at: secondImageURL, width: 10, height: 20)
    let importURL = try XCTUnwrap(
      FinderImportPayload.makeURL(for: [imageURL, secondImageURL, imageURL, textURL])
    )
    let importedURLs = try XCTUnwrap(FinderImportPayload.fileURLs(from: importURL))

    viewModel.addImagesFromExternalOpen(importedURLs)

    XCTAssertEqual(viewModel.selectedImages.map(\.url), [imageURL, secondImageURL])
    XCTAssertFalse(viewModel.isShowingResults)
    XCTAssertFalse(viewModel.isShowingSelectionList)
  }

  func testDefaultPreferencesUseSafeValues() {
    let preferences = UserPreferences()

    XCTAssertEqual(preferences.appearanceMode, .system)
    XCTAssertEqual(preferences.selectedPreset, .fullHD)
    XCTAssertEqual(preferences.width, 1920)
    XCTAssertEqual(preferences.height, 1080)
    XCTAssertTrue(preferences.preservesAspectRatio)
    XCTAssertFalse(preferences.allowsUpscaling)
    XCTAssertFalse(preferences.overwritesOriginal)
    XCTAssertEqual(preferences.outputFormat, .jpeg)
    XCTAssertEqual(preferences.qualityMode, .automatic)
    XCTAssertEqual(preferences.quality, 0.85)
    XCTAssertEqual(preferences.filenameSuffix, "_1920x1080")
    XCTAssertNil(preferences.outputDirectory)
    XCTAssertEqual(preferences.jpegBackgroundColor, .white)
  }

  func testSelectingCustomOutputDirectoryDisablesOverwriteAndCanReset() throws {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputURL,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: outputURL) }

    var preferences = UserPreferences()
    preferences.overwritesOriginal = true

    preferences.selectOutputDirectory(outputURL)

    XCTAssertEqual(preferences.outputDirectory?.path, outputURL.path)
    XCTAssertNotNil(preferences.outputDirectory?.bookmarkData)
    XCTAssertEqual(preferences.outputDirectory?.resolvedURL, outputURL.standardizedFileURL)
    XCTAssertFalse(preferences.overwritesOriginal)
    XCTAssertFalse(ResizeConfiguration(preferences: preferences).overwritesOriginal)

    preferences.resetOutputDirectory()
    XCTAssertNil(preferences.outputDirectory)
  }

  func testPresetAndDimensionSwapStaySynchronized() {
    var preferences = UserPreferences()
    preferences.selectPreset(.social)

    XCTAssertEqual(preferences.width, 1200)
    XCTAssertEqual(preferences.height, 630)
    XCTAssertEqual(preferences.selectedPreset, .social)
    XCTAssertEqual(preferences.filenameSuffix, "_1200x630")

    preferences.swapDimensions()

    XCTAssertEqual(preferences.width, 630)
    XCTAssertEqual(preferences.height, 1200)
    XCTAssertEqual(preferences.selectedPreset, .custom)
    XCTAssertEqual(preferences.filenameSuffix, "_630x1200")

    preferences.filenameSuffix = "_web"
    preferences.selectPreset(.hd)
    XCTAssertEqual(preferences.filenameSuffix, "_web")
  }

  func testManualQualityControlStateFollowsFormatAndMode() {
    var preferences = UserPreferences()

    XCTAssertFalse(preferences.isManualQualityControlEnabled)

    preferences.toggleQualityMode()
    XCTAssertEqual(preferences.qualityMode, .manual)
    XCTAssertTrue(preferences.isManualQualityControlEnabled)

    preferences.outputFormat = .webP
    XCTAssertTrue(preferences.isManualQualityControlEnabled)

    preferences.outputFormat = .png
    XCTAssertFalse(preferences.isManualQualityControlEnabled)

    preferences.toggleQualityMode()
    XCTAssertEqual(preferences.qualityMode, .automatic)
  }

  func testPreferencesPersistAndReload() {
    let suiteName = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = PreferencesStore(defaults: defaults)
    store.preferences.appearanceMode = .dark
    store.preferences.width = 800
    store.preferences.height = 600
    store.preferences.outputFormat = .png
    store.preferences.qualityMode = .manual
    store.preferences.filenameSuffix = "_social"
    store.preferences.outputDirectory = OutputDirectoryPreference(
      path: "/tmp/tesviye-persisted-output"
    )
    store.preferences.jpegBackgroundColor = RGBColor(red: 0.8, green: 0.2, blue: 0.1)
    store.flush()

    let reloadedStore = PreferencesStore(defaults: defaults)
    XCTAssertEqual(reloadedStore.preferences.appearanceMode, .dark)
    XCTAssertEqual(reloadedStore.preferences.width, 800)
    XCTAssertEqual(reloadedStore.preferences.height, 600)
    XCTAssertEqual(reloadedStore.preferences.outputFormat, .png)
    XCTAssertEqual(reloadedStore.preferences.qualityMode, .manual)
    XCTAssertEqual(reloadedStore.preferences.filenameSuffix, "_social")
    XCTAssertEqual(
      reloadedStore.preferences.outputDirectory?.path,
      "/tmp/tesviye-persisted-output"
    )
    XCTAssertEqual(
      reloadedStore.preferences.jpegBackgroundColor,
      RGBColor(red: 0.8, green: 0.2, blue: 0.1)
    )
  }

  func testLegacyPreferencesWithoutQualityModeMigrateToAutomatic() throws {
    let suiteName = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    var preferences = UserPreferences()
    preferences.width = 640
    preferences.qualityMode = .manual
    preferences.quality = 0.42
    preferences.filenameSuffix = "-yeniden-boyutlandirildi"
    let currentData = try JSONEncoder().encode(
      StoredPreferences(schemaVersion: 1, preferences: preferences)
    )
    var legacyRoot = try XCTUnwrap(
      JSONSerialization.jsonObject(with: currentData) as? [String: Any]
    )
    var legacyPreferences = try XCTUnwrap(
      legacyRoot["preferences"] as? [String: Any]
    )
    legacyPreferences.removeValue(forKey: "qualityMode")
    legacyRoot["preferences"] = legacyPreferences
    defaults.set(
      try JSONSerialization.data(withJSONObject: legacyRoot),
      forKey: PreferencesStore.storageKey
    )

    let migratedStore = PreferencesStore(defaults: defaults)

    XCTAssertEqual(migratedStore.preferences.width, 640)
    XCTAssertEqual(migratedStore.preferences.quality, 0.42)
    XCTAssertEqual(migratedStore.preferences.qualityMode, .automatic)
    XCTAssertEqual(migratedStore.preferences.filenameSuffix, "_640x1080")
  }

  func testCorruptPreferencesFallBackToDefaults() {
    let suiteName = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data([0x00, 0x01, 0x02]), forKey: PreferencesStore.storageKey)

    let store = PreferencesStore(defaults: defaults)

    XCTAssertEqual(store.preferences, UserPreferences())
  }

  func testSuffixSanitizationRemovesPathCharacters() {
    XCTAssertEqual(
      ImageResizeService.sanitizedSuffix(" /yeniden\\boyut: "),
      "-yeniden-boyut-"
    )
    XCTAssertEqual(
      ImageResizeService.sanitizedSuffix("   "),
      "_yeniden-boyutlandirildi"
    )
  }

  func testCopyOutputCollisionStartsAtOneAndIncrements() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("source.png")
    let proposedURL = directory.appendingPathComponent("source_1280x720.png")
    let firstCollisionURL = directory.appendingPathComponent("source_1280x720-1.png")
    try Data().write(to: proposedURL)

    XCTAssertEqual(
      ImageResizeService.uniqueOutputURL(
        sourceURL: sourceURL,
        suffix: "_1280x720",
        outputFormat: .png
      ),
      firstCollisionURL
    )

    try Data().write(to: firstCollisionURL)
    XCTAssertEqual(
      ImageResizeService.uniqueOutputURL(
        sourceURL: sourceURL,
        suffix: "_1280x720",
        outputFormat: .png
      ).lastPathComponent,
      "source_1280x720-2.png"
    )
  }

  func testFormatConversionCollisionStartsAtOne() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("source.png")
    let existingOutputURL = directory.appendingPathComponent("source.jpg")
    try createPNG(at: sourceURL, width: 40, height: 20)
    try Data("existing".utf8).write(to: existingOutputURL)

    var preferences = UserPreferences()
    preferences.width = 10
    preferences.height = 10
    preferences.outputFormat = .jpeg
    preferences.overwritesOriginal = true

    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: preferences)
    )

    XCTAssertEqual(outputURL.lastPathComponent, "source-1.jpg")
    XCTAssertEqual(try Data(contentsOf: existingOutputURL), Data("existing".utf8))
  }

  func testPNGResizeCreatesSiblingCopyWithoutDirectoryGrant() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("source.png")
    try createPNG(at: sourceURL, width: 40, height: 20)

    var preferences = UserPreferences()
    preferences.updateWidth(10)
    preferences.updateHeight(10)
    preferences.outputFormat = .png
    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: preferences)
    )

    XCTAssertEqual(outputURL.lastPathComponent, "source_10x10.png")
    XCTAssertEqual(
      outputURL.deletingLastPathComponent().standardizedFileURL,
      sourceURL.deletingLastPathComponent().standardizedFileURL
    )
    let dimensions = try imageDimensions(at: outputURL)
    XCTAssertEqual(dimensions.width, 10)
    XCTAssertEqual(dimensions.height, 5)
    XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
  }

  func testPNGResizeCreatesCopyInSelectedOutputDirectoryAndResolvesCollision() throws {
    let rootDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = rootDirectory.appendingPathComponent("source", isDirectory: true)
    let outputDirectory = rootDirectory.appendingPathComponent("output", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceDirectory,
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: rootDirectory) }

    let sourceURL = sourceDirectory.appendingPathComponent("source.png")
    let existingOutputURL = outputDirectory.appendingPathComponent("source_10x10.png")
    try createPNG(at: sourceURL, width: 40, height: 20)
    try Data("existing".utf8).write(to: existingOutputURL)

    var preferences = UserPreferences()
    preferences.updateWidth(10)
    preferences.updateHeight(10)
    preferences.outputFormat = .png
    preferences.overwritesOriginal = true
    preferences.selectOutputDirectory(outputDirectory)

    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: preferences)
    )

    XCTAssertEqual(outputURL.lastPathComponent, "source_10x10-1.png")
    XCTAssertEqual(
      outputURL.deletingLastPathComponent().standardizedFileURL,
      outputDirectory.standardizedFileURL
    )
    XCTAssertEqual(try Data(contentsOf: existingOutputURL), Data("existing".utf8))
    XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    XCTAssertEqual(try imageDimensions(at: outputURL).width, 10)
    XCTAssertEqual(try imageDimensions(at: outputURL).height, 5)
  }

  func testResizeRejectsMissingCustomOutputDirectory() throws {
    let sourceDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: sourceDirectory) }

    let sourceURL = sourceDirectory.appendingPathComponent("source.png")
    let missingDirectory = sourceDirectory.appendingPathComponent("missing", isDirectory: true)
    try createPNG(at: sourceURL, width: 40, height: 20)

    var preferences = UserPreferences()
    preferences.outputFormat = .png
    preferences.outputDirectory = OutputDirectoryPreference(path: missingDirectory.path)

    XCTAssertThrowsError(
      try ImageResizeService.resize(
        sourceURL: sourceURL,
        configuration: ResizeConfiguration(preferences: preferences)
      )
    ) { error in
      guard case ImageResizeError.outputFolderNotWritable = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testMainViewModelProcessesWithoutOutputDirectoryPrompt() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("view-model-source.png")
    try createPNG(at: sourceURL, width: 40, height: 20)

    let viewModel = MainViewModel()
    viewModel.addImages(from: [sourceURL])

    var preferences = UserPreferences()
    preferences.width = 10
    preferences.height = 10
    preferences.outputFormat = .png
    preferences.filenameSuffix = "-processed"
    viewModel.startProcessing(preferences: preferences)

    for _ in 0..<100 where viewModel.isProcessing {
      try await Task.sleep(for: .milliseconds(10))
    }

    XCTAssertFalse(viewModel.isProcessing)
    XCTAssertTrue(viewModel.isShowingResults)
    XCTAssertEqual(viewModel.results.count, 1)
    XCTAssertEqual(viewModel.results.first?.status, .success)
    XCTAssertEqual(
      viewModel.results.first?.outputURL?.lastPathComponent,
      "view-model-source-processed.png"
    )

    viewModel.clearSelectionAndDismissResults()

    XCTAssertFalse(viewModel.isShowingResults)
    XCTAssertTrue(viewModel.selectedImages.isEmpty)
    XCTAssertTrue(viewModel.results.isEmpty)
  }

  func testJPEGResizeCreatesSiblingCopyWithoutDirectoryGrant() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("jpeg-source.png")
    try createPNG(at: sourceURL, width: 40, height: 20)

    var preferences = UserPreferences()
    preferences.width = 10
    preferences.height = 10
    preferences.outputFormat = .jpeg
    preferences.filenameSuffix = "-small"
    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: preferences)
    )

    XCTAssertEqual(outputURL.lastPathComponent, "jpeg-source-small.jpg")
    XCTAssertEqual(try imageDimensions(at: outputURL).width, 10)
    XCTAssertEqual(try imageDimensions(at: outputURL).height, 5)
  }

  func testAutomaticJPEGStaysWithinSameFormatSourceBudget() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("automatic-source.jpg")
    try createPatternJPEG(at: sourceURL, width: 160, height: 90, quality: 0.25)

    var preferences = UserPreferences()
    preferences.width = 128
    preferences.height = 72
    preferences.outputFormat = .jpeg
    preferences.qualityMode = .automatic
    preferences.filenameSuffix = "-automatic"
    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: preferences)
    )

    let sourceByteCount = try Data(contentsOf: sourceURL).count
    let outputByteCount = try Data(contentsOf: outputURL).count
    XCTAssertLessThanOrEqual(outputByteCount, sourceByteCount)
    XCTAssertEqual(try imageDimensions(at: outputURL).width, 128)
    XCTAssertEqual(try imageDimensions(at: outputURL).height, 72)
  }

  func testJPEGUsesSelectedBackgroundColorForTransparency() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("transparent-source.png")
    try createPNG(at: sourceURL, width: 40, height: 20, includesTransparency: true)

    var preferences = UserPreferences()
    preferences.width = 40
    preferences.height = 20
    preferences.outputFormat = .jpeg
    preferences.qualityMode = .manual
    preferences.quality = 1
    preferences.filenameSuffix = "-background"
    preferences.jpegBackgroundColor = RGBColor(red: 0.9, green: 0.1, blue: 0.1)

    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: preferences)
    )
    let backgroundPixel = try decodedRGBPixel(
      at: outputURL,
      x: 38,
      y: 10
    )

    XCTAssertGreaterThan(backgroundPixel.red, 0.65)
    XCTAssertLessThan(backgroundPixel.green, 0.35)
    XCTAssertLessThan(backgroundPixel.blue, 0.35)
  }

  func testWebPResizeEncodesQualityAndPreservesAlpha() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceURL = directory.appendingPathComponent("transparent-source.png")
    try createPNG(at: sourceURL, width: 40, height: 20, includesTransparency: true)

    var lowQualityPreferences = UserPreferences()
    lowQualityPreferences.width = 10
    lowQualityPreferences.height = 10
    lowQualityPreferences.outputFormat = .webP
    lowQualityPreferences.qualityMode = .manual
    lowQualityPreferences.quality = 0.2
    lowQualityPreferences.filenameSuffix = "-low"
    let lowQualityURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: lowQualityPreferences)
    )

    var highQualityPreferences = lowQualityPreferences
    highQualityPreferences.quality = 0.95
    highQualityPreferences.filenameSuffix = "-high"
    let highQualityURL = try ImageResizeService.resize(
      sourceURL: sourceURL,
      configuration: ResizeConfiguration(preferences: highQualityPreferences)
    )

    let lowQualityData = try Data(contentsOf: lowQualityURL)
    let highQualityData = try Data(contentsOf: highQualityURL)
    XCTAssertEqual(String(data: lowQualityData.prefix(4), encoding: .ascii), "RIFF")
    XCTAssertEqual(String(data: lowQualityData.dropFirst(8).prefix(4), encoding: .ascii), "WEBP")
    XCTAssertNotEqual(lowQualityData, highQualityData)
    XCTAssertEqual(try imageDimensions(at: highQualityURL).width, 10)
    XCTAssertEqual(try imageDimensions(at: highQualityURL).height, 5)

    let alphaValues = try decodedAlphaValues(at: highQualityURL)
    XCTAssertTrue(alphaValues.contains(0))
    XCTAssertTrue(alphaValues.contains(255))
  }

  private func createPNG(
    at url: URL,
    width: Int,
    height: Int,
    includesTransparency: Bool = false
  ) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(
      CGRect(
        x: 0,
        y: 0,
        width: includesTransparency ? width / 2 : width,
        height: height
      )
    )
    let image = context.makeImage()!

    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.png" as CFString,
        1,
        nil
      )
    else {
      XCTFail("PNG destination could not be created")
      return
    }
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }

  private func createPatternJPEG(
    at url: URL,
    width: Int,
    height: Int,
    quality: Double
  ) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    for y in stride(from: 0, to: height, by: 4) {
      for x in stride(from: 0, to: width, by: 4) {
        let seed = (x * 31 + y * 17) % 255
        context.setFillColor(
          CGColor(
            red: CGFloat(seed) / 255,
            green: CGFloat((seed * 3) % 255) / 255,
            blue: CGFloat((seed * 7) % 255) / 255,
            alpha: 1
          )
        )
        context.fill(CGRect(x: x, y: y, width: 4, height: 4))
      }
    }

    let image = context.makeImage()!
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        "public.jpeg" as CFString,
        1,
        nil
      )
    else {
      XCTFail("JPEG destination could not be created")
      return
    }
    let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }

  private func imageDimensions(at url: URL) throws -> (width: Int, height: Int) {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else {
      XCTFail("Output dimensions could not be read")
      return (0, 0)
    }
    return (width.intValue, height.intValue)
  }

  private func decodedAlphaValues(at url: URL) throws -> [UInt8] {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
      XCTFail("WebP output could not be decoded")
      return []
    }

    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let didRender = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let baseAddress = buffer.baseAddress,
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
          ).rawValue
        )
      else {
        return false
      }

      context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
      )
      return true
    }

    XCTAssertTrue(didRender)
    return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
  }

  private func decodedRGBPixel(
    at url: URL,
    x: Int,
    y: Int
  ) throws -> (red: Double, green: Double, blue: Double) {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      x >= 0,
      x < image.width,
      y >= 0,
      y < image.height
    else {
      XCTFail("JPEG output pixel could not be read")
      return (0, 0, 0)
    }

    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    let didRender = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let baseAddress = buffer.baseAddress,
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: baseAddress,
          width: image.width,
          height: image.height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
          ).rawValue
        )
      else {
        return false
      }

      context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
      )
      return true
    }

    XCTAssertTrue(didRender)
    let offset = (y * bytesPerRow) + (x * 4)
    return (
      Double(pixels[offset]) / 255,
      Double(pixels[offset + 1]) / 255,
      Double(pixels[offset + 2]) / 255
    )
  }
}
