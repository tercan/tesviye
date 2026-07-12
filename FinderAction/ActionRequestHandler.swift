import AppKit
import Foundation
import UniformTypeIdentifiers

final class ActionRequestHandler: NSObject, NSExtensionRequestHandling {
  private let stateQueue = DispatchQueue(label: "gupse.tesviye.finder-action.state")

  func beginRequest(with context: NSExtensionContext) {
    let providers = context.inputItems
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
      .filter { provider in
        provider.registeredTypeIdentifiers.contains { identifier in
          UTType(identifier)?.conforms(to: .image) == true
        }
      }

    guard !providers.isEmpty else {
      context.cancelRequest(withError: Self.error(code: 1))
      return
    }

    let group = DispatchGroup()
    var indexedURLs: [Int: URL] = [:]
    var loadingError: Error?

    for (index, provider) in providers.enumerated() {
      group.enter()
      loadOriginalURL(from: provider) { [stateQueue] result in
        stateQueue.async {
          switch result {
          case .success(let url):
            indexedURLs[index] = url.standardizedFileURL
          case .failure(let error):
            loadingError = loadingError ?? error
          }
          group.leave()
        }
      }
    }

    group.notify(queue: stateQueue) {
      guard loadingError == nil, indexedURLs.count == providers.count else {
        context.cancelRequest(withError: loadingError ?? Self.error(code: 2))
        return
      }

      let imageURLs = indexedURLs.keys.sorted().compactMap { indexedURLs[$0] }
      self.openContainingApplication(with: imageURLs, context: context)
    }
  }

  private func loadOriginalURL(
    from provider: NSItemProvider,
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    let identifier =
      provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
      ? UTType.fileURL.identifier
      : provider.registeredTypeIdentifiers.first { registeredIdentifier in
        UTType(registeredIdentifier)?.conforms(to: .image) == true
      }

    guard let identifier else {
      completion(.failure(Self.error(code: 3)))
      return
    }

    provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, error in
      if let error {
        completion(.failure(error))
        return
      }
      guard let url = item as? URL, url.isFileURL else {
        completion(.failure(Self.error(code: 4)))
        return
      }
      completion(.success(url))
    }
  }

  private func openContainingApplication(
    with imageURLs: [URL],
    context: NSExtensionContext
  ) {
    guard
      let applicationURL = containingApplicationURL,
      let importURL = FinderImportPayload.makeURL(for: imageURLs)
    else {
      context.cancelRequest(withError: Self.error(code: 5))
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.open(
      [importURL],
      withApplicationAt: applicationURL,
      configuration: configuration
    ) { _, error in
      if let error {
        context.cancelRequest(withError: error)
      } else {
        context.completeRequest(returningItems: context.inputItems, completionHandler: nil)
      }
    }
  }

  private var containingApplicationURL: URL? {
    var url = Bundle.main.bundleURL
    for _ in 0..<3 {
      url.deleteLastPathComponent()
    }
    return url.pathExtension == "app" ? url : nil
  }

  private static func error(code: Int) -> NSError {
    NSError(domain: "gupse.tesviye.finder-action", code: code)
  }
}
