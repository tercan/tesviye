import AppKit
import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import tesviye

@MainActor
final class TesviyeTests: XCTestCase {
  func testKeepSizeConvertsEveryFormatWithoutResizing() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("original.png")
    try createPNG(at: source, width: 83, height: 47, includesTransparency: true)
    let originalData = try Data(contentsOf: source)
    for format in OutputFormat.allCases {
      var preferences = UserPreferences()
      preferences.width = 10
      preferences.height = 999
      preferences.allowsUpscaling = true
      preferences.preservesAspectRatio = false
      preferences.selectPreset(.original)
      preferences.outputFormat = format
      let output = try ImageResizeService.resize(
        sourceURL: source, configuration: ResizeConfiguration(preferences: preferences)
      )
      let dimensions = try imageDimensions(at: output)
      XCTAssertEqual(dimensions.width, 83)
      XCTAssertEqual(dimensions.height, 47)
      XCTAssertEqual(output.pathExtension, format.fileExtension)
      XCTAssertEqual(try Data(contentsOf: source), originalData)
    }
  }

  func testKeepSizePreservesOrientedJPEGDimensions() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("rotated.jpeg")
    try createPatternJPEG(at: source, width: 83, height: 47, quality: 0.8, orientation: 6)
    var preferences = UserPreferences()
    preferences.selectPreset(.original)
    preferences.outputFormat = .png
    let output = try ImageResizeService.resize(
      sourceURL: source, configuration: ResizeConfiguration(preferences: preferences)
    )
    let dimensions = try imageDimensions(at: output)
    XCTAssertEqual(dimensions.width, 47)
    XCTAssertEqual(dimensions.height, 83)
  }

  func testKeepSizeBatchPreservesEachSourceDimensions() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("first.png")
    let second = directory.appendingPathComponent("second.png")
    try createPNG(at: first, width: 80, height: 40)
    try createPNG(at: second, width: 30, height: 70)
    let model = MainViewModel()
    model.addImages(from: [first, second])
    var preferences = UserPreferences()
    preferences.selectPreset(.original)
    model.startProcessing(preferences: preferences)
    for _ in 0..<200 where model.isProcessing { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertFalse(model.isProcessing)
    XCTAssertEqual(model.successfulResults.count, 2)
    let firstOutput = try XCTUnwrap(model.results.first?.outputURL)
    let secondOutput = try XCTUnwrap(model.results.last?.outputURL)
    XCTAssertEqual(try imageDimensions(at: firstOutput).width, 80)
    XCTAssertEqual(try imageDimensions(at: firstOutput).height, 40)
    XCTAssertEqual(try imageDimensions(at: secondOutput).width, 30)
    XCTAssertEqual(try imageDimensions(at: secondOutput).height, 70)
  }

  func testOriginalAndCustomSelectionsSurviveNormalizationAndReload() throws {
    let suite = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: defaults, fallbackAppearance: .light)
    store.preferences.selectPreset(.original)
    store.flush()
    let original = PreferencesStore(defaults: defaults).preferences
    XCTAssertEqual(original.selectedPreset, .original)
    XCTAssertTrue(ResizeConfiguration(preferences: original).preservesOriginalSize)
    XCTAssertEqual(original.filenameSuffix, "_original")
    store.preferences.selectPreset(.custom)
    store.preferences.updateWidth(1920)
    store.preferences.updateHeight(1080)
    store.flush()
    let custom = PreferencesStore(defaults: defaults).preferences
    XCTAssertEqual(custom.selectedPreset, .custom)
    XCTAssertFalse(ResizeConfiguration(preferences: custom).preservesOriginalSize)
  }

  func testOutputFormatDoesNotChangeCustomDimensions() {
    var preferences = UserPreferences()
    preferences.selectPreset(.custom)
    preferences.updateWidth(1234)
    preferences.updateHeight(567)
    for format in OutputFormat.allCases {
      preferences.outputFormat = format
      preferences.normalize()
      let configuration = ResizeConfiguration(preferences: preferences)
      XCTAssertEqual(configuration.outputFormat, format)
      XCTAssertEqual(configuration.width, 1234)
      XCTAssertEqual(configuration.height, 567)
      XCTAssertEqual(preferences.selectedPreset, .custom)
    }
    XCTAssertEqual(ResizePreset.visiblePresets.first, .original)
    XCTAssertEqual(ResizePreset.visiblePresets.last, .custom)
    XCTAssertEqual(ResizePreset.visiblePresets.count, 7)
  }

  func testLegacySystemAppearanceMigratesWithoutResettingOtherPreferences() throws {
    let suite = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var preferences = UserPreferences()
    preferences.updateWidth(987)
    preferences.usesFilenameSuffix = false
    let data = try JSONEncoder().encode(
      StoredPreferences(schemaVersion: 6, preferences: preferences))
    var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var stored = try XCTUnwrap(root["preferences"] as? [String: Any])
    stored["appearanceMode"] = "system"
    root["preferences"] = stored
    defaults.set(
      try JSONSerialization.data(withJSONObject: root), forKey: PreferencesStore.storageKey)
    let migrated = PreferencesStore(defaults: defaults, fallbackAppearance: .dark)
    XCTAssertEqual(migrated.preferences.appearanceMode, .dark)
    XCTAssertEqual(migrated.preferences.width, 987)
    XCTAssertFalse(migrated.preferences.usesFilenameSuffix)
    migrated.flush()
    XCTAssertEqual(
      PreferencesStore(defaults: defaults, fallbackAppearance: .light).preferences.appearanceMode,
      .dark)
  }

  func testIdleTerminationSavesPreferencesAndExitsImmediately() {
    let suite = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: defaults)
    store.preferences.selectPreset(.original)
    let coordinator = ApplicationTerminationCoordinator()
    let result = coordinator.shouldTerminate(
      viewModel: MainViewModel(), preferencesStore: store,
      confirmCancellation: {
        XCTFail("Idle termination must not show a confirmation")
        return false
      },
      reply: { _ in XCTFail("Idle termination must be immediate") }
    )
    XCTAssertEqual(result, .terminateNow)
    XCTAssertEqual(PreferencesStore(defaults: defaults).preferences.selectedPreset, .original)
  }

  func testProcessingTerminationCanBeCancelledThenFinishesSafely() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.png")
    try createPNG(at: source, width: 40, height: 20)
    let suite = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = PreferencesStore(defaults: defaults)
    let model = MainViewModel()
    model.addImages(from: [source])
    model.startProcessing(preferences: store.preferences)
    let coordinator = ApplicationTerminationCoordinator()
    XCTAssertEqual(
      coordinator.shouldTerminate(
        viewModel: model, preferencesStore: store, confirmCancellation: { false },
        reply: { _ in XCTFail("Cancelled quit must not reply") }
      ), .terminateCancel)
    XCTAssertTrue(model.isProcessing)
    let completed = expectation(description: "Processing has stopped before termination")
    XCTAssertEqual(
      coordinator.shouldTerminate(
        viewModel: model, preferencesStore: store, confirmCancellation: { true },
        reply: { allowed in
          XCTAssertTrue(allowed)
          XCTAssertFalse(model.isProcessing)
          XCTAssertNotNil(defaults.data(forKey: PreferencesStore.storageKey))
          completed.fulfill()
        }
      ), .terminateLater)
    await fulfillment(of: [completed], timeout: 5)
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
  }

  func testCompactWindowLayoutAndResultActions() throws {
    let suiteName = "TesviyeTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = PreferencesStore(defaults: defaults, fallbackAppearance: .light)
    let model = MainViewModel()
    store.preferences.selectPreset(.original)
    let original = try renderView(
      ContentView().environmentObject(store).environmentObject(model), name: "main-original-light"
    )
    XCTAssertEqual(original.width, 740, accuracy: 1)
    XCTAssertLessThan(original.height, 720)

    store.preferences.selectPreset(.custom)
    store.preferences.updateWidth(1234)
    store.preferences.updateHeight(567)
    store.preferences.outputFormat = .png
    let custom = try renderView(
      ContentView().environmentObject(store).environmentObject(model), name: "main-custom-light"
    )
    XCTAssertEqual(custom.width, 740, accuracy: 1)
    XCTAssertEqual(custom.height, original.height, accuracy: 1)
    store.preferences.appearanceMode = .dark
    _ = try renderView(
      ContentView().environmentObject(store).environmentObject(model), name: "main-custom-dark",
      colorScheme: .dark
    )

    let source = URL(fileURLWithPath: "/tmp/source.jpeg")
    let success = ResizeResult(sourceURL: source, outputURL: source, status: .success, message: nil)
    let resultView = ProcessingResultsView(
      summary: BatchResultSummary(results: Array(repeating: success, count: 42), total: 42),
      failedResults: [], onReveal: {}, onClear: {}, onDismiss: {}
    )
    let resultSize = try renderView(resultView, name: "results-42")
    XCTAssertEqual(resultSize.width, 560, accuracy: 1)
    XCTAssertLessThan(resultSize.height, original.height)
  }

  func testColorPanelDisablingDetachesActiveWellAndPreventsReopening() {
    let well = PositionedColorWell(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
    defer { well.dismissColorPanel() }
    well.activate(true)
    XCTAssertTrue(well.isActive)
    well.updateEnabledState(false)
    XCTAssertFalse(well.isEnabled)
    XCTAssertFalse(well.isActive)
    XCTAssertFalse(NSColorPanel.shared.isVisible)
    well.activate(true)
    XCTAssertFalse(well.isActive)
  }

  func testColorPanelOutsideClickClosesPanelWithoutConsumingOtherControls() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
      styleMask: .borderless, backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    let well = PositionedColorWell(frame: NSRect(x: 10, y: 10, width: 30, height: 24))
    window.contentView?.addSubview(well)
    defer {
      well.dismissColorPanel()
      window.close()
    }
    well.activate(true)
    let event = try makeMouseDown(window: window, point: CGPoint(x: 150, y: 100))
    XCTAssertTrue(well.handleMouseDown(event) === event)
    XCTAssertFalse(well.isActive)
    XCTAssertFalse(NSColorPanel.shared.isVisible)
  }

  func testColorPanelInternalClickStaysActiveAndSwatchClickCloses() throws {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 160),
      styleMask: .borderless, backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    let well = PositionedColorWell(frame: NSRect(x: 10, y: 10, width: 30, height: 24))
    window.contentView?.addSubview(well)
    defer {
      well.dismissColorPanel()
      window.close()
    }
    well.activate(true)
    let panelEvent = try makeMouseDown(window: NSColorPanel.shared, point: CGPoint(x: 20, y: 20))
    XCTAssertTrue(well.handleMouseDown(panelEvent) === panelEvent)
    XCTAssertTrue(well.isActive)
    let swatchEvent = try makeMouseDown(window: window, point: CGPoint(x: 20, y: 20))
    XCTAssertNil(well.handleMouseDown(swatchEvent))
    XCTAssertFalse(well.isActive)
  }

  func testColorPanelClosesWhenApplicationBecomesInactive() {
    let well = PositionedColorWell(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
    defer { well.dismissColorPanel() }
    well.activate(true)
    NotificationCenter.default.post(
      name: NSApplication.didResignActiveNotification, object: NSApplication.shared
    )
    XCTAssertFalse(well.isActive)
    XCTAssertFalse(NSColorPanel.shared.isVisible)
  }

  private func makeMouseDown(window: NSWindow, point: CGPoint) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1
      )
    )
  }

  private func renderView<Content: View>(
    _ content: Content, name: String, colorScheme: ColorScheme = .light
  ) throws -> CGSize {
    let view = NSHostingView(
      rootView: content.background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: "tr"))
        .environment(\.colorScheme, colorScheme)
    )
    view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    let size = view.fittingSize
    view.setFrameSize(size)
    view.layoutSubtreeIfNeeded()
    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    let directory = URL(fileURLWithPath: "/tmp/Tesviye-1.2.0-qa", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try data.write(to: directory.appendingPathComponent("\(name).png"))
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    return size
  }

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

  func testAppearanceChoicesExcludeSystemMode() {
    XCTAssertEqual(AppearanceMode.allCases, [.light, .dark])
  }

  func testLastWindowClosureRequestsApplicationTermination() {
    let delegate = ExternalImageOpenCoordinator()
    XCTAssertTrue(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    var requested = false
    delegate.terminationHandler = {
      requested = true
      return .terminateNow
    }
    XCTAssertEqual(delegate.applicationShouldTerminate(NSApplication.shared), .terminateNow)
    XCTAssertTrue(requested)
  }

  func testBatchResultSummaryDistinguishesSuccessFailureAndCancellation() {
    let source = URL(fileURLWithPath: "/tmp/source.png")
    let success = ResizeResult(sourceURL: source, outputURL: source, status: .success, message: nil)
    let failure = ResizeResult(
      sourceURL: source, outputURL: nil, status: .failure, message: "Error")
    let completed = BatchResultSummary(results: Array(repeating: success, count: 42), total: 42)
    XCTAssertEqual(completed.status, .completed)
    XCTAssertEqual(completed.successCount, 42)
    XCTAssertEqual(completed.failureCount, 0)
    XCTAssertEqual(completed.remainingCount, 0)
    XCTAssertEqual(
      BatchResultSummary(results: [success, failure], total: 2).status, .completedWithErrors)
    XCTAssertEqual(BatchResultSummary(results: [failure], total: 1).status, .failed)
    let cancelled = BatchResultSummary(results: [success], total: 3)
    XCTAssertEqual(cancelled.status, .cancelled)
    XCTAssertEqual(cancelled.remainingCount, 2)
  }

  func testDisabledFilenameSuffixKeepsStoredTextAndProducesNoSuffix() {
    var preferences = UserPreferences()
    preferences.filenameSuffix = "_custom"
    preferences.usesFilenameSuffix = false
    preferences.normalize()
    XCTAssertEqual(preferences.filenameSuffix, "_custom")
    XCTAssertEqual(ResizeConfiguration(preferences: preferences).filenameSuffix, "")
    preferences.usesFilenameSuffix = true
    XCTAssertEqual(ResizeConfiguration(preferences: preferences).filenameSuffix, "_custom")
  }

  func testLegacyPreferencesEnableSuffixByDefault() throws {
    let encoded = try JSONEncoder().encode(UserPreferences())
    var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "usesFilenameSuffix")
    let decoded = try JSONDecoder().decode(
      UserPreferences.self, from: JSONSerialization.data(withJSONObject: legacy)
    )
    XCTAssertTrue(decoded.usesFilenameSuffix)
    XCTAssertEqual(decoded.effectiveFilenameSuffix, "_1920x1080")
  }

  func testVersionFiveCustomSuffixIsPreservedDuringMigration() {
    var preferences = UserPreferences()
    preferences.filenameSuffix = "-resized"
    preferences.migrateFilenameSuffixIfNeeded(from: 5)
    XCTAssertEqual(preferences.filenameSuffix, "-resized")
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
      "FinderResizeIconTemplate"
    )
    XCTAssertNotNil(extensionBundle.url(forResource: "Assets", withExtension: "car"))
    let icon = try XCTUnwrap(extensionBundle.image(forResource: "FinderResizeIconTemplate"))
    XCTAssertTrue(icon.isTemplate)
  }

  func testFinderActionUsesTitleCaseTurkishMenuLabels() throws {
    let resources = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
      .appendingPathComponent("TesviyeFinderAction.appex/Contents/Resources")
    let turkish = try XCTUnwrap(Bundle(url: resources.appendingPathComponent("tr.lproj")))
    let english = try XCTUnwrap(Bundle(url: resources.appendingPathComponent("en.lproj")))
    for key in ["CFBundleDisplayName", "NSExtensionServiceFinderPreviewLabel"] {
      XCTAssertEqual(
        turkish.localizedString(forKey: key, value: nil, table: "InfoPlist"),
        "Görselleri Yeniden Boyutlandır"
      )
      XCTAssertEqual(
        english.localizedString(forKey: key, value: nil, table: "InfoPlist"), "Resize Images"
      )
    }
  }

  func testFinderIconRemainsVisibleWhenHostDrawsOriginalPixels() throws {
    let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
    let bundle = try XCTUnwrap(
      Bundle(url: plugInsURL.appendingPathComponent("TesviyeFinderAction.appex"))
    )
    let image = try XCTUnwrap(bundle.image(forResource: "FinderResizeIconTemplate"))
    XCTAssertTrue(image.isTemplate)
    let light = try renderFinderIcon(image, appearance: .aqua)
    let dark = try renderFinderIcon(image, appearance: .darkAqua)
    var lightBrightness: CGFloat = 0
    var darkBrightness: CGFloat = 0
    var coveredPixels = 0
    for y in 0..<48 {
      for x in 0..<48 {
        let lightColor = try XCTUnwrap(light.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        let darkColor = try XCTUnwrap(dark.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        XCTAssertEqual(lightColor.alphaComponent, darkColor.alphaComponent, accuracy: 0.02)
        if lightColor.alphaComponent > 0.5 {
          lightBrightness += lightColor.redComponent
          darkBrightness += darkColor.redComponent
          coveredPixels += 1
        }
      }
    }
    XCTAssertGreaterThan(coveredPixels, 100)
    XCTAssertLessThan(lightBrightness / CGFloat(coveredPixels), 0.1)
    XCTAssertGreaterThan(darkBrightness / CGFloat(coveredPixels), 0.9)
  }

  private func renderFinderIcon(
    _ image: NSImage, appearance: NSAppearance.Name
  ) throws -> NSBitmapImageRep {
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
      )
    )
    let rawImage = try XCTUnwrap(image.copy() as? NSImage)
    // Finder hosts may rasterize an extension icon before applying template tinting.
    rawImage.isTemplate = false
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    try XCTUnwrap(NSAppearance(named: appearance)).performAsCurrentDrawingAppearance {
      rawImage.draw(in: NSRect(x: 0, y: 0, width: 48, height: 48))
    }
    let output = URL(fileURLWithPath: "/tmp/Tesviye-1.1.2-qa", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let name = appearance == .darkAqua ? "finder-dark.png" : "finder-light.png"
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
      .write(to: output.appendingPathComponent(name))
    return bitmap
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

    XCTAssertEqual(preferences.appearanceMode, .light)
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
    store.preferences.usesFilenameSuffix = false
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
    XCTAssertFalse(reloadedStore.preferences.usesFilenameSuffix)
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

    let store = PreferencesStore(defaults: defaults, fallbackAppearance: .light)

    XCTAssertEqual(store.preferences, UserPreferences())
  }

  func testSuffixSanitizationRemovesPathCharacters() {
    XCTAssertEqual(
      ImageResizeService.sanitizedSuffix(" /yeniden\\boyut: "),
      "-yeniden-boyut-"
    )
    XCTAssertEqual(
      ImageResizeService.sanitizedSuffix("   "),
      ""
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

  func testJPEGToJPGWithoutSuffixPreservesSourceAndExistingOutput() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("photo.jpeg")
    try createPatternJPEG(at: sourceURL, width: 40, height: 20, quality: 0.8)
    let originalData = try Data(contentsOf: sourceURL)
    var preferences = UserPreferences()
    preferences.usesFilenameSuffix = false
    preferences.width = 20
    preferences.height = 10
    let configuration = ResizeConfiguration(preferences: preferences)
    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL, configuration: configuration)
    XCTAssertEqual(outputURL.lastPathComponent, "photo.jpg")
    let outputData = try Data(contentsOf: outputURL)
    let duplicateURL = try ImageResizeService.resize(
      sourceURL: sourceURL, configuration: configuration)
    XCTAssertEqual(duplicateURL.lastPathComponent, "photo-1.jpg")
    XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
    XCTAssertEqual(try Data(contentsOf: outputURL), outputData)
    XCTAssertEqual(try imageDimensions(at: outputURL).width, 20)
  }

  func testSameFormatWithoutSuffixNeverReplacesSource() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("TesviyeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let sourceURL = directory.appendingPathComponent("photo.png")
    try createPNG(at: sourceURL, width: 40, height: 20)
    let originalData = try Data(contentsOf: sourceURL)
    var preferences = UserPreferences()
    preferences.usesFilenameSuffix = false
    preferences.outputFormat = .png
    preferences.width = 20
    preferences.height = 10
    let outputURL = try ImageResizeService.resize(
      sourceURL: sourceURL, configuration: ResizeConfiguration(preferences: preferences)
    )
    XCTAssertEqual(outputURL.lastPathComponent, "photo-1.png")
    XCTAssertEqual(try Data(contentsOf: sourceURL), originalData)
    XCTAssertEqual(try imageDimensions(at: outputURL).width, 20)
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
    quality: Double,
    orientation: Int = 1
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
    let properties =
      [
        kCGImageDestinationLossyCompressionQuality: quality,
        kCGImagePropertyOrientation: orientation,
      ] as CFDictionary
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
