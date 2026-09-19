import AppKit
import Combine
import Foundation

@MainActor
final class ExternalImageOpenCoordinator: NSObject, NSApplicationDelegate, ObservableObject {
  @Published private(set) var pendingURLs: [URL] = []
  var terminationHandler: (() -> NSApplication.TerminateReply)?

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    terminationHandler?() ?? .terminateNow
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    handleExternalOpen(urls)

    application.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
  }

  func handleExternalOpen(_ urls: [URL]) {
    let imageURLs = urls.flatMap { url -> [URL] in
      if let payloadURLs = FinderImportPayload.fileURLs(from: url) {
        return payloadURLs
      }
      return url.isFileURL ? [url] : []
    }
    enqueue(imageURLs)
  }

  func enqueue(_ urls: [URL]) {
    var knownURLs = Set(pendingURLs.map(\.standardizedFileURL))
    for url in urls {
      let standardizedURL = url.standardizedFileURL
      guard knownURLs.insert(standardizedURL).inserted else { continue }
      pendingURLs.append(standardizedURL)
    }
  }

  func drainPendingURLs() -> [URL] {
    let urls = pendingURLs
    pendingURLs.removeAll()
    return urls
  }
}
