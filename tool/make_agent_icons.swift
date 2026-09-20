// Renders every agent logo as its own round 128px PNG for the Flutter app:
// assets/agent-icons/<source name without extension>.png. The CATALOG in
// lib/src/domain/agent_catalog.dart names that file as each agent's `icon`.
// Sources live in tool/agent_icons (the originals, any format NSImage reads).
// Avatars are round, so every logo is fitted inside the circle:
// - keys in `badges` are black line art: drawn as a white glyph on a round
//   plate in the brand color (like the app icon), since they would vanish
//   on the dark background;
// - square tiles and round logos fill the cell as they are;
// - anything else is scaled down until it no longer pokes out of the circle.
//   swiftc tool/make_agent_icons.swift -o /tmp/make-agent-icons
//   /tmp/make-agent-icons tool/agent_icons assets/agent-icons
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: make-agent-icons <src dir> <out dir>"); exit(1) }
let src = URL(fileURLWithPath: args[1]), dst = URL(fileURLWithPath: args[2])

let files = [
  "claude-code.png", "codex.png", "cursor.png", "gemini_cli.png",            // 101-104
  "github_copilot.png", "windsurf.png", "opencode.png", "amp.png",           // 105-108
  "cline.png", "roo_code.png", "kilo-code.jpeg", "goose.svg",                // 109-112
  "antigravity.png", "droid.png", "kiro.png", "qwen_code.png",               // 113-116
  "augment.svg", "codebuddy.svg", "commandcode.svg", "continue.png",         // 117-120
  "crush.png", "deepseek-harness.svg", "hermes.svg", "iflow.svg",            // 121-124
  "junie.svg", "openclaw.svg", "pi.png", "qoder.png",                        // 125-128
  "trae-cn.svg", "trae.svg", "workbuddy.svg", "zencoder.jpeg",               // 129-132
  "adal.png", "cortex.svg", "deepagents.svg", "firebender.svg",              // 133-136
  "gitlab_duo.svg", "grok.svg", "ibm_bob.svg", "kimi.svg",                   // 137-140
  "mcpjam.png", "mistral_vibe.svg", "neovate.png", "openhands.svg",          // 141-144
  "pochi.png", "replit.svg", "warp.svg", "zcode.png",                        // 145-148
]
// Plate colors (top, bottom of the gradient). Brands without a color get graphite.
let graphite: (UInt32, UInt32) = (0x55555E, 0x2C2C33)
let badges: [String: (UInt32, UInt32)] = [
  "codex.png": graphite, "roo_code.png": graphite, "goose.svg": graphite,
  "augment.svg": graphite, "commandcode.svg": graphite, "hermes.svg": graphite,
  "grok.svg": graphite, "kimi.svg": graphite, "neovate.png": graphite, "warp.svg": graphite,
  "deepseek-harness.svg": (0x6E88FF, 0x3F5CF0),
  "gitlab_duo.svg": (0xFC6D26, 0xE24329),
  "ibm_bob.svg": (0x4589FF, 0x0F62FE),
]
// Source borders to cut away before drawing (fraction of each side).
let insets: [String: CGFloat] = ["neovate.png": 0.09]

let S = 512                        // work size of one logo; written downsampled to `out`
let out = 128
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32) -> CGColor {
  CGColor(colorSpace: rgb, components: [CGFloat((hex >> 16) & 0xff) / 255,
                                        CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, 1])!
}
func canvas(_ w: Int, _ h: Int) -> CGContext {
  CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: rgb,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

// The source drawn to fill an S x S square (aspect kept), optionally flattened to white.
func render(_ file: String, white: Bool) -> CGImage {
  guard let image = NSImage(contentsOf: src.appendingPathComponent(file)) else {
    print("missing \(file)"); exit(1)
  }
  let ctx = canvas(S, S)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
  let inset = insets[file] ?? 0
  let w = image.size.width, h = image.size.height
  let from = NSRect(x: w * inset, y: h * inset, width: w * (1 - 2 * inset), height: h * (1 - 2 * inset))
  let scale = CGFloat(S) / max(from.width, from.height)
  let rect = NSRect(x: (CGFloat(S) - from.width * scale) / 2, y: (CGFloat(S) - from.height * scale) / 2,
                    width: from.width * scale, height: from.height * scale)
  image.draw(in: rect, from: from, operation: .sourceOver, fraction: 1)
  if white { NSColor.white.set(); rect.fill(using: .sourceAtop) }
  NSGraphicsContext.restoreGraphicsState()
  return ctx.makeImage()!
}

// Where the opaque pixels are: their bounding-box center, the farthest one from
// that center, and how much of the area outside the inscribed circle is opaque.
func measure(_ image: CGImage) -> (center: CGPoint, reach: CGFloat, outside: CGFloat) {
  let ctx = canvas(S, S)
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: S, height: S))
  let px = ctx.data!.bindMemory(to: UInt8.self, capacity: S * ctx.bytesPerRow)
  var opaque: [(Int, Int)] = []
  var outsideAll = 0, outsideOpaque = 0
  let r = CGFloat(S) / 2
  for y in 0..<S {
    for x in 0..<S {
      let on = px[y * ctx.bytesPerRow + x * 4 + 3] > 40
      if on { opaque.append((x, y)) }
      let dx = CGFloat(x) + 0.5 - r, dy = CGFloat(y) + 0.5 - r
      if dx * dx + dy * dy > r * r { outsideAll += 1; if on { outsideOpaque += 1 } }
    }
  }
  guard !opaque.isEmpty else { return (CGPoint(x: r, y: r), r, 0) }
  let xs = opaque.map { $0.0 }, ys = opaque.map { $0.1 }
  let c = CGPoint(x: CGFloat(xs.min()! + xs.max()! + 1) / 2, y: CGFloat(ys.min()! + ys.max()! + 1) / 2)
  var reach: CGFloat = 0
  for (x, y) in opaque {
    let dx = CGFloat(x) + 0.5 - c.x, dy = CGFloat(y) + 0.5 - c.y
    reach = max(reach, (dx * dx + dy * dy).squareRoot())
  }
  return (c, reach, CGFloat(outsideOpaque) / CGFloat(outsideAll))
}

// Draws `image` so its opaque part is centered and reaches at most `radius`.
func place(_ image: CGImage, in ctx: CGContext, at x: CGFloat, radius: CGFloat) {
  let m = measure(image)
  let k = radius / m.reach
  let half = CGFloat(S) / 2
  ctx.draw(image, in: CGRect(x: x + half - m.center.x * k, y: half - m.center.y * k,
                             width: CGFloat(S) * k, height: CGFloat(S) * k))
}

for file in files {
  let cell = canvas(S, S)
  cell.interpolationQuality = .high
  let half = CGFloat(S) / 2
  // A little air so the round logo never touches the avatar's clip edge.
  cell.translateBy(x: half, y: half)
  cell.scaleBy(x: CGFloat(S - 16) / CGFloat(S), y: CGFloat(S - 16) / CGFloat(S))
  cell.translateBy(x: -half, y: -half)
  if let plate = badges[file] {
    let disc = CGRect(x: 0, y: 0, width: CGFloat(S), height: CGFloat(S))
    cell.saveGState()
    cell.addEllipse(in: disc); cell.clip()
    let g = CGGradient(colorsSpace: rgb, colors: [color(plate.0), color(plate.1)] as CFArray, locations: nil)!
    cell.drawLinearGradient(g, start: CGPoint(x: 0, y: CGFloat(S)), end: CGPoint(x: 0, y: 0), options: [])
    cell.restoreGState()
    place(render(file, white: true), in: cell, at: 0, radius: half * 0.66)
  } else {
    let image = render(file, white: false)
    let m = measure(image)
    if m.outside > 0.9 || m.outside < 0.02 {
      cell.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(S), height: CGFloat(S)))
    } else {
      place(image, in: cell, at: 0, radius: half * 0.96)
    }
  }
  let small = canvas(out, out)
  small.interpolationQuality = .high
  small.draw(cell.makeImage()!, in: CGRect(x: 0, y: 0, width: out, height: out))
  let rep = NSBitmapImageRep(cgImage: small.makeImage()!)
  let name = (file as NSString).deletingPathExtension + ".png"
  try rep.representation(using: .png, properties: [:])!.write(to: dst.appendingPathComponent(name))
}
print("wrote \(files.count) logos at \(out)x\(out)")
