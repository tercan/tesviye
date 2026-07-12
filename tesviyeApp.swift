import AppKit
import SwiftUI

@main
struct TesviyeApp: App {
  @NSApplicationDelegateAdaptor(ExternalImageOpenCoordinator.self)
  private var externalImageOpenCoordinator
  @StateObject private var preferencesStore = PreferencesStore()
  @StateObject private var mainViewModel = MainViewModel()

  var body: some Scene {
    Window("app.name", id: "main") {
      ContentView()
        .environmentObject(preferencesStore)
        .environmentObject(mainViewModel)
        .preferredColorScheme(preferredColorScheme)
        .background(RadiuslessWindowAccessor())
        .onAppear {
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
    .defaultSize(width: 740, height: 688)
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

    MenuBarExtra("app.name", systemImage: "photo.badge.arrow.down") {
      MenuBarContent(
        preferencesStore: preferencesStore,
        mainViewModel: mainViewModel,
        onQuit: requestQuit
      )
    }
    .menuBarExtraStyle(.menu)
  }

  private var preferredColorScheme: ColorScheme? {
    switch preferencesStore.preferences.appearanceMode {
    case .system:
      return nil
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

  @MainActor
  private func requestQuit() {
    if mainViewModel.isProcessing {
      let alert = NSAlert()
      alert.alertStyle = .warning
      alert.messageText = String(localized: "quit.processing.title")
      alert.informativeText = String(localized: "quit.processing.message")
      alert.addButton(withTitle: String(localized: "quit.processing.confirm"))
      alert.addButton(withTitle: String(localized: "action.cancel"))

      guard alert.runModal() == .alertFirstButtonReturn else {
        return
      }

      Task {
        await mainViewModel.cancelProcessingAndWait()
        preferencesStore.flush()
        NSApplication.shared.terminate(nil)
      }
      return
    }

    preferencesStore.flush()
    NSApplication.shared.terminate(nil)
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

private struct MenuBarContent: View {
  @Environment(\.openWindow) private var openWindow
  @ObservedObject var preferencesStore: PreferencesStore
  @ObservedObject var mainViewModel: MainViewModel
  let onQuit: @MainActor () -> Void

  var body: some View {
    Button("menu.open") {
      openWindow(id: "main")
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    if mainViewModel.isProcessing {
      Divider()

      Text(
        String.localizedStringWithFormat(
          String(localized: "processing.progress.format"),
          mainViewModel.progress.completed,
          mainViewModel.progress.total
        ))

      Button("processing.cancel") {
        mainViewModel.cancelProcessing()
      }
    }

    Divider()

    Button("menu.quit") {
      onQuit()
    }
  }
}
