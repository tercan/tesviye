import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @EnvironmentObject private var preferencesStore: PreferencesStore
  @EnvironmentObject private var viewModel: MainViewModel
  @State private var isAdvancedExpanded = false
  @State private var isAdvancedContentVisible = false
  @State private var isShowingAbout = false
  @State private var isShowingOverwriteConfirmation = false

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        windowHeader
        Divider()

        VStack(spacing: 0) {
          selectionHeader
          Divider()
          presetsSection
          Divider()
          dimensionsSection
          Divider()
          behaviorSection
          Divider()
          outputSection
          Divider()
          advancedSection
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)

        Spacer(minLength: 0)

        Divider()
        actionBar
      }
      .disabled(isAppModalPresented)
      .accessibilityHidden(isAppModalPresented)

      if isAppModalPresented {
        appModalLayer
      }
    }
    .frame(width: 740, height: preferredWindowHeight)
    .background(Color(nsColor: .windowBackgroundColor))
    .dropDestination(for: URL.self) { urls, _ in
      viewModel.addImages(from: urls)
      return true
    }
  }

  private var windowHeader: some View {
    HStack(spacing: 8) {
      Button {
        closeMainWindow()
      } label: {
        Image(systemName: "xmark")
          .frame(width: 26, height: 26)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("window.close.help")
      .accessibilityLabel("window.close.help")

      Button {
        minimizeMainWindow()
      } label: {
        Image(systemName: "minus")
          .frame(width: 26, height: 26)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("window.minimize.help")
      .accessibilityLabel("window.minimize.help")

      Text("app.name")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)

      Spacer()

      Button {
        cycleAppearance()
      } label: {
        Image(systemName: preferencesStore.preferences.appearanceMode.systemImage)
          .frame(width: 26, height: 26)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(appearanceHelpText)
      .accessibilityLabel(appearanceHelpText)

      Button {
        isShowingAbout = true
      } label: {
        Image(systemName: "info.circle")
          .frame(width: 26, height: 26)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("toolbar.info.help")
      .accessibilityLabel("toolbar.info.help")
    }
    .padding(.horizontal, 12)
    .frame(height: 38)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var isAppModalPresented: Bool {
    isShowingAbout
      || isShowingOverwriteConfirmation
      || viewModel.isShowingSelectionList
      || viewModel.isShowingResults
  }

  private var appModalLayer: some View {
    ZStack {
      Color.black.opacity(0.24)
        .accessibilityHidden(true)

      appModalContent
    }
    .onExitCommand {
      dismissActiveModal()
    }
  }

  @ViewBuilder
  private var appModalContent: some View {
    if isShowingOverwriteConfirmation {
      radiuslessModalSurface {
        overwriteConfirmationModal
      }
    } else if viewModel.isShowingResults {
      radiuslessModalSurface {
        resultsView
      }
    } else if viewModel.isShowingSelectionList {
      radiuslessModalSurface {
        selectionList
      }
    } else if isShowingAbout {
      radiuslessModalSurface {
        AboutView {
          isShowingAbout = false
        }
      }
    }
  }

  private func radiuslessModalSurface<ModalContent: View>(
    @ViewBuilder content: () -> ModalContent
  ) -> some View {
    content()
      .background(Color(nsColor: .windowBackgroundColor))
      .overlay {
        Rectangle()
          .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
          .allowsHitTesting(false)
      }
      .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
      .accessibilityAddTraits(.isModal)
  }

  private var overwriteConfirmationModal: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("overwrite.confirmation.title")
        .font(.title3.weight(.semibold))
      Text("overwrite.confirmation.message")
        .foregroundStyle(.secondary)

      HStack {
        Spacer()
        Button("action.cancel", role: .cancel) {
          isShowingOverwriteConfirmation = false
        }
        .keyboardShortcut(.cancelAction)

        Button("overwrite.confirmation.action", role: .destructive) {
          isShowingOverwriteConfirmation = false
          startProcessing()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 460)
  }

  private var selectionHeader: some View {
    HStack(spacing: 16) {
      Image(
        systemName: viewModel.selectedImages.isEmpty ? "photo.on.rectangle.angled" : "photo.stack"
      )
      .font(.system(size: 38, weight: .regular))
      .foregroundStyle(
        viewModel.selectedImages.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint)
      )
      .frame(width: 54, height: 54)
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(viewModel.selectionTitle)
          .font(.title3.weight(.semibold))
        Text(viewModel.selectionSubtitle)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if viewModel.selectedImages.isEmpty {
        Button("selection.choose") {
          chooseImages()
        }
      } else {
        HStack(spacing: 12) {
          Button("selection.add") {
            chooseImages()
          }
          Button("selection.showList") {
            viewModel.isShowingSelectionList = true
          }
          .buttonStyle(.link)
        }
      }
    }
    .padding(.bottom, 18)
    .contentShape(Rectangle())
    .accessibilityElement(children: .contain)
  }

  private var presetsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("preset.title")
        .font(.headline)

      HStack(spacing: 0) {
        ForEach(ResizePreset.visiblePresets) { preset in
          Button {
            selectPreset(preset)
          } label: {
            VStack(spacing: 6) {
              Image(systemName: preset.systemImage)
                .font(.system(size: 16, weight: .regular))
              if let dimensions = preset.dimensions {
                Text("\(dimensions.width) × \(dimensions.height)")
                  .font(.callout)
              }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
          }
          .buttonStyle(
            PresetButtonStyle(
              isSelected: preferencesStore.preferences.selectedPreset == preset
            )
          )
          .help(presetAccessibilityName(preset))
          .accessibilityLabel(presetAccessibilityName(preset))
        }
      }
      .overlay {
        Rectangle()
          .stroke(.quaternary, lineWidth: 1)
          .allowsHitTesting(false)
      }
    }
    .padding(.vertical, 16)
  }

  private var dimensionsSection: some View {
    HStack(alignment: .bottom, spacing: 12) {
      Text("dimensions.title")
        .font(.headline)
        .frame(width: 120, alignment: .leading)
        .padding(.bottom, 7)

      dimensionField(
        title: "dimensions.width",
        value: widthBinding
      )

      Button {
        var preferences = preferencesStore.preferences
        preferences.swapDimensions()
        preferencesStore.preferences = preferences
      } label: {
        Image(systemName: "arrow.left.arrow.right")
          .frame(width: 26, height: 26)
      }
      .help("dimensions.swap.help")
      .accessibilityLabel("dimensions.swap.help")
      .padding(.bottom, 1)

      dimensionField(
        title: "dimensions.height",
        value: heightBinding
      )

      Button {
        preferencesStore.preferences.preservesAspectRatio.toggle()
      } label: {
        Image(
          systemName: preferencesStore.preferences.preservesAspectRatio ? "lock.fill" : "lock.open"
        )
        .frame(width: 26, height: 26)
      }
      .help(aspectRatioHelpText)
      .accessibilityLabel(aspectRatioHelpText)
      .padding(.bottom, 1)
    }
    .padding(.vertical, 16)
  }

  private var behaviorSection: some View {
    VStack(spacing: 0) {
      settingsToggleRow(
        title: "upscale.title",
        isOn: $preferencesStore.preferences.allowsUpscaling,
        description: preferencesStore.preferences.allowsUpscaling
          ? "upscale.on.description"
          : "upscale.off.description"
      )

      Divider()

      settingsToggleRow(
        title: "overwrite.title",
        isOn: $preferencesStore.preferences.overwritesOriginal,
        description: preferencesStore.preferences.overwritesOriginal
          ? "overwrite.on.description"
          : preferencesStore.preferences.outputDirectory == nil
            ? "overwrite.off.description"
            : "overwrite.off.customLocation.description",
        isEnabled: preferencesStore.preferences.outputDirectory == nil
      )
    }
  }

  private var outputSection: some View {
    HStack(spacing: 14) {
      HStack(spacing: 10) {
        Text("format.title")
          .font(.headline)

        Picker("format.title", selection: $preferencesStore.preferences.outputFormat) {
          ForEach(OutputFormat.allCases, id: \.self) { format in
            Text(format.displayName).tag(format)
          }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity)

      Divider()
        .frame(height: 34)

      HStack(spacing: 10) {
        Text("quality.title")
          .font(.headline)

        Button {
          var preferences = preferencesStore.preferences
          preferences.toggleQualityMode()
          preferencesStore.preferences = preferences
        } label: {
          Image(systemName: qualityModeSystemImage)
            .foregroundStyle(.tint)
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .disabled(!preferencesStore.preferences.outputFormat.supportsQualityAdjustment)
        .help(qualityModeHelpText)
        .accessibilityLabel(qualityModeHelpText)

        Slider(
          value: $preferencesStore.preferences.quality,
          in: 0.01...1,
          step: 0.01
        )
        .frame(minWidth: 150, maxWidth: .infinity)
        .disabled(!preferencesStore.preferences.isManualQualityControlEnabled)
        .accessibilityLabel("quality.title")

        Text(
          preferencesStore.preferences.isManualQualityControlEnabled
            ? manualQualityText
            : ""
        )
        .monospacedDigit()
        .frame(width: 42, alignment: .trailing)
        .accessibilityHidden(!preferencesStore.preferences.isManualQualityControlEnabled)
      }
      .frame(maxWidth: .infinity)
    }
    .padding(.vertical, 16)
  }

  private var advancedSection: some View {
    VStack(spacing: 0) {
      Button {
        toggleAdvancedSection()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: isAdvancedExpanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .frame(width: 12)
          Text("advanced.title")
            .font(.headline)
          Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(advancedToggleHelpText)
      .accessibilityLabel("advanced.title")
      .accessibilityHint(advancedToggleHelpText)

      if isAdvancedExpanded {
        advancedSettingsContent
          .opacity(isAdvancedContentVisible ? 1 : 0)
      }
    }
    .padding(.vertical, 2)
  }

  private var advancedSettingsContent: some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text("advanced.suffix.title")
          .frame(width: 190, alignment: .leading)
        VStack(alignment: .leading, spacing: 4) {
          TextField(
            "advanced.suffix.placeholder",
            text: $preferencesStore.preferences.filenameSuffix
          )
          Text(suffixExample)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 10)

      Divider()

      HStack {
        Text("advanced.location.title")
          .frame(width: 190, alignment: .leading)
        if let selectedPath = selectedOutputDirectoryDisplayPath {
          Text(verbatim: selectedPath)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.secondary)
            .help(preferencesStore.preferences.outputDirectory?.path ?? selectedPath)
        } else {
          Text("advanced.location.sameFolder")
            .foregroundStyle(.secondary)
        }
        Spacer()
        if preferencesStore.preferences.outputDirectory != nil {
          Button("advanced.location.reset") {
            preferencesStore.preferences.resetOutputDirectory()
          }
          .help("advanced.location.reset.help")
        }
        Button("advanced.location.change") {
          chooseOutputDirectory()
        }
        .help("advanced.location.change.help")
      }
      .padding(.vertical, 10)

      Divider()

      Toggle(
        "advanced.metadata.preserve",
        isOn: $preferencesStore.preferences.preservesMetadata
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 10)

      Divider()

      Toggle(
        "advanced.metadata.removeLocation",
        isOn: $preferencesStore.preferences.removesLocationMetadata
      )
      .disabled(!preferencesStore.preferences.preservesMetadata)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 10)

      Divider()

      HStack {
        Text("advanced.jpegBackground.title")
        Spacer()
        AnchoredColorWell(
          color: jpegBackgroundColorBinding,
          accessibilityLabel: String(localized: "advanced.jpegBackground.title"),
          panelTrailingClearance: 70
        )
        .frame(width: 30, height: 24)
        .help("advanced.jpegBackground.help")
        .accessibilityLabel("advanced.jpegBackground.title")
        Text(preferencesStore.preferences.jpegBackgroundColor.hexString)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 10)
    }
    .padding(.horizontal, 14)
    .background(.quinary.opacity(0.35))
    .overlay {
      Rectangle()
        .stroke(.quaternary, lineWidth: 1)
    }
    .padding(.bottom, 12)
  }

  private var actionBar: some View {
    VStack(spacing: 0) {
      if viewModel.isProcessing {
        ProgressView(value: viewModel.progress.fraction) {
          Text(
            String.localizedStringWithFormat(
              String(localized: "processing.progress.format"),
              viewModel.progress.completed,
              viewModel.progress.total
            ))
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
      }

      HStack(spacing: 12) {
        Label(statusText, systemImage: statusSystemImage)
          .foregroundStyle(viewModel.selectedImages.isEmpty ? .secondary : .primary)

        Spacer()

        if viewModel.isProcessing {
          Button("processing.cancel") {
            viewModel.cancelProcessing()
          }
        } else {
          Button("selection.clear") {
            viewModel.clearSelection()
          }
          .disabled(viewModel.selectedImages.isEmpty)
        }

        Button("processing.start") {
          if preferencesStore.preferences.overwritesOriginal {
            isShowingOverwriteConfirmation = true
          } else {
            startProcessing()
          }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!viewModel.canProcess)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 14)
    }
  }

  private var selectionList: some View {
    VStack(spacing: 0) {
      List {
        ForEach(viewModel.selectedImages) { image in
          HStack {
            Image(systemName: "photo")
              .foregroundStyle(.secondary)
            Text(image.url.lastPathComponent)
            Spacer()
            Button {
              viewModel.removeImage(image)
            } label: {
              Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .help("selection.remove.help")
            .accessibilityLabel("selection.remove.help")
          }
        }
      }

      Divider()

      HStack {
        Button("selection.clear") {
          viewModel.clearSelection()
        }
        Spacer()
        Button("action.done") {
          viewModel.isShowingSelectionList = false
        }
        .keyboardShortcut(.defaultAction)
      }
      .padding()
    }
    .frame(width: 520, height: 360)
  }

  private var resultsView: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label(
        "results.title",
        systemImage: viewModel.failedResults.isEmpty
          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
      )
      .font(.title2.weight(.semibold))
      .foregroundStyle(viewModel.failedResults.isEmpty ? .green : .orange)

      Text(
        String.localizedStringWithFormat(
          String(localized: "results.summary.format"),
          viewModel.successfulResults.count,
          viewModel.failedResults.count
        ))

      if !viewModel.failedResults.isEmpty {
        List(viewModel.failedResults) { result in
          VStack(alignment: .leading, spacing: 3) {
            Text(result.sourceURL.lastPathComponent)
              .fontWeight(.medium)
            Text(result.message ?? String(localized: "processing.error.generic"))
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .frame(minHeight: 140)
      }

      HStack {
        if !viewModel.successfulResults.isEmpty {
          Button("results.reveal") {
            viewModel.revealSuccessfulOutputs()
          }
        }
        Spacer()
        Button("results.clearList") {
          viewModel.clearSelectionAndDismissResults()
        }
        .help("results.clearList.help")
        .accessibilityHint("results.clearList.help")

        Button("action.done") {
          viewModel.isShowingResults = false
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 520)
    .frame(minHeight: 220)
  }

  private func dimensionField(
    title: LocalizedStringKey,
    value: Binding<Int>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.callout)
      HStack(spacing: 6) {
        TextField(title, value: value, format: .number)
          .frame(width: 120)
        Text("dimensions.pixels.short")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func settingsToggleRow(
    title: LocalizedStringKey,
    isOn: Binding<Bool>,
    description: LocalizedStringKey,
    isEnabled: Bool = true
  ) -> some View {
    HStack(spacing: 14) {
      Text(title)
        .font(.headline)
        .frame(width: 160, alignment: .leading)
      Toggle(title, isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
      Text(description)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.vertical, 14)
    .disabled(!isEnabled)
  }

  private var widthBinding: Binding<Int> {
    Binding {
      preferencesStore.preferences.width
    } set: { value in
      var preferences = preferencesStore.preferences
      preferences.updateWidth(value)
      preferencesStore.preferences = preferences
    }
  }

  private var heightBinding: Binding<Int> {
    Binding {
      preferencesStore.preferences.height
    } set: { value in
      var preferences = preferencesStore.preferences
      preferences.updateHeight(value)
      preferencesStore.preferences = preferences
    }
  }

  private var jpegBackgroundColorBinding: Binding<NSColor> {
    Binding {
      let color = preferencesStore.preferences.jpegBackgroundColor
      return NSColor(
        srgbRed: color.red,
        green: color.green,
        blue: color.blue,
        alpha: 1
      )
    } set: { color in
      let convertedColor = color.usingColorSpace(.sRGB) ?? .white
      preferencesStore.preferences.jpegBackgroundColor = RGBColor(
        red: Double(convertedColor.redComponent),
        green: Double(convertedColor.greenComponent),
        blue: Double(convertedColor.blueComponent)
      )
    }
  }

  private var manualQualityText: String {
    return "\(Int((preferencesStore.preferences.quality * 100).rounded()))%"
  }

  private var selectedOutputDirectoryDisplayPath: String? {
    guard let path = preferencesStore.preferences.outputDirectory?.path else {
      return nil
    }
    return (path as NSString).abbreviatingWithTildeInPath
  }

  private var preferredWindowHeight: CGFloat {
    let contentHeight: CGFloat = isAdvancedExpanded ? 840 : 650
    let processingHeight: CGFloat = viewModel.isProcessing ? 48 : 0
    return contentHeight + processingHeight + 38
  }

  private var suffixExample: String {
    let suffix = ImageResizeService.sanitizedSuffix(
      preferencesStore.preferences.filenameSuffix
    )
    return String.localizedStringWithFormat(
      String(localized: "advanced.suffix.example.format"),
      "\(String(localized: "advanced.suffix.sampleBase"))\(suffix).\(preferencesStore.preferences.outputFormat.fileExtension)"
    )
  }

  private var statusText: LocalizedStringKey {
    if viewModel.isCancelling {
      return "processing.status.cancelling"
    }
    if viewModel.isProcessing {
      return "processing.status.active"
    }
    if viewModel.selectedImages.isEmpty {
      return "processing.status.empty"
    }
    return preferencesStore.preferences.allowsUpscaling
      ? "processing.status.ready"
      : "processing.status.readyNoUpscale"
  }

  private var statusSystemImage: String {
    if viewModel.isProcessing {
      return "arrow.triangle.2.circlepath"
    }
    return viewModel.selectedImages.isEmpty ? "info.circle" : "checkmark.circle.fill"
  }

  private var appearanceHelpText: String {
    switch preferencesStore.preferences.appearanceMode {
    case .system:
      return String(localized: "appearance.system.help")
    case .light:
      return String(localized: "appearance.light.help")
    case .dark:
      return String(localized: "appearance.dark.help")
    }
  }

  private var aspectRatioHelpText: String {
    preferencesStore.preferences.preservesAspectRatio
      ? String(localized: "dimensions.aspect.locked.help")
      : String(localized: "dimensions.aspect.unlocked.help")
  }

  private var qualityModeSystemImage: String {
    preferencesStore.preferences.qualityMode == .automatic
      ? "gearshape.fill"
      : "slider.horizontal.3"
  }

  private var qualityModeHelpText: String {
    preferencesStore.preferences.qualityMode == .automatic
      ? String(localized: "quality.mode.automatic.help")
      : String(localized: "quality.mode.manual.help")
  }

  private var advancedToggleHelpText: String {
    isAdvancedExpanded
      ? String(localized: "advanced.collapse.help")
      : String(localized: "advanced.expand.help")
  }

  private func toggleAdvancedSection() {
    if isAdvancedExpanded {
      withAnimation(.easeOut(duration: 0.16)) {
        isAdvancedContentVisible = false
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
        guard !isAdvancedContentVisible else { return }
        isAdvancedExpanded = false
      }
      return
    }

    isAdvancedExpanded = true
    isAdvancedContentVisible = false
    DispatchQueue.main.async {
      withAnimation(.easeIn(duration: 0.18)) {
        isAdvancedContentVisible = true
      }
    }
  }

  private func presetAccessibilityName(_ preset: ResizePreset) -> String {
    guard let dimensions = preset.dimensions else {
      return String(localized: "preset.custom")
    }
    return "\(dimensions.width) × \(dimensions.height)"
  }

  private func selectPreset(_ preset: ResizePreset) {
    var preferences = preferencesStore.preferences
    preferences.selectPreset(preset)
    preferencesStore.preferences = preferences
  }

  private func cycleAppearance() {
    preferencesStore.preferences.appearanceMode = preferencesStore.preferences.appearanceMode.next
  }

  private func dismissActiveModal() {
    if isShowingOverwriteConfirmation {
      isShowingOverwriteConfirmation = false
    } else if viewModel.isShowingResults {
      viewModel.isShowingResults = false
    } else if viewModel.isShowingSelectionList {
      viewModel.isShowingSelectionList = false
    } else if isShowingAbout {
      isShowingAbout = false
    }
  }

  private func closeMainWindow() {
    mainWindow?.performClose(nil)
  }

  private func minimizeMainWindow() {
    mainWindow?.miniaturize(nil)
  }

  private func chooseImages() {
    let panel = NativeOpenPanelFactory.makeImagePanel()
    NSApplication.shared.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK else { return }
    viewModel.addImages(from: panel.urls)
  }

  private func chooseOutputDirectory() {
    let initialDirectory = preferencesStore.preferences.outputDirectory?.resolvedURL
    let panel = NativeOpenPanelFactory.makeOutputDirectoryPanel(
      initialDirectory: initialDirectory
    )
    NSApplication.shared.activate(ignoringOtherApps: true)
    guard panel.runModal() == .OK, let directoryURL = panel.url else { return }
    preferencesStore.preferences.selectOutputDirectory(directoryURL)
  }

  private var mainWindow: NSWindow? {
    NSApplication.shared.windows.first {
      $0.identifier == RadiuslessWindowConfiguration.identifier
    }
  }

  private func startProcessing() {
    preferencesStore.flush()
    viewModel.startProcessing(preferences: preferencesStore.preferences)
  }
}

enum NativeOpenPanelFactory {
  @MainActor
  static func makeImagePanel() -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.title = String(localized: "selection.choose")
    panel.prompt = String(localized: "selection.choose")
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.resolvesAliases = true
    panel.allowedContentTypes = [.image]
    return panel
  }

  @MainActor
  static func makeOutputDirectoryPanel(initialDirectory: URL?) -> NSOpenPanel {
    let panel = NSOpenPanel()
    panel.title = String(localized: "advanced.location.title")
    panel.prompt = String(localized: "advanced.location.change")
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.directoryURL = initialDirectory
    return panel
  }
}

struct ColorPanelPositioning {
  static func origin(
    anchorFrame: CGRect,
    panelSize: CGSize,
    visibleFrame: CGRect,
    spacing: CGFloat = 8,
    trailingClearance: CGFloat = 0
  ) -> CGPoint {
    let rightOriginX = anchorFrame.maxX + spacing + trailingClearance
    let leftOriginX = anchorFrame.minX - spacing - panelSize.width
    let preferredOriginX =
      rightOriginX + panelSize.width <= visibleFrame.maxX
      ? rightOriginX
      : leftOriginX
    let maximumOriginX = max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
    let maximumOriginY = max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)

    return CGPoint(
      x: min(max(preferredOriginX, visibleFrame.minX), maximumOriginX),
      y: min(
        max(anchorFrame.maxY - panelSize.height, visibleFrame.minY),
        maximumOriginY
      )
    )
  }
}

private struct AnchoredColorWell: NSViewRepresentable {
  @Binding var color: NSColor
  let accessibilityLabel: String
  let panelTrailingClearance: CGFloat

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> PositionedColorWell {
    let colorWell = PositionedColorWell()
    colorWell.color = color
    colorWell.isBordered = true
    colorWell.panelTrailingClearance = panelTrailingClearance
    colorWell.target = context.coordinator
    colorWell.action = #selector(Coordinator.handleColorChange(_:))
    colorWell.setAccessibilityLabel(accessibilityLabel)
    return colorWell
  }

  func updateNSView(_ colorWell: PositionedColorWell, context: Context) {
    context.coordinator.parent = self
    colorWell.setAccessibilityLabel(accessibilityLabel)
    colorWell.panelTrailingClearance = panelTrailingClearance
    guard colorWell.color != color else { return }
    colorWell.color = color
  }

  final class Coordinator: NSObject {
    var parent: AnchoredColorWell

    init(parent: AnchoredColorWell) {
      self.parent = parent
    }

    @objc func handleColorChange(_ sender: NSColorWell) {
      parent.color = sender.color
    }
  }
}

private final class PositionedColorWell: NSColorWell {
  var panelTrailingClearance: CGFloat = 0

  override func activate(_ exclusive: Bool) {
    let colorPanel = NSColorPanel.shared
    colorPanel.showsAlpha = false
    colorPanel.level = .floating
    position(colorPanel)
    super.activate(exclusive)

    DispatchQueue.main.async { [weak self, weak colorPanel] in
      guard let self, let colorPanel else { return }
      self.position(colorPanel)
    }
  }

  private func position(_ colorPanel: NSColorPanel) {
    guard let window else { return }
    let anchorFrame = window.convertToScreen(convert(bounds, to: nil))
    let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    guard let visibleFrame else { return }

    let origin = ColorPanelPositioning.origin(
      anchorFrame: anchorFrame,
      panelSize: colorPanel.frame.size,
      visibleFrame: visibleFrame,
      trailingClearance: panelTrailingClearance
    )
    colorPanel.setFrameOrigin(origin)
  }
}

private struct PresetButtonStyle: ButtonStyle {
  let isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(isSelected ? Color.white : Color.primary)
      .background(
        isSelected
          ? Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1)
          : Color.clear
      )
      .overlay(alignment: .trailing) {
        Divider()
      }
  }
}

struct ContentViewPreviews: PreviewProvider {
  static var previews: some View {
    ContentView()
      .environmentObject(PreferencesStore())
      .environmentObject(MainViewModel())
  }
}
