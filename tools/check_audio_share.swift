import Foundation
import UniformTypeIdentifiers

/// Exercises the production provider with real Foundation consumers. It does
/// not claim to reproduce Discord's private share extension or remote upload.
@main
struct AudioShareCheck {
  enum Failure: Error { case missingData, unexpectedItem }

  static func data(_ provider: NSItemProvider, type: String) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      _ = provider.loadDataRepresentation(forTypeIdentifier: type) { bytes, error in
        if let bytes { continuation.resume(returning: bytes) }
        else { continuation.resume(throwing: error ?? Failure.missingData) }
      }
    }
  }

  static func file(_ provider: NSItemProvider, type: String) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        do {
          guard let url else { throw error ?? Failure.missingData }
          // The system's temporary file is valid only inside this callback.
          continuation.resume(returning: try Data(contentsOf: url))
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  static func legacy(_ provider: NSItemProvider, type: String) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
        do {
          if let bytes = item as? Data { continuation.resume(returning: bytes) }
          else if let url = item as? URL {
            continuation.resume(returning: try Data(contentsOf: url))
          } else { throw error ?? Failure.unexpectedItem }
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("hyperstream-share-check-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Artist - Sample.mp3")
    var expected = Data("ID3".utf8)
    expected.append(Data(repeating: 0x7a, count: 11_000_000))
    try expected.write(to: source)
    let provider = AudioShareProvider.make(file: source)
    precondition(provider.suggestedName == source.lastPathComponent)
    precondition(provider.hasItemConformingToTypeIdentifier(UTType.mp3.identifier))
    precondition(provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier))
    precondition(provider.hasItemConformingToTypeIdentifier(UTType.data.identifier))
    let raw = try await data(provider, type: UTType.mp3.identifier)
    precondition(raw == expected)
    let copied = try await file(provider, type: UTType.mp3.identifier)
    precondition(copied == expected)
    let oldConsumer = try await legacy(provider, type: UTType.mp3.identifier)
    precondition(oldConsumer == expected)
    let generic = try await data(provider, type: UTType.data.identifier)
    precondition(generic == expected)
    try FileManager.default.removeItem(at: source)
    do {
      _ = try await data(AudioShareProvider.make(file: source), type: UTType.mp3.identifier)
      preconditionFailure("Missing source should fail cleanly")
    } catch {
      precondition(!(error as NSError).description.contains(root.path))
    }
    print("Native audio share: 11 MB data/file/legacy/generic readers, filename/type and missing-file handling passed.")
  }
}
