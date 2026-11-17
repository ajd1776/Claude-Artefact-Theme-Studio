import AppKit
import SwiftUI
import WebKit

@main
struct ThemeStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The editor: sidebar, live preview, inspector, compare.
        Window("Theme Studio", id: "main") {
            MainWindow()
        }
        .defaultSize(width: 1360, height: 860)
        .commands { StudioCommands() }

        // Pop-out previews: one real window per style. Move them to another display,
        // tile them, or take them full screen with the green button.
        WindowGroup("Preview", id: "preview", for: String.self) { $styleID in
            PreviewWindow(styleID: styleID ?? "p_bookmark")
        }
        .defaultSize(width: 1100, height: 760)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct MainWindow: View {
    @Environment(\.openWindow) private var openWindow
    @State private var subtitle = ""

    var body: some View {
        StudioWebView(
            role: .main,
            onTitle: { subtitle = $0 },
            onPopOut: { id in openWindow(id: "preview", value: id) }
        )
        .frame(minWidth: 860, minHeight: 560)
        .navigationSubtitle(subtitle)
    }
}

struct PreviewWindow: View {
    let styleID: String
    @State private var title = "Preview"

    var body: some View {
        StudioWebView(role: .preview(styleID), onTitle: { title = $0 }, onPopOut: nil)
            .frame(minWidth: 360, minHeight: 280)
            .navigationTitle(title)
    }
}

struct StudioCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Style from Selected") { Bridge.run("TS.duplicate()") }
                .keyboardShortcut("d")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { Bridge.run("TS.save()") }
                .keyboardShortcut("s")
            Button("Revert Changes") { Bridge.run("TS.revert()") }
            Divider()
            Button("Export Tokens…") { Bridge.run("TS.openExport()") }
                .keyboardShortcut("e")
            Button("Show Saved Styles in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([StyleStore.shared.folder])
            }
        }
        CommandMenu("Style") {
            Button("Pop Out Preview") { Bridge.run("TS.popOut()") }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Set as Default Artifact Theme…") { Bridge.run("TS.setDefault()") }
            Button("Show Default Theme Files in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([DefaultTheme.referenceURL])
            }
            Divider()
            Button("Dark Palette") { Bridge.run("TS.setVariant('dark')") }
                .keyboardShortcut("1")
            Button("Light Palette") { Bridge.run("TS.setVariant('light')") }
                .keyboardShortcut("2")
            Divider()
            Button("Edit") { Bridge.run("TS.setMode('edit')") }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Compare") { Bridge.run("TS.setMode('compare')") }
                .keyboardShortcut("2", modifiers: [.command, .option])
        }
    }
}

/// Lets menu commands reach the editor's web view.
enum Bridge {
    static weak var main: WKWebView?

    static func run(_ js: String) {
        main?.evaluateJavaScript("(function(){ if (window.TS) { \(js); } })()", completionHandler: nil)
    }
}
