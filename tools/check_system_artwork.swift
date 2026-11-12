import Foundation
import CoreGraphics
import ImageIO

/// Runs against the production Image I/O converter without Flutter or a GPU.
@main
struct ArtworkCheck {
  static func fixture(_ type: String, orientation: Int = 1) -> Data {
    let context = CGContext(
      data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.4, green: 0.1, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [
      kCGImagePropertyOrientation: orientation,
    ] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return data as Data
  }

  static func check(_ data: Data, width: Int, height: Int) {
    let png = SystemArtwork.pngData(data)!
    let source = CGImageSourceCreateWithData(png as CFData, nil)!
    precondition(CGImageSourceGetType(source)! as String == "public.png")
    precondition(CGImageSourceGetCount(source) == 1)
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    precondition(image.width == width && image.height == height)
  }

  static func main() {
    check(fixture("public.png"), width: 512, height: 256)
    check(fixture("public.jpeg"), width: 512, height: 256)
    check(fixture("public.jpeg", orientation: 6), width: 256, height: 512)
    precondition(SystemArtwork.pngData(Data()) == nil)
    precondition(SystemArtwork.pngData(Data("not an image".utf8)) == nil)
    precondition(SystemArtwork.pngData(Data([137, 80, 78, 71, 13, 10, 26, 10])) == nil)
    precondition(SystemArtwork.pngData(Data(repeating: 0, count: 8 * 1024 * 1024 + 1)) == nil)
    let input = fixture("public.png")
    let done = DispatchGroup()
    done.enter()
    DispatchQueue.global(qos: .utility).async {
      autoreleasepool { check(input, width: 512, height: 256) }
      done.leave()
    }
    precondition(done.wait(timeout: .now() + 20) == .success)
    print("Native artwork: PNG/JPEG, orientation, size bounds, invalid input and background worker passed.")
  }
}
