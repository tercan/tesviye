import CoreGraphics
import Foundation
import ImageIO
import libwebp

enum ImageResizeError: Error {
  case cannotReadSource
  case invalidDimensions
  case unsupportedOutputFormat
  case cannotCreateBitmap
  case outputFolderNotWritable
  case cannotCreateDestination
  case cannotFinalizeDestination
  case outputVerificationFailed
  case outputInstallationFailed(code: Int)
}

enum ImageResizeService {
  nonisolated private static let maximumPixelCount: Int64 = 200_000_000

  nonisolated static func resize(
    sourceURL: URL,
    configuration: ResizeConfiguration
  ) throws -> URL {
    let didAccessSecurityScope = sourceURL.startAccessingSecurityScopedResource()
    defer {
      if didAccessSecurityScope {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
      throw ImageResizeError.cannotReadSource
    }

    let outputDirectory =
      configuration.outputDirectory?.resolvedURL
      ?? sourceURL.deletingLastPathComponent()
    let didAccessOutputDirectory =
      configuration.outputDirectory != nil
      && outputDirectory.startAccessingSecurityScopedResource()
    defer {
      if didAccessOutputDirectory {
        outputDirectory.stopAccessingSecurityScopedResource()
      }
    }

    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(
        atPath: outputDirectory.path,
        isDirectory: &isDirectory
      ),
      isDirectory.boolValue,
      FileManager.default.isWritableFile(atPath: outputDirectory.path)
    else {
      throw ImageResizeError.outputFolderNotWritable
    }

    let sourceSize = try orientedSourceSize(from: imageSource)
    let targetSize = try targetSize(
      sourceSize: sourceSize,
      configuration: configuration
    )

    guard
      configuration.outputFormat == .webP
        || destinationTypeIsSupported(configuration.outputFormat.typeIdentifier)
    else {
      throw ImageResizeError.unsupportedOutputFormat
    }

    let resizedImage = try createResizedImage(
      from: imageSource,
      sourceSize: sourceSize,
      targetSize: targetSize,
      outputFormat: configuration.outputFormat,
      jpegBackgroundColor: configuration.jpegBackgroundColor
    )

    let temporaryURL =
      outputDirectory
      .appendingPathComponent(".tesviye-\(UUID().uuidString)")
      .appendingPathExtension(configuration.outputFormat.fileExtension)

    do {
      try write(
        resizedImage,
        source: imageSource,
        sourceURL: sourceURL,
        to: temporaryURL,
        configuration: configuration
      )
      try verifyOutput(at: temporaryURL, expectedSize: targetSize)

      return try installOutput(
        temporaryURL: temporaryURL,
        sourceURL: sourceURL,
        outputDirectory: outputDirectory,
        configuration: configuration
      )
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw error
    }
  }

  nonisolated static func sanitizedSuffix(_ suffix: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/\\:")
    let components = suffix.components(separatedBy: invalidCharacters)
    let sanitized = components.joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized
  }

  nonisolated static func uniqueOutputURL(
    sourceURL: URL,
    suffix: String,
    outputFormat: OutputFormat,
    outputDirectory: URL? = nil,
    fileManager: FileManager = .default
  ) -> URL {
    let directory = outputDirectory ?? sourceURL.deletingLastPathComponent()
    let basename = sourceURL.deletingPathExtension().lastPathComponent
    let sanitized = sanitizedSuffix(suffix)
    let proposedURL =
      directory
      .appendingPathComponent("\(basename)\(sanitized)")
      .appendingPathExtension(outputFormat.fileExtension)

    guard fileManager.fileExists(atPath: proposedURL.path) else {
      return proposedURL
    }

    var index = 1
    while true {
      let candidate =
        directory
        .appendingPathComponent("\(basename)\(sanitized)-\(index)")
        .appendingPathExtension(outputFormat.fileExtension)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }

  private nonisolated static func orientedSourceSize(
    from source: CGImageSource
  ) throws -> CGSize {
    guard
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = numberValue(properties[kCGImagePropertyPixelWidth]),
      let height = numberValue(properties[kCGImagePropertyPixelHeight])
    else {
      throw ImageResizeError.cannotReadSource
    }

    let orientation = numberValue(properties[kCGImagePropertyOrientation]) ?? 1
    if [5, 6, 7, 8].contains(Int(orientation)) {
      return CGSize(width: height, height: width)
    }
    return CGSize(width: width, height: height)
  }

  private nonisolated static func numberValue(_ value: Any?) -> CGFloat? {
    if let number = value as? NSNumber {
      return CGFloat(truncating: number)
    }
    return nil
  }

  private nonisolated static func targetSize(
    sourceSize: CGSize,
    configuration: ResizeConfiguration
  ) throws -> CGSize {
    if configuration.preservesOriginalSize {
      guard sourceSize.width.isFinite, sourceSize.height.isFinite,
        sourceSize.width > 0, sourceSize.height > 0,
        sourceSize.width * sourceSize.height <= CGFloat(maximumPixelCount)
      else { throw ImageResizeError.invalidDimensions }
      return sourceSize
    }
    guard
      configuration.width > 0,
      configuration.height > 0,
      configuration.width <= 100_000,
      configuration.height <= 100_000
    else {
      throw ImageResizeError.invalidDimensions
    }

    let requestedWidth = CGFloat(configuration.width)
    let requestedHeight = CGFloat(configuration.height)
    let result: CGSize

    if configuration.preservesAspectRatio {
      var scale = min(
        requestedWidth / sourceSize.width,
        requestedHeight / sourceSize.height
      )
      if !configuration.allowsUpscaling {
        scale = min(scale, 1)
      }
      result = CGSize(
        width: max(1, (sourceSize.width * scale).rounded()),
        height: max(1, (sourceSize.height * scale).rounded())
      )
    } else {
      result = CGSize(
        width: configuration.allowsUpscaling
          ? requestedWidth
          : min(requestedWidth, sourceSize.width),
        height: configuration.allowsUpscaling
          ? requestedHeight
          : min(requestedHeight, sourceSize.height)
      )
    }

    let pixelCount = Int64(result.width) * Int64(result.height)
    guard pixelCount > 0, pixelCount <= maximumPixelCount else {
      throw ImageResizeError.invalidDimensions
    }
    return result
  }

  private nonisolated static func createResizedImage(
    from source: CGImageSource,
    sourceSize: CGSize,
    targetSize: CGSize,
    outputFormat: OutputFormat,
    jpegBackgroundColor: RGBColor
  ) throws -> CGImage {
    let targetMaximumDimension = max(targetSize.width, targetSize.height)
    let sourceMaximumDimension = max(sourceSize.width, sourceSize.height)
    let thumbnailMaximumDimension = min(targetMaximumDimension, sourceMaximumDimension)

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(max(1, thumbnailMaximumDimension)),
      kCGImageSourceShouldCacheImmediately: true,
    ]

    guard
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      )
    else {
      throw ImageResizeError.cannotReadSource
    }

    let width = Int(targetSize.width)
    let height = Int(targetSize.height)
    let colorSpace = thumbnail.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)

    guard
      let colorSpace,
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw ImageResizeError.cannotCreateBitmap
    }

    context.interpolationQuality = .high
    if outputFormat == .jpeg {
      context.setFillColor(
        CGColor(
          red: CGFloat(jpegBackgroundColor.red),
          green: CGFloat(jpegBackgroundColor.green),
          blue: CGFloat(jpegBackgroundColor.blue),
          alpha: 1
        )
      )
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    } else {
      context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    }
    context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let resizedImage = context.makeImage() else {
      throw ImageResizeError.cannotCreateBitmap
    }
    return resizedImage
  }

  private nonisolated static func destinationTypeIsSupported(_ identifier: String) -> Bool {
    let supportedTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
    return supportedTypes.contains(identifier)
  }

  private nonisolated static func write(
    _ image: CGImage,
    source: CGImageSource,
    sourceURL: URL,
    to url: URL,
    configuration: ResizeConfiguration
  ) throws {
    var properties: [CFString: Any] = [:]
    if configuration.preservesMetadata,
      let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    {
      properties = sourceProperties
      properties.removeValue(forKey: kCGImagePropertyPixelWidth)
      properties.removeValue(forKey: kCGImagePropertyPixelHeight)
      properties[kCGImagePropertyOrientation] = 1

      if configuration.removesLocationMetadata {
        properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
      }
    }

    let encodedData: Data
    switch configuration.outputFormat {
    case .png:
      encodedData = try encodeWithImageIO(
        image,
        outputFormat: .png,
        properties: properties
      )
    case .jpeg:
      encodedData = try encodeLossyData(
        sourceURL: sourceURL,
        configuration: configuration
      ) { quality in
        var jpegProperties = properties
        jpegProperties[kCGImageDestinationLossyCompressionQuality] = quality
        return try encodeWithImageIO(
          image,
          outputFormat: .jpeg,
          properties: jpegProperties
        )
      }
    case .webP:
      encodedData = try encodeLossyData(
        sourceURL: sourceURL,
        configuration: configuration
      ) { quality in
        try encodeWebP(image, quality: quality)
      }
    }

    do {
      try encodedData.write(to: url, options: .atomic)
    } catch {
      throw ImageResizeError.cannotFinalizeDestination
    }
  }

  private nonisolated static func encodeWithImageIO(
    _ image: CGImage,
    outputFormat: OutputFormat,
    properties: [CFString: Any]
  ) throws -> Data {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        outputFormat.typeIdentifier as CFString,
        1,
        nil
      )
    else {
      throw ImageResizeError.cannotCreateDestination
    }

    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw ImageResizeError.cannotFinalizeDestination
    }
    return data as Data
  }

  private nonisolated static func encodeLossyData(
    sourceURL: URL,
    configuration: ResizeConfiguration,
    encode: (Double) throws -> Data
  ) throws -> Data {
    guard configuration.qualityMode == .automatic else {
      return try encode(configuration.quality)
    }

    guard
      let byteBudget = sourceByteBudget(
        sourceURL: sourceURL,
        outputFormat: configuration.outputFormat
      )
    else {
      return try encode(automaticDefaultQuality(for: configuration.outputFormat))
    }

    var smallestData: Data?
    for quality in automaticQualityCandidates(for: configuration.outputFormat) {
      let data = try encode(quality)
      if data.count <= byteBudget {
        return data
      }
      if data.count < (smallestData?.count ?? .max) {
        smallestData = data
      }
    }

    guard let smallestData else {
      throw ImageResizeError.cannotFinalizeDestination
    }
    return smallestData
  }

  private nonisolated static func automaticDefaultQuality(
    for outputFormat: OutputFormat
  ) -> Double {
    switch outputFormat {
    case .jpeg:
      return 0.55
    case .webP:
      return 0.8
    case .png:
      return 1
    }
  }

  private nonisolated static func automaticQualityCandidates(
    for outputFormat: OutputFormat
  ) -> [Double] {
    switch outputFormat {
    case .jpeg:
      return [0.72, 0.58, 0.46, 0.34, 0.22]
    case .webP:
      return [0.9, 0.8, 0.7, 0.6, 0.5]
    case .png:
      return []
    }
  }

  private nonisolated static func sourceByteBudget(
    sourceURL: URL,
    outputFormat: OutputFormat
  ) -> Int? {
    guard
      outputFormat != .png,
      sourceExtensionMatchesFormat(sourceURL.pathExtension, outputFormat)
    else {
      return nil
    }
    return try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
  }

  private nonisolated static func encodeWebP(
    _ image: CGImage,
    quality: Double
  ) throws -> Data {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
      CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    )

    let didRender = rgba.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let colorSpace,
        let baseAddress = buffer.baseAddress,
        let context = CGContext(
          data: baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: bytesPerRow,
          space: colorSpace,
          bitmapInfo: bitmapInfo.rawValue
        )
      else {
        return false
      }

      context.setBlendMode(.copy)
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }

    guard didRender else {
      throw ImageResizeError.cannotCreateBitmap
    }

    unpremultiplyRGBA(&rgba)

    var encodedBytes: UnsafeMutablePointer<UInt8>?
    let encodedSize = rgba.withUnsafeBytes { buffer in
      WebPEncodeRGBA(
        buffer.bindMemory(to: UInt8.self).baseAddress,
        Int32(width),
        Int32(height),
        Int32(bytesPerRow),
        Float(min(max(quality, 0.01), 1) * 100),
        &encodedBytes
      )
    }

    guard encodedSize > 0, let encodedBytes else {
      throw ImageResizeError.cannotFinalizeDestination
    }
    defer { WebPFree(encodedBytes) }
    return Data(bytes: encodedBytes, count: encodedSize)
  }

  private nonisolated static func unpremultiplyRGBA(_ pixels: inout [UInt8]) {
    for index in stride(from: 0, to: pixels.count, by: 4) {
      let alpha = Int(pixels[index + 3])
      guard alpha < 255 else { continue }

      if alpha == 0 {
        pixels[index] = 0
        pixels[index + 1] = 0
        pixels[index + 2] = 0
        continue
      }

      for componentOffset in 0..<3 {
        let component = Int(pixels[index + componentOffset])
        pixels[index + componentOffset] = UInt8(
          min(255, (component * 255 + alpha / 2) / alpha)
        )
      }
    }
  }

  private nonisolated static func verifyOutput(
    at url: URL,
    expectedSize: CGSize
  ) throws {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = numberValue(properties[kCGImagePropertyPixelWidth]),
      let height = numberValue(properties[kCGImagePropertyPixelHeight]),
      Int(width) == Int(expectedSize.width),
      Int(height) == Int(expectedSize.height)
    else {
      throw ImageResizeError.outputVerificationFailed
    }
  }

  private nonisolated static func installOutput(
    temporaryURL: URL,
    sourceURL: URL,
    outputDirectory: URL,
    configuration: ResizeConfiguration
  ) throws -> URL {
    let fileManager = FileManager.default

    if configuration.overwritesOriginal,
      sourceExtensionMatchesFormat(sourceURL.pathExtension, configuration.outputFormat)
    {
      do {
        _ = try fileManager.replaceItemAt(
          sourceURL,
          withItemAt: temporaryURL,
          backupItemName: nil,
          options: []
        )
      } catch {
        throw ImageResizeError.outputInstallationFailed(code: (error as NSError).code)
      }
      return sourceURL
    }

    let outputURL: URL
    if configuration.overwritesOriginal {
      let proposedURL =
        sourceURL
        .deletingPathExtension()
        .appendingPathExtension(configuration.outputFormat.fileExtension)
      outputURL = uniqueURL(from: proposedURL, fileManager: fileManager)
    } else {
      outputURL = uniqueOutputURL(
        sourceURL: sourceURL,
        suffix: configuration.filenameSuffix,
        outputFormat: configuration.outputFormat,
        outputDirectory: outputDirectory,
        fileManager: fileManager
      )
    }

    do {
      try fileManager.moveItem(at: temporaryURL, to: outputURL)
    } catch {
      throw ImageResizeError.outputInstallationFailed(code: (error as NSError).code)
    }
    return outputURL
  }

  private nonisolated static func sourceExtensionMatchesFormat(
    _ pathExtension: String,
    _ outputFormat: OutputFormat
  ) -> Bool {
    switch outputFormat {
    case .jpeg:
      return ["jpg", "jpeg"].contains(pathExtension.lowercased())
    case .png:
      return pathExtension.lowercased() == "png"
    case .webP:
      return pathExtension.lowercased() == "webp"
    }
  }

  private nonisolated static func uniqueURL(
    from proposedURL: URL,
    fileManager: FileManager
  ) -> URL {
    guard fileManager.fileExists(atPath: proposedURL.path) else {
      return proposedURL
    }

    let directory = proposedURL.deletingLastPathComponent()
    let basename = proposedURL.deletingPathExtension().lastPathComponent
    let pathExtension = proposedURL.pathExtension
    var index = 1

    while true {
      let candidate =
        directory
        .appendingPathComponent("\(basename)-\(index)")
        .appendingPathExtension(pathExtension)
      if !fileManager.fileExists(atPath: candidate.path) {
        return candidate
      }
      index += 1
    }
  }
}
