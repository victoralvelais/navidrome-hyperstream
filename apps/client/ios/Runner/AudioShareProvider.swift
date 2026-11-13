import Foundation
import UniformTypeIdentifiers

/// Offers actual audio bytes as well as a file copy. Receivers that request
/// data must never get the UTF-8 bytes of a private file URL instead.
enum AudioShareProvider {
  private static var unavailable: NSError {
    NSError(domain: "dev.hyperstream.share", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The audio file is no longer available."])
  }

  static func make(file: URL) -> NSItemProvider {
    let provider = NSItemProvider()
    let type = UTType(filenameExtension: file.pathExtension) ?? .data
    provider.suggestedName = file.lastPathComponent
    provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          completion(try Data(contentsOf: file, options: .mappedIfSafe), nil)
        } catch {
          completion(nil, unavailable)
        }
      }
      return nil
    }
    // No openInPlace option: the system may provide its own readable copy to
    // another process, instead of requiring access to our app's private path.
    provider.registerFileRepresentation(forTypeIdentifier: type.identifier,
                                        fileOptions: [], visibility: .all) { completion in
      if FileManager.default.isReadableFile(atPath: file.path) {
        completion(file, false, nil)
      } else {
        completion(nil, false, unavailable)
      }
      return nil
    }
    return provider
  }
}
