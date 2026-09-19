import AppKit
import Combine
import SwiftUI

@main
struct TesviyeApp: App {
  @NSApplicationDelegateAdaptor(ExternalImageOpenCoordinator.self)
  private var externalImageOpenCoordinator
  @StateObject private var preferencesStore = PreferencesStore()
  @StateObject private var mainViewModel = MainViewModel()
  @StateObject private var terminationCoordinator = ApplicationTerminationCoordinator()

  var body: some Scene {
    Window("app.name", id: "main") {
      ContentView(onQuit: requestQuit)
        .environmentObject(preferencesStore)
        .environmentObject(mainViewModel)
        .preferredColorScheme(preferredColorScheme)
        .background(RadiuslessWindowAccessor())
        .onAppear {
          configureTermination()
          importPendingExternalImages()
        }
        .onChange(of: externalImageOpenCoordinator.pendingURLs) { _, urls in
          guard !urls.isEmpty else { return }
          importPendingExternalImages()
        }
        .onChange(of: mainViewModel.isProcessing) { _, isProcessing in
          guard !isProcessing else { return }
          importPendingExternalImages()
        }
        .onOpenURL { url in
          externalImageOpenCoordinator.handleExternalOpen([url])
          importPendingExternalImages()
        }
    }
    .windowResizability(.contentSize)
    .windowStyle(.hiddenTitleBar)
    .commands {
      CommandGroup(replacing: .appTermination) {
        Button("menu.quit") {
          requestQuit()
        }
        .keyboardShortcut("q")
      }
    }
  }

  private var preferredColorScheme: ColorScheme? {
    switch preferencesStore.preferences.appearanceMode {
    case .light:
      return .light
    case .dark:
      return .dark
    }
  }

  @MainActor
  private func importPendingExternalImages() {
    guard !mainViewModel.isProcessing else { return }
    let urls = externalImageOpenCoordinator.drainPendingURLs()
    guard !urls.isEmpty else { return }
    mainViewModel.addImagesFromExternalOpen(urls)
  }

  private func requestQuit() {
    NSApplication.shared.terminate(nil)
  }

  private func configureTermination() {
    externalImageOpenCoordinator.terminationHandler = {
      terminationCoordinator.shouldTerminate(
        viewModel: mainViewModel,
        preferencesStore: preferencesStore,
        confirmCancellation: {
          let alert = NSAlert()
          alert.alertStyle = .warning
          alert.messageText = String(localized: "quit.processing.title")
          alert.informativeText = String(localized: "quit.processing.message")
          alert.addButton(withTitle: String(localized: "quit.processing.confirm"))
          alert.addButton(withTitle: String(localized: "action.cancel"))
          return alert.runModal() == .alertFirstButtonReturn
        },
        reply: { NSApplication.shared.reply(toApplicationShouldTerminate: $0) }
      )
    }
  }
}

@MainActor
final class ApplicationTerminationCoordinator: ObservableObject {
  private var isWaitingForProcessing = false

  func shouldTerminate(
    viewModel: MainViewModel,
    preferencesStore: PreferencesStore,
    confirmCancellation: () -> Bool,
    reply: @escaping (Bool) -> Void
  ) -> NSApplication.TerminateReply {
    guard !isWaitingForProcessing else { return .terminateLater }
    guard viewModel.isProcessing else {
      preferencesStore.flush()
      return .terminateNow
    }
    guard confirmCancellation() else { return .terminateCancel }
    isWaitingForProcessing = true
    Task {
      await viewModel.cancelProcessingAndWait()
      preferencesStore.flush()
      reply(true)
    }
    return .terminateLater
  }
}

struct RadiuslessWindowConfiguration {
  static let identifier = NSUserInterfaceItemIdentifier("TesviyeMainWindow")

  @MainActor
  static func apply(to window: NSWindow) {
    let styleMask: NSWindow.StyleMask = [.borderless, .closable, .miniaturizable]
    if window.styleMask != styleMask {
      window.styleMask = styleMask
    }
    window.identifier = identifier
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.isMovableByWindowBackground = true
    window.hasShadow = true
    window.isOpaque = true
    window.backgroundColor = .windowBackgroundColor

    guard let contentView = window.contentView else { return }
    contentView.wantsLayer = true
    contentView.layer?.cornerRadius = 0
    contentView.layer?.masksToBounds = true
  }
}

struct WindowDragArea: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowDragView {
    WindowDragView()
  }

  func updateNSView(_ nsView: WindowDragView, context: Context) {}
}

final class WindowDragView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}

private struct RadiuslessWindowAccessor: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      guard let window = view.window else { return }
      RadiuslessWindowConfiguration.apply(to: window)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    guard let window = nsView.window else { return }
    RadiuslessWindowConfiguration.apply(to: window)
  }
}
