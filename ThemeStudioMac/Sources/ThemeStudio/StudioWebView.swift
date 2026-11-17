import AppKit
import Combine
import SwiftUI
import WebKit

enum WebRole: Equatable {
    case main
    case preview(String)
}

/// Hosts the Theme Studio page. The editor and every pop-out window load the same page;
/// a boot script tells it which role it plays and hands it the styles saved on disk.
struct StudioWebView: NSViewRepresentable {
    let role: WebRole
    var onTitle: (String) -> Void
    var onPopOut: ((String) -> Void)?

    func makeCoordinator() -> WebCoordinator { WebCoordinator(role: role) }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.onTitle = onTitle
        context.coordinator.onPopOut = onPopOut
        return context.coordinator.makeWebView()
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onTitle = onTitle
        context.coordinator.onPopOut = onPopOut
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: WebCoordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "studio")
        coordinator.liveUpdates = nil
    }
}

final class WebCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let role: WebRole
    weak var webView: WKWebView?
    var onTitle: ((String) -> Void)?
    var onPopOut: ((String) -> Void)?
    var liveUpdates: AnyCancellable?
    private let store = StyleStore.shared

    init(role: WebRole) { self.role = role }

    func makeWebView() -> WKWebView {
        let controller = WKUserContentController()
        controller.add(WeakMessageHandler(self), name: "studio")
        controller.addUserScript(WKUserScript(source: bootScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .default()

        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground") // no white flash before the page paints
        view.isInspectable = true
        view.navigationDelegate = self
        webView = view

        switch role {
        case .main:
            Bridge.main = view
        case .preview:
            // Every edit in the editor arrives here and redraws this window.
            liveUpdates = store.$liveJSON
                .dropFirst()
                .receive(on: RunLoop.main)
                .sink { [weak self] json in
                    self?.webView?.evaluateJavaScript("window.TS_live && window.TS_live(\(json))", completionHandler: nil)
                }
        }

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<p style='font:14px -apple-system;padding:24px'>The page is missing from the app bundle. Run build.sh again.</p>", baseURL: nil)
        }
        return view
    }

    private func bootScript() -> String {
        switch role {
        case .main:
            return """
            window.__TS_NATIVE = { mode: 'main', styles: \(store.savedStylesJSON()),
              template: \(jsonLiteral(DefaultTheme.templateText())), defaultId: \(jsonLiteral(DefaultTheme.currentID() ?? NSNull())) };
            """
        case .preview(let id):
            return """
            window.__TS_NATIVE = { mode: 'preview', previewId: \(jsonLiteral(id)), variant: \(jsonLiteral(store.variant)),
              styles: \(store.savedStylesJSON()), live: \(store.liveJSON) };
            """
        }
    }

    // MARK: messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "save":
            if let id = body["id"] as? String, let json = body["json"] as? String { store.save(id: id, json: json) }
        case "delete":
            if let id = body["id"] as? String { store.delete(id: id) }
        case "live":
            if let variant = body["variant"] as? String { store.variant = variant }
            if let json = body["json"] as? String, StyleStore.isJSONObject(json) { store.liveJSON = json }
        case "title":
            if let text = body["text"] as? String { onTitle?(text) }
        case "popout":
            if let variant = body["variant"] as? String { store.variant = variant }
            if let id = body["id"] as? String { onPopOut?(id) }
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "setDefault":
            if let id = body["id"] as? String, let name = body["name"] as? String,
               let reference = body["reference"] as? String, let skill = body["skill"] as? String {
                confirmSetDefault(id: id, name: name, reference: reference, skill: skill)
            }
        case "saveFile":
            if let text = body["text"] as? String { saveFile(name: body["name"] as? String ?? "theme.css", text: text) }
        default:
            break
        }
    }

    private func confirmSetDefault(id: String, name: String, reference: String, skill: String) {
        let alert = NSAlert()
        alert.messageText = "Make “\(name)” your default artifact theme?"
        alert.informativeText = "Claude will use it for the pages and artifacts it builds for you from now on. This rewrites reference.html and the Current style section of SKILL.md in ~/.claude/skills/terminal-preview. The versions there now are kept as reference.previous.html and SKILL.previous.md."
        alert.addButton(withTitle: "Set as Default")
        alert.addButton(withTitle: "Cancel")
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            do {
                try DefaultTheme.apply(id: id, name: name, reference: reference, skillBlock: skill)
                self?.reply(["ok": true, "id": id])
            } catch {
                self?.reply(["ok": false, "message": error.localizedDescription])
            }
        }
        if let window = webView?.window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func reply(_ result: [String: Any]) {
        webView?.evaluateJavaScript("window.TS_defaultSet && window.TS_defaultSet(\(jsonLiteral(result)))", completionHandler: nil)
    }

    private func saveFile(name: String, text: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        let write: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { NSAlert(error: error).runModal() }
        }
        if let window = webView?.window {
            panel.beginSheetModal(for: window, completionHandler: write)
        } else {
            write(panel.runModal())
        }
    }

    // Links open in the default browser, never inside the app.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated, let url = action.request.url, url.scheme?.hasPrefix("http") == true {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}

/// Avoids the retain cycle between WKUserContentController and its handler.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
