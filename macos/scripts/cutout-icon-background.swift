// Lifts the mochi off whatever ground the image model drew it on, so the app-icon artwork can go
// into Icon Composer as a layer over a background *it* controls rather than one baked into the
// pixels (which would survive into the Dark/Clear/Tinted appearances the system derives).
//
//     swift scripts/cutout-icon-background.swift <master.png> <out-1024.png> [chroma] [lumaHeadroom] [edgeTrim]
//
// The current master was cut with:
//
//     swift scripts/cutout-icon-background.swift \
//         App/Icon/mochi-icon-master-1254.png App/Icon/mochi-icon-cutout-1024.png 18 255 2
//
// Background is taken to be the low-chroma region reachable from the border, so the subject's
// interior can never be punched out no matter how neutral it goes. The two thresholds are
// **per-master and must be re-measured** — sample the plate, the contact shadow and several points
// on the subject before trusting a number here.
//
//   chroma        max colourfulness a pixel may have and still count as ground. Measured on the
//                 current master: plate 8, outer white 0, contact shadow 13, mochi body 24-39 —
//                 so 18 sits in the gap.
//   lumaHeadroom  how much brighter than the border a pixel may be and still count as ground.
//                 Needed only when the subject has a *neutral* specular highlight that the fill
//                 could otherwise walk into from the edge: on an earlier master the plate sat at
//                 luma ~220 and the highlight at 240+, and a headroom of 9 landed in that gap.
//                 The current master's sheen is warm (chroma 24), so chroma alone holds it and the
//                 headroom is left wide open.
//   edgeTrim      pixels of background grown inwards before feathering, to swallow the
//                 anti-aliased ring where subject and ground blend. Without it that ring survives
//                 as a speckled fringe all round the silhouette; 2 is enough on the current
//                 master and costs about a pixel and a half of subject at the output size.
//
// A residual haze at the base is expected wherever the innermost contact shadow is warmed by
// bounce light: it reads as chromatic and survives. Widening chroma far enough to take it starts
// notching the subject's lower sides, which is the worse defect.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let srcURL = URL(fileURLWithPath: CommandLine.arguments[1])
let dstURL = URL(fileURLWithPath: CommandLine.arguments[2])
let outSide = 1024

guard let source = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
      let cgIn = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("cannot read source") }
let w = cgIn.width, h = cgIn.height

// Normalise into a known RGBA8 sRGB buffer; everything below works on raw bytes.
let space = CGColorSpace(name: CGColorSpace.sRGB)!
var buf = [UInt8](repeating: 0, count: w*h*4)
buf.withUnsafeMutableBytes { raw in
    let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w*4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cgIn, in: CGRect(x: 0, y: 0, width: w, height: h))
}

// Background = low-chroma pixels reachable from the border. Flood fill rather than a global
// threshold, so the mochi's own neutral specular highlight can't be punched out from inside.
let chromaLimit = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 18
let lumaHeadroom = CommandLine.arguments.count > 4 ? Int(CommandLine.arguments[4])! : 255
let edgeTrim = CommandLine.arguments.count > 5 ? Int(CommandLine.arguments[5])! : 2
// The plate's brightness, taken as the median of the border ring rather than one corner: the
// plate has a faint vignette, and a single sample sets the threshold too low to propagate across.
var borderLuma: [Int] = []
for x in 0..<w { borderLuma.append(x); borderLuma.append((h-1)*w + x) }
for y in 0..<h { borderLuma.append(y*w); borderLuma.append(y*w + w-1) }
let bgLuma = borderLuma.map { (Int(buf[$0*4]) + Int(buf[$0*4+1]) + Int(buf[$0*4+2])) / 3 }
    .sorted()[borderLuma.count/2]
func chroma(_ i: Int) -> Int {
    let r = Int(buf[i*4]), g = Int(buf[i*4+1]), b = Int(buf[i*4+2])
    return max(r, max(g, b)) - min(r, min(g, b))
}
func luma(_ i: Int) -> Int { (Int(buf[i*4]) + Int(buf[i*4+1]) + Int(buf[i*4+2])) / 3 }
// Background *and* its contact shadow are neutral and no brighter than the plate; the mochi's
// specular highlight is neutral too but *brighter*, which is what stops the fill from eating it.
func isBackgroundish(_ i: Int) -> Bool { chroma(i) <= chromaLimit && luma(i) <= bgLuma + lumaHeadroom }
var isBG = [Bool](repeating: false, count: w*h)
var stack: [Int] = []
func seed(_ i: Int) { if !isBG[i] && isBackgroundish(i) { isBG[i] = true; stack.append(i) } }
for x in 0..<w { seed(x); seed((h-1)*w + x) }
for y in 0..<h { seed(y*w); seed(y*w + w-1) }
while let i = stack.popLast() {
    let x = i % w, y = i / w
    if x > 0 { seed(i-1) }
    if x < w-1 { seed(i+1) }
    if y > 0 { seed(i-w) }
    if y < h-1 { seed(i+w) }
}

// Grow the background inwards by a couple of pixels before feathering. The subject's edge is
// anti-aliased into the ground, so the ring where the two blend lands between the two chroma
// populations and survives the fill as a speckled fringe. Trimming past it puts the boundary in
// solid subject, where feathering can make a clean edge; raising the chroma limit far enough to
// take the fringe instead starts eating the glossy rim, which is the worse defect.
if edgeTrim > 0 {
    var grown = isBG
    for y in 0..<h {
        for x in 0..<w where !isBG[y*w + x] {
            var touchesBackground = false
            for dy in -edgeTrim...edgeTrim where !touchesBackground {
                let ny = y + dy
                guard ny >= 0, ny < h else { continue }
                for dx in -edgeTrim...edgeTrim {
                    let nx = x + dx
                    guard nx >= 0, nx < w else { continue }
                    if isBG[ny*w + nx] { touchesBackground = true; break }
                }
            }
            if touchesBackground { grown[y*w + x] = true }
        }
    }
    isBG = grown
}

// Feather the cut so it doesn't read as a hard sticker outline.
let radius = 3
var alpha = isBG.map { $0 ? 0.0 : 255.0 }
var feathered = alpha
for y in 0..<h {
    for x in 0..<w {
        var sum = 0.0, n = 0.0
        for dy in -radius...radius {
            let ny = y + dy
            guard ny >= 0, ny < h else { continue }
            for dx in -radius...radius {
                let nx = x + dx
                guard nx >= 0, nx < w else { continue }
                sum += alpha[ny*w + nx]; n += 1
            }
        }
        feathered[y*w + x] = sum / n
    }
}
alpha = feathered

// Write alpha back, premultiplied to match the context's format.
for i in 0..<(w*h) {
    let a = alpha[i] / 255
    buf[i*4]   = UInt8((Double(buf[i*4]) * a).rounded())
    buf[i*4+1] = UInt8((Double(buf[i*4+1]) * a).rounded())
    buf[i*4+2] = UInt8((Double(buf[i*4+2]) * a).rounded())
    buf[i*4+3] = UInt8(alpha[i].rounded())
}

let cut = isBG.filter { $0 }.count
print("background pixels removed: \(cut) (\(String(format: "%.1f", Double(cut)/Double(w*h)*100))%)")

// Down to the exact 1024 canvas, with no window-server backing scale in the way.
let cgCut = buf.withUnsafeMutableBytes { raw -> CGImage in
    CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
              bytesPerRow: w*4, space: space,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
}
let outCtx = CGContext(data: nil, width: outSide, height: outSide, bitsPerComponent: 8,
                       bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
outCtx.interpolationQuality = .high
outCtx.draw(cgCut, in: CGRect(x: 0, y: 0, width: outSide, height: outSide))
let cgOut = outCtx.makeImage()!

guard let dest = CGImageDestinationCreateWithURL(dstURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("cannot create destination") }
CGImageDestinationAddImage(dest, cgOut, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("cannot write png") }
print("OK \(dstURL.path)")
