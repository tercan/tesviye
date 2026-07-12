import Foundation

enum FinderImportPayload {
  static let scheme = "gupse-tesviye"
  static let host = "finder-import"
  static let maximumFileCount = 100

  private static let payloadQueryName = "payload"

  static func makeURL(for fileURLs: [URL]) -> URL? {
    let normalizedURLs = normalizedFileURLs(fileURLs)
    guard !normalizedURLs.isEmpty, normalizedURLs.count <= maximumFileCount else {
      return nil
    }

    let paths = normalizedURLs.map(\.path)
    guard let payloadData = try? JSONEncoder().encode(paths) else {
      return nil
    }

    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.queryItems = [
      URLQueryItem(
        name: payloadQueryName,
        value: payloadData.base64EncodedString()
      )
    ]
    return components.url
  }

  static func fileURLs(from url: URL) -> [URL]? {
    guard
      url.scheme == scheme,
      url.host == host,
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let payload = components.queryItems?.first(where: { $0.name == payloadQueryName })?.value,
      let payloadData = Data(base64Encoded: payload),
      let paths = try? JSONDecoder().decode([String].self, from: payloadData),
      !paths.isEmpty,
      paths.count <= maximumFileCount,
      paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") })
    else {
      return nil
    }

    return normalizedFileURLs(paths.map { URL(fileURLWithPath: $0) })
  }

  private static func normalizedFileURLs(_ urls: [URL]) -> [URL] {
    var knownURLs = Set<URL>()
    return urls.compactMap { url in
      guard url.isFileURL else { return nil }
      let normalizedURL = url.standardizedFileURL
      return knownURLs.insert(normalizedURL).inserted ? normalizedURL : nil
    }
  }
}
