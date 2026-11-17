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

/// Writes a style into the terminal-preview skill so it becomes the look Claude uses for artifacts.
/// The page builds the files (it has the renderer); this only checks, backs up and writes them.
enum DefaultTheme {
    static let skillDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/skills/terminal-preview", isDirectory: true)
    static var referenceURL: URL { skillDir.appendingPathComponent("reference.html") }
    static var skillURL: URL { skillDir.appendingPathComponent("SKILL.md") }
    private static var recordURL: URL {
        StyleStore.shared.folder.deletingLastPathComponent().appendingPathComponent("default.json")
    }
    static let begin = "<!-- theme-studio:begin"
    static let end = "<!-- theme-studio:end -->"

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// The box-drawing reference page every default theme is generated from.
    static func templateText() -> String {
        guard let url = Bundle.main.url(forResource: "reference-template", withExtension: "html"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    /// The id of the style last set as default, if any.
    static func currentID() -> String? {
        guard let data = try? Data(contentsOf: recordURL),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return record["id"] as? String
    }

    static func apply(id: String, name: String, reference: String, skillBlock: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillURL.path) else {
            throw Failure(message: "Couldn't find the terminal-preview skill in ~/.claude/skills/terminal-preview, so nothing was changed.")
        }
        guard reference.contains("<style>"), reference.contains("--k-white"),
              skillBlock.hasPrefix(begin), skillBlock.hasSuffix(end) else {
            throw Failure(message: "The generated theme files looked incomplete, so nothing was changed.")
        }
        let skill = try String(contentsOf: skillURL, encoding: .utf8)
        guard let b = skill.range(of: begin), let e = skill.range(of: end), b.lowerBound < e.lowerBound else {
            throw Failure(message: "SKILL.md has no Current style section for Theme Studio to replace, so nothing was changed.")
        }
        let updatedSkill = skill.replacingCharacters(in: b.lowerBound..<e.upperBound, with: skillBlock)

        // Keep one step of history next to the live files.
        let previousReference = skillDir.appendingPathComponent("reference.previous.html")
        let previousSkill = skillDir.appendingPathComponent("SKILL.previous.md")
        if fm.fileExists(atPath: referenceURL.path) {
            try? fm.removeItem(at: previousReference)
            try fm.copyItem(at: referenceURL, to: previousReference)
        }
        try? fm.removeItem(at: previousSkill)
        try fm.copyItem(at: skillURL, to: previousSkill)

        try reference.write(to: referenceURL, atomically: true, encoding: .utf8)
        try updatedSkill.write(to: skillURL, atomically: true, encoding: .utf8)
        let record: [String: Any] = ["id": id, "name": name, "setAt": Int(Date().timeIntervalSince1970 * 1000)]
        try? jsonLiteral(record).write(to: recordURL, atomically: true, encoding: .utf8)
    }
}
