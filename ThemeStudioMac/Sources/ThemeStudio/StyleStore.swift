import Combine
import Foundation

/// Saved styles live as one JSON file each in
/// ~/Library/Application Support/Theme Studio/styles/<id>.json
/// so they survive reinstalls and Claude can read them later.
final class StyleStore: ObservableObject {
    static let shared = StyleStore()

    /// Every style as the editor currently shows it (unsaved edits included), as JSON.
    @Published var liveJSON = "{}"
    /// The palette the editor last showed; new pop-outs start with it.
    var variant = "dark"
    let folder: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("Theme Studio/styles", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func savedStylesJSON() -> String {
        var all: [String: Any] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            all[url.deletingPathExtension().lastPathComponent] = object
        }
        return jsonLiteral(all)
    }

    func save(id: String, json: String) {
        guard Self.isSafeID(id), Self.isJSONObject(json), let data = json.data(using: .utf8) else { return }
        try? data.write(to: folder.appendingPathComponent(id + ".json"), options: .atomic)
    }

    func delete(id: String) {
        guard Self.isSafeID(id) else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(id + ".json"))
    }

    static func isSafeID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
    }

    static func isJSONObject(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }
}

/// A value written as a JSON literal, safe to drop into a script.
func jsonLiteral(_ value: Any) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
          let text = String(data: data, encoding: .utf8) else { return "null" }
    return text
}
