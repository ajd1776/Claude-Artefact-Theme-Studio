// Renders the README screenshots from the page the Mac app ships, offscreen, with WebKit.
// Each shot loads the page in the app's native mode with example styles, then saves a 2x PNG.
//
// Usage (from the repo root, after ./ThemeStudioMac/build.sh):
//   swift docs/shoot.swift "ThemeStudioMac/build/Theme Studio.app/Contents/Resources/index.html" docs/screenshots
import AppKit
import WebKit

struct Shot {
    let name: String
    let width: CGFloat
    let height: CGFloat
    let dark: Bool
    let ui: String        // the page's remembered view state
    let native: String    // what the Mac app would hand the page at launch
    var after = ""        // script to run once loaded
}

// Example "My Styles" so the sidebar isn't empty. Missing fields fall back to Bookmark Panel.
let now = Int(Date().timeIntervalSince1970 * 1000)
let examples = """
{ s_forest: { name: 'Deep Forest', updatedAt: \(now - 2 * 3_600_000), box: 'double', font: 'jet',
    dark: { bg: '#020a05', fg: '#3cff8f', fg2: '#22c46a', dim: '#1f9150', line: '#0f5c31', faint: '#082a17' } },
  s_night: { name: 'Night Shift', updatedAt: \(now - 26 * 3_600_000), box: 'rounded', font: 'fira',
    dark: { bg: '#07040e', fg: '#c8b6ff', fg2: '#9c86e6', dim: '#7a66b8', line: '#3d2f66', faint: '#1a1230', cyan: '#5ef2ff' } } }
"""
let main = "{ mode: 'main', styles: \(examples) }"

let shots: [Shot] = [
    Shot(name: "editor-dark", width: 1440, height: 900, dark: true,
         ui: #"{"sel":"p_bookmark","mode":"edit","variant":"dark"}"#, native: main),
    Shot(name: "editor-light", width: 1440, height: 900, dark: false,
         ui: #"{"sel":"p_ice","mode":"edit","variant":"light"}"#, native: main),
    Shot(name: "compare", width: 1600, height: 1000, dark: true,
         ui: #"{"sel":"p_bookmark","mode":"compare","variant":"dark","cmp":["p_bookmark","s_forest","p_amber"],"cmpN":3}"#, native: main),
    Shot(name: "pop-out", width: 1200, height: 760, dark: true,
         ui: "{}", native: "{ mode: 'preview', previewId: 'p_amber', variant: 'dark', styles: \(examples), live: {} }"),
    Shot(name: "export", width: 1440, height: 900, dark: true,
         ui: #"{"sel":"s_forest","mode":"edit","variant":"dark"}"#, native: main, after: "TS.openExport()"),
]

func jsString(_ s: String) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: s, options: .fragmentsAllowed), encoding: .utf8)!
}

/// Rounded corners, a hairline and a soft shadow on a transparent canvas, at 2x.
func framedPNG(_ image: CGImage, width w: CGFloat, height h: CGFloat) -> Data {
    let scale: CGFloat = 2, pad: CGFloat = 40, radius: CGFloat = 12
    let ctx = CGContext(data: nil, width: Int((w + pad * 2) * scale), height: Int((h + pad * 2) * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    let rect = CGRect(x: pad, y: pad, width: w, height: h)
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 32, color: CGColor(gray: 0, alpha: 0.32))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip(); ctx.interpolationQuality = .high
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.35)); ctx.setLineWidth(1); ctx.strokePath()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

final class Shooter: NSObject, WKNavigationDelegate {
    let page: URL, outDir: URL
    var queue: [Shot]
    var current: Shot?
    var window: NSWindow?
    var web: WKWebView?

    init(page: URL, outDir: URL, shots: [Shot]) { self.page = page; self.outDir = outDir; queue = shots }

    func next() {
        guard !queue.isEmpty else { NSApp.terminate(nil); return }
        let shot = queue.removeFirst(); current = shot
        let boot = """
        try { localStorage.clear(); localStorage.setItem('ts.ui', \(jsString(shot.ui))); } catch (e) {}
        window.__TS_NATIVE = \(shot.native);
        """
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let config = WKWebViewConfiguration(); config.userContentController = controller
        let frame = NSRect(x: 0, y: 0, width: shot.width, height: shot.height)
        let win = NSWindow(contentRect: frame.offsetBy(dx: -30_000, dy: -30_000), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: shot.dark ? .darkAqua : .aqua)
        let view = WKWebView(frame: frame, configuration: config)
        view.navigationDelegate = self
        win.contentView = view
        win.orderBack(nil)
        window = win; web = view
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let shot = current else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !shot.after.isEmpty { webView.evaluateJavaScript(shot.after, completionHandler: nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.snap(shot) }
        }
    }

    func snap(_ shot: Shot) {
        let config = WKSnapshotConfiguration(); config.afterScreenUpdates = true
        web?.takeSnapshot(with: config) { image, error in
            if let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let url = self.outDir.appendingPathComponent(shot.name + ".png")
                try! framedPNG(cg, width: shot.width, height: shot.height).write(to: url)
                print("✓ \(url.lastPathComponent)  \(cg.width)×\(cg.height)")
            } else {
                print("✗ \(shot.name): \(error?.localizedDescription ?? "no image")")
            }
            self.window?.orderOut(nil)
            self.next()
        }
    }
}

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: swift docs/shoot.swift <index.html> <out-dir>"); exit(2) }
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let shooter = Shooter(page: URL(fileURLWithPath: args[1]), outDir: outDir, shots: shots)
shooter.next()
app.run()
