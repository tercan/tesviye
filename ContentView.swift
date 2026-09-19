import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @EnvironmentObject private var preferencesStore: PreferencesStore
  @EnvironmentObject private var viewModel: MainViewModel
  @State private var isShowingAbout = false
  @State private var isShowingOverwriteConfirmation = false

  let onQuit: () -> Void

  init(onQuit: @escaping () -> Void = { NSApplication.shared.terminate(nil) }) {
    self.onQuit = onQuit
  }

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
          advancedSettingsContent
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 12)

        Divider()
        actionBar
      }
      .disabled(isAppModalPresented)
      .accessibilityHidden(isAppModalPresented)

      if isAppModalPresented {
        appModalLayer
      }
    }
    .frame(width: 740)
    .fixedSize(horizontal: false, vertical: true)
    .background(Color(nsColor: .windowBackgroundColor))
    .dropDestination(for: URL.self) { urls, _ in
      viewModel.addImages(from: urls)
      return true
    }
  }

  private var windowHeader: some View {
    HStack(spacing: 8) {
      Button {
        onQuit()
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

      WindowDragArea()
        .overlay(alignment: .leading) {
          Text("app.name")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

      Button {
        preferencesStore.preferences.appearanceMode =
          preferencesStore.preferences.appearanceMode == .light ? .dark : .light
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
    HStack(spacing: 0) {
      ForEach(ResizePreset.visiblePresets) { preset in
        Button {
          selectPreset(preset)
        } label: {
          Text(presetAccessibilityName(preset))
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(
          PresetButtonStyle(isSelected: preferencesStore.preferences.selectedPreset == preset)
        )
        .help(presetAccessibilityName(preset))
        .accessibilityLabel(presetAccessibilityName(preset))
        .accessibilityAddTraits(
          preferencesStore.preferences.selectedPreset == preset ? .isSelected : [])
      }
    }
    .overlay {
      Rectangle().stroke(.quaternary, lineWidth: 1).allowsHitTesting(false)
    }
    .padding(.vertical, 14)
  }

  private var dimensionsSection: some View {
    HStack(alignment: .bottom, spacing: 12) {
      Text("dimensions.title")
        .font(.headline)
        .frame(width: 190, alignment: .leading)
        .padding(.bottom, 7)

      dimensionField(
        title: "dimensions.width",
        value: widthBinding
      )
      .disabled(preferencesStore.preferences.selectedPreset != .custom)

      Button {
        var preferences = preferencesStore.preferences
        preferences.swapDimensions()
        preferencesStore.preferences = preferences
      } label: {
        Image(systemName: "arrow.left.arrow.right")
          .frame(width: 26, height: 26)
      }
      .disabled(preferencesStore.preferences.selectedPreset != .custom)
      .help("dimensions.swap.help")
      .accessibilityLabel("dimensions.swap.help")
      .padding(.bottom, 1)

      dimensionField(
        title: "dimensions.height",
        value: heightBinding
      )
      .disabled(preferencesStore.preferences.selectedPreset != .custom)

      Button {
        preferencesStore.preferences.preservesAspectRatio.toggle()
      } label: {
        Image(
          systemName: preferencesStore.preferences.preservesAspectRatio ? "lock.fill" : "lock.open"
        )
        .frame(width: 26, height: 26)
      }
      .disabled(preferencesStore.preferences.selectedPreset == .original)
      .help(aspectRatioHelpText)
      .accessibilityLabel(aspectRatioHelpText)
      .padding(.bottom, 1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 16)
  }

  private var behaviorSection: some View {
    VStack(spacing: 0) {
      settingsToggleRow(
        title: "upscale.title",
        isOn: $preferencesStore.preferences.allowsUpscaling,
        description: preferencesStore.preferences.selectedPreset == .original
          ? "upscale.original.description"
          : preferencesStore.preferences.allowsUpscaling
            ? "upscale.on.description"
            : "upscale.off.description",
        isEnabled: preferencesStore.preferences.selectedPreset != .original
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

  private var advancedSettingsContent: some View {
    VStack(spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text("advanced.suffix.title")
          .font(.headline)
          .frame(width: 190, alignment: .leading)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Toggle(
              "advanced.suffix.enabled", isOn: $preferencesStore.preferences.usesFilenameSuffix
            )
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help("advanced.suffix.enabled.help")
            .accessibilityLabel("advanced.suffix.enabled")
            TextField(
              "advanced.suffix.placeholder",
              text: $preferencesStore.preferences.filenameSuffix
            )
            .disabled(!preferencesStore.preferences.usesFilenameSuffix)
            .accessibilityLabel("advanced.suffix.title")
          }
          Text(suffixExample)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 10)

      Divider()

      HStack {
        Text("advanced.location.title")
          .font(.headline)
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

      HStack(spacing: 12) {
        Toggle("advanced.metadata.preserve", isOn: $preferencesStore.preferences.preservesMetadata)
          .toggleStyle(.checkbox)
          .frame(maxWidth: .infinity, alignment: .leading)

        Divider().frame(height: 28)

        Toggle(
          "advanced.metadata.removeLocation",
          isOn: $preferencesStore.preferences.removesLocationMetadata
        )
        .toggleStyle(.checkbox)
        .disabled(!preferencesStore.preferences.preservesMetadata)
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider().frame(height: 28)

        HStack(spacing: 8) {
          Text("advanced.jpegBackground.title")
          Spacer(minLength: 0)
          AnchoredColorWell(
            color: jpegBackgroundColorBinding,
            accessibilityLabel: String(localized: "advanced.jpegBackground.title"),
            panelTrailingClearance: 70
          )
          .frame(width: 30, height: 24)
          .help("advanced.jpegBackground.help")
          .accessibilityLabel("advanced.jpegBackground.title")
          Text(preferencesStore.preferences.jpegBackgroundColor.hexString)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .disabled(preferencesStore.preferences.outputFormat != .jpeg)
        .frame(maxWidth: .infinity)
      }
      .font(.callout)
      .padding(.vertical, 14)
    }
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
    ProcessingResultsView(
      summary: viewModel.resultSummary,
      failedResults: viewModel.failedResults,
      onReveal: viewModel.revealSuccessfulOutputs,
      onClear: viewModel.clearSelectionAndDismissResults,
      onDismiss: { viewModel.isShowingResults = false }
    )
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

  private var suffixExample: String {
    let suffix = ImageResizeService.sanitizedSuffix(
      preferencesStore.preferences.effectiveFilenameSuffix
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
    if preferencesStore.preferences.selectedPreset == .original {
      return "processing.status.original"
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
    preferencesStore.preferences.appearanceMode == .light
      ? String(localized: "appearance.light.help") : String(localized: "appearance.dark.help")
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

  private func presetAccessibilityName(_ preset: ResizePreset) -> String {
    if preset == .original { return String(localized: "preset.original") }
    guard let dimensions = preset.dimensions else { return String(localized: "preset.custom") }
    return "\(dimensions.width) × \(dimensions.height)"
  }

  private func selectPreset(_ preset: ResizePreset) {
    var preferences = preferencesStore.preferences
    preferences.selectPreset(preset)
    preferencesStore.preferences = preferences
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

struct ProcessingResultsView: View {
  let summary: BatchResultSummary
  let failedResults: [ResizeResult]
  let onReveal: () -> Void
  let onClear: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .top, spacing: 16) {
          Image(systemName: statusIcon)
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(summary.status == .completed ? Color.accentColor : Color.orange)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 10) {
            Text(titleKey)
              .font(.title3.weight(.semibold))
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityAddTraits(.isHeader)

            if summary.successCount > 0 {
              Text(
                String.localizedStringWithFormat(
                  String(localized: "results.success.format"), summary.successCount
                )
              )
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            if summary.failureCount > 0 {
              Text(
                String.localizedStringWithFormat(
                  String(localized: "results.failure.format"), summary.failureCount
                )
              )
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            if summary.remainingCount > 0 {
              Text(
                String.localizedStringWithFormat(
                  String(localized: "results.remaining.format"), summary.remainingCount
                )
              )
              .foregroundStyle(.secondary)
            }
          }
        }

        if !failedResults.isEmpty {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              ForEach(failedResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                  Text(result.sourceURL.lastPathComponent)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(result.sourceURL.lastPathComponent)
                  Text(result.message ?? String(localized: "processing.error.generic"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            .padding(12)
          }
          .frame(height: min(CGFloat(failedResults.count) * 76, 180))
          .background(.quinary)
        }

        HStack(spacing: 12) {
          if summary.successCount > 0 {
            Button(action: onReveal) {
              Label("results.reveal", systemImage: "folder")
                .padding(.vertical, 6)
            }
            .keyboardShortcut(.defaultAction)
          }
          Button(action: onClear) {
            Label("results.clearList", systemImage: "xmark")
              .padding(.vertical, 6)
          }
          .help("results.clearList.help")
          .accessibilityHint("results.clearList.help")
          Spacer(minLength: 0)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      .padding(24)

      Divider()

      HStack {
        Spacer()
        Button("action.done", action: onDismiss)
          .keyboardShortcut(.cancelAction)
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 14)
    }
    .frame(width: 560)
  }

  private var titleKey: LocalizedStringKey {
    switch summary.status {
    case .completed: return "results.title"
    case .completedWithErrors: return "results.partial.title"
    case .failed: return "results.failed.title"
    case .cancelled: return "results.cancelled.title"
    }
  }

  private var statusIcon: String {
    switch summary.status {
    case .completed: return "checkmark.circle"
    case .completedWithErrors, .failed: return "exclamationmark.triangle"
    case .cancelled: return "pause.circle"
    }
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
  @Environment(\.isEnabled) private var isEnabled
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
    colorWell.updateEnabledState(isEnabled)
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
    colorWell.updateEnabledState(isEnabled)
    guard colorWell.color != color else { return }
    colorWell.color = color
  }

  static func dismantleNSView(_ colorWell: PositionedColorWell, coordinator: Coordinator) {
    colorWell.dismissColorPanel()
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

final class PositionedColorWell: NSColorWell {
  var panelTrailingClearance: CGFloat = 0
  private var mouseMonitor: Any?
  private var notificationObservers: [NSObjectProtocol] = []

  func updateEnabledState(_ enabled: Bool) {
    isEnabled = enabled
    if !enabled {
      dismissColorPanel()
    }
  }

  override func activate(_ exclusive: Bool) {
    guard isEnabled else { return }
    let colorPanel = NSColorPanel.shared
    colorPanel.showsAlpha = false
    colorPanel.level = .floating
    position(colorPanel)
    super.activate(exclusive)
    startMonitoringDismissal()

    DispatchQueue.main.async { [weak self, weak colorPanel] in
      guard let self, self.isActive, let colorPanel else { return }
      self.position(colorPanel)
    }
  }

  override func deactivate() {
    stopMonitoringDismissal()
    super.deactivate()
  }

  func dismissColorPanel() {
    let ownsPanel = isActive
    deactivate()
    if ownsPanel {
      NSColorPanel.shared.orderOut(nil)
    }
  }

  func handleMouseDown(_ event: NSEvent) -> NSEvent? {
    guard isActive else { return event }
    let colorPanel = NSColorPanel.shared
    var eventWindow = event.window
    while let currentWindow = eventWindow {
      if currentWindow === colorPanel { return event }
      eventWindow = currentWindow.parent
    }

    let clicksColorWell =
      event.window === window
      && bounds.contains(convert(event.locationInWindow, from: nil))
    dismissColorPanel()
    // Consume the swatch click so it cannot immediately reopen the panel.
    return clicksColorWell ? nil : event
  }

  private func startMonitoringDismissal() {
    stopMonitoringDismissal()
    mouseMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      return self.handleMouseDown(event)
    }

    let center = NotificationCenter.default
    notificationObservers.append(
      center.addObserver(
        forName: NSApplication.didResignActiveNotification, object: NSApplication.shared,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.dismissColorPanel() }
      }
    )
    notificationObservers.append(
      center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) {
        [weak self] notification in
        MainActor.assumeIsolated {
          guard let self, let closedWindow = notification.object as? NSWindow else { return }
          if closedWindow === self.window || closedWindow === NSColorPanel.shared {
            self.dismissColorPanel()
          }
        }
      }
    )
  }

  private func stopMonitoringDismissal() {
    if let mouseMonitor {
      NSEvent.removeMonitor(mouseMonitor)
      self.mouseMonitor = nil
    }
    for observer in notificationObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    notificationObservers.removeAll()
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
