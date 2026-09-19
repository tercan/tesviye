import AppKit
import Combine
import Foundation
import OSLog
import UniformTypeIdentifiers

@MainActor
final class MainViewModel: ObservableObject {
  @Published private(set) var selectedImages: [SelectedImage] = []
  @Published private(set) var progress = BatchProgress()
  @Published private(set) var results: [ResizeResult] = []
  @Published private(set) var isProcessing = false
  @Published private(set) var isCancelling = false
  @Published var isShowingSelectionList = false
  @Published var isShowingResults = false

  private var processingTask: Task<Void, Never>?
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "gupse.tesviye",
    category: "ImageProcessing"
  )

  var canProcess: Bool {
    !selectedImages.isEmpty && !isProcessing
  }

  var selectionTitle: String {
    guard !selectedImages.isEmpty else {
      return String(localized: "selection.empty.title")
    }

    return String.localizedStringWithFormat(
      String(localized: "selection.count"),
      selectedImages.count
    )
  }

  var selectionSubtitle: String {
    guard !selectedImages.isEmpty else {
      return String(localized: "selection.empty.subtitle")
    }

    let totalBytes = selectedImages.reduce(Int64(0)) { $0 + $1.byteCount }
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return String.localizedStringWithFormat(
      String(localized: "selection.totalSize"),
      formatter.string(fromByteCount: totalBytes)
    )
  }

  var successfulResults: [ResizeResult] {
    results.filter { $0.status == .success }
  }

  var failedResults: [ResizeResult] {
    results.filter { $0.status == .failure }
  }

  var resultSummary: BatchResultSummary {
    BatchResultSummary(results: results, total: progress.total)
  }

  func addImages(from urls: [URL]) {
    var knownURLs = Set(selectedImages.map { $0.url.standardizedFileURL })
    let newImages = urls.compactMap { url -> SelectedImage? in
      let standardizedURL = url.standardizedFileURL
      guard
        knownURLs.insert(standardizedURL).inserted,
        Self.isSupportedImage(standardizedURL)
      else {
        return nil
      }

      let didAccessSecurityScope = standardizedURL.startAccessingSecurityScopedResource()
      defer {
        if didAccessSecurityScope {
          standardizedURL.stopAccessingSecurityScopedResource()
        }
      }

      let values = try? standardizedURL.resourceValues(forKeys: [.fileSizeKey])
      return SelectedImage(
        url: standardizedURL,
        byteCount: Int64(values?.fileSize ?? 0)
      )
    }

    selectedImages.append(contentsOf: newImages)
  }

  func addImagesFromExternalOpen(_ urls: [URL]) {
    guard !isProcessing else { return }
    isShowingResults = false
    isShowingSelectionList = false
    addImages(from: urls)
  }

  func removeImage(_ image: SelectedImage) {
    selectedImages.removeAll { $0.id == image.id }
  }

  func clearSelection() {
    guard !isProcessing else { return }
    selectedImages.removeAll()
    results.removeAll()
  }

  func clearSelectionAndDismissResults() {
    guard !isProcessing else { return }
    clearSelection()
    isShowingResults = false
  }

  func startProcessing(preferences: UserPreferences) {
    guard canProcess else { return }

    let images = selectedImages
    let configuration = ResizeConfiguration(preferences: preferences)
    progress = BatchProgress(completed: 0, total: images.count)
    results = []
    isProcessing = true
    isCancelling = false

    processingTask = Task { [weak self] in
      guard let self else { return }

      for image in images {
        if Task.isCancelled {
          break
        }

        do {
          let outputURL = try await Task.detached(priority: .userInitiated) {
            try ImageResizeService.resize(
              sourceURL: image.url,
              configuration: configuration
            )
          }.value

          results.append(
            ResizeResult(
              sourceURL: image.url,
              outputURL: outputURL,
              status: .success,
              message: nil
            )
          )
        } catch {
          if Task.isCancelled {
            break
          }

          results.append(
            ResizeResult(
              sourceURL: image.url,
              outputURL: nil,
              status: .failure,
              message: localizedMessage(for: error)
            )
          )
          logger.error(
            "Image processing failed for \(image.url.lastPathComponent, privacy: .public): \(String(reflecting: error), privacy: .public)"
          )
        }

        progress.completed += 1
      }

      finishProcessing(showsResults: !results.isEmpty)
    }
  }

  func cancelProcessing() {
    processingTask?.cancel()
    isCancelling = processingTask != nil
  }

  func cancelProcessingAndWait() async {
    let task = processingTask
    task?.cancel()
    isCancelling = task != nil
    await task?.value
  }

  func revealSuccessfulOutputs() {
    let urls = successfulResults.compactMap(\.outputURL)
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
  }

  private func localizedMessage(for error: Error) -> String {
    switch error {
    case ImageResizeError.cannotReadSource:
      return String(localized: "processing.error.cannotRead")
    case ImageResizeError.invalidDimensions:
      return String(localized: "processing.error.invalidDimensions")
    case ImageResizeError.unsupportedOutputFormat:
      return String(localized: "processing.error.unsupportedFormat")
    case ImageResizeError.outputFolderNotWritable,
      ImageResizeError.cannotCreateDestination,
      ImageResizeError.cannotFinalizeDestination,
      ImageResizeError.outputInstallationFailed:
      return String(localized: "processing.error.cannotWrite")
    case ImageResizeError.outputVerificationFailed:
      return String(localized: "processing.error.verification")
    default:
      return String(localized: "processing.error.generic")
    }
  }

  private func finishProcessing(showsResults: Bool) {
    isProcessing = false
    isCancelling = false
    processingTask = nil
    isShowingResults = showsResults
  }

  private static func isSupportedImage(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else {
      return false
    }
    return type.conforms(to: .image)
  }
}
