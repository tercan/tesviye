import SwiftUI

struct AboutView: View {
  let onDismiss: () -> Void

  init(onDismiss: @escaping () -> Void = {}) {
    self.onDismiss = onDismiss
  }

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.1"
  }

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "photo.badge.arrow.down")
        .font(.system(size: 44, weight: .regular))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      VStack(spacing: 3) {
        Text("app.name")
          .font(.title2.weight(.semibold))
        Text(
          String.localizedStringWithFormat(
            String(localized: "about.version.format"),
            version
          )
        )
        .foregroundStyle(.secondary)
      }

      Divider()

      Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
        GridRow {
          Text("about.developer.label")
            .foregroundStyle(.secondary)
          Text("about.developer.value")
        }
        GridRow {
          Text("about.website.label")
            .foregroundStyle(.secondary)
          Link(
            "about.website.value",
            destination: URL(string: "https://tercan.github.io/tesviye/")!
          )
        }
        GridRow {
          Text("about.license.label")
            .foregroundStyle(.secondary)
          Text("about.license.value")
        }
      }
      .font(.callout)

      Divider()

      Text("about.privacy")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      HStack {
        Text("about.copyright")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Button("action.done") {
          onDismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 440)
  }
}
