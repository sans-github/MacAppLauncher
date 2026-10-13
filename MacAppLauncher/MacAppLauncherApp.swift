import AppKit
import Combine
import SwiftUI

@main
@MainActor
struct MacAppLauncherApp: App {
    @StateObject private var catalog = AppCatalog()

    var body: some Scene {
        MenuBarExtra {
            LauncherPanel(catalog: catalog)
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Model

/// One sibling project, resolved to the app it builds.
struct LauncherApp: Identifiable {
    /// The `.xcodeproj` name, which is the product name. The folder name is not:
    /// `MacSoshinWidgets` builds `Shoshin.app`.
    let name: String
    /// Nil when the project has never been installed.
    let url: URL?
    let bundleID: String?

    var id: String { name }

    /// `MacCountdownWidget` shows as `Countdown`.
    var displayName: String {
        var n = name
        if n.hasPrefix("Mac") { n.removeFirst(3) }
        for suffix in ["Widgets", "Widget"] where n.hasSuffix(suffix) {
            n.removeLast(suffix.count)
            break
        }
        return n.isEmpty ? name : n
    }
}

/// Lists every app project next to this one and tracks which are running.
///
/// The projects folder is a source tree, so each sibling is mapped to its
/// installed bundle in /Applications or ~/Applications by project name.
@MainActor
final class AppCatalog: ObservableObject {
    /// Excluded from the list: this app.
    static let selfName = "MacAppLauncher"
    static let rootKey = "projectsRoot"
    static let defaultRoot = NSHomeDirectory() + "/Documents/hello-claude/mac-widgets"

    @Published private(set) var apps: [LauncherApp] = []
    @Published private(set) var running: Set<String> = []

    var root: URL {
        URL(fileURLWithPath: UserDefaults.standard.string(forKey: Self.rootKey) ?? Self.defaultRoot)
    }

    private var runningWatch: AnyCancellable?

    init() {
        // KVO on `runningApplications`, not the didLaunch/didTerminate
        // notifications: those are not posted for LSUIElement apps, and every
        // app this launcher lists is one.
        runningWatch = NSWorkspace.shared.publisher(for: \.runningApplications)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] apps in
                self?.running = Set(apps.compactMap(\.bundleIdentifier))
            }
        reload()
    }

    func reload() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                   options: [.skipsHiddenFiles])) ?? []
        apps = folders
            .filter { $0.lastPathComponent != Self.selfName && $0.hasDirectoryPath }
            .compactMap { folder in
                let project = (try? fm.contentsOfDirectory(atPath: folder.path))?
                    .first { $0.hasSuffix(".xcodeproj") }
                guard let project else { return nil }
                let name = (project as NSString).deletingPathExtension
                guard name != Self.selfName else { return nil }
                let url = Self.installedURL(for: name)
                return LauncherApp(name: name, url: url, bundleID: url.flatMap { Bundle(url: $0)?.bundleIdentifier })
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        refreshRunning()
    }

    func refreshRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func isRunning(_ app: LauncherApp) -> Bool {
        app.bundleID.map { running.contains($0) } ?? false
    }

    func launch(_ app: LauncherApp) {
        guard let url = app.url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func quit(_ app: LauncherApp) {
        guard let id = app.bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = root
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: Self.rootKey)
        reload()
    }

    private static func installedURL(for name: String) -> URL? {
        ["/Applications", NSHomeDirectory() + "/Applications"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name + ".app") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

// MARK: - Panel

@MainActor
struct LauncherPanel: View {
    @ObservedObject var catalog: AppCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if catalog.apps.isEmpty {
                Text("No apps found in \(catalog.root.lastPathComponent)")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            ForEach(catalog.apps) { app in
                AppRow(app: app, isRunning: catalog.isRunning(app),
                       launch: { catalog.launch(app) }, quit: { catalog.quit(app) })
            }
            Divider()
            HStack {
                Button { catalog.chooseRoot() } label: { Image(systemName: "folder") }
                    .buttonStyle(CapsuleControlButtonStyle(tint: RowPalette.control, isOn: false))
                    .help("Choose projects folder (\(catalog.root.path))")
                Spacer()
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(CapsuleControlButtonStyle(tint: RowPalette.control, isOn: true))
                    .help("Quit MacAppLauncher")
            }
        }
        .padding(10)
        .frame(width: 240)
        .focusEffectDisabled()
        .onAppear { catalog.reload() }
    }
}

@MainActor
struct AppRow: View {
    let app: LauncherApp
    let isRunning: Bool
    let launch: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: launch) {
                HStack(spacing: 8) {
                    icon
                        .frame(width: 22, height: 22)
                    Text(app.displayName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isRunning {
                        Circle()
                            .fill(RowPalette.control)
                            .frame(width: 6, height: 6)
                            .accessibilityLabel("Running")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.url == nil)
            .opacity(app.url == nil ? 0.35 : 1)
            .help(app.url == nil ? "\(app.displayName) is not installed" : "Open \(app.displayName)")

            Button(action: quit) { Image(systemName: "power") }
                .buttonStyle(CapsuleControlButtonStyle(tint: RowPalette.control, isOn: isRunning))
                .disabled(!isRunning)
                .help("Quit \(app.displayName)")
        }
    }

    @ViewBuilder private var icon: some View {
        if let url = app.url, Self.hasOwnIcon(url) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            let tile = AppTile.forName(app.displayName)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tile.color)
                .overlay {
                    if let symbol = tile.symbol {
                        Image(systemName: symbol)
                    } else {
                        Text(app.displayName.prefix(1))
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// The sibling apps ship no icon, so NSWorkspace would hand back the
    /// generic grid square for them.
    private static func hasOwnIcon(_ url: URL) -> Bool {
        let info = Bundle(url: url)?.infoDictionary
        return info?["CFBundleIconFile"] != nil || info?["CFBundleIconName"] != nil
    }
}

// MARK: - Style (shared with MacRecordWidget)

enum RowPalette {
    /// #007AFF. Every lit control, as in MacRecordWidget.
    static let control = Color(red: 0.0, green: 0.4784, blue: 1.0)
    static let glyphOn = Color.white
}

/// Off: rounded rect on `controlBackgroundColor` with a 1pt `separatorColor`
/// outline. On: a capsule filled with the tint and no outline.
private struct CapsuleControlChrome<Label: View>: View {
    let isOn: Bool
    let tint: Color
    let isPressed: Bool
    let label: Label

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        label
            .foregroundStyle(isOn ? RowPalette.glyphOn : Color(nsColor: .labelColor))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background {
                if isOn {
                    Capsule().fill(tint)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                }
            }
            .contentShape(Rectangle())
            .opacity(isPressed ? 0.75 : 1)
            .opacity(isEnabled ? 1 : 0.35)
    }
}

struct CapsuleControlButtonStyle: ButtonStyle {
    let tint: Color
    var isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        CapsuleControlChrome(isOn: isOn, tint: tint, isPressed: configuration.isPressed, label: configuration.label)
    }
}

/// Stand-in icon for an app that has none of its own.
struct AppTile {
    let symbol: String?
    let color: Color

    static func forName(_ name: String) -> AppTile {
        switch name {
        case "Countdown": return AppTile(symbol: "timer", color: Color(red: 1.0, green: 0.624, blue: 0.039))
        case "Record": return AppTile(symbol: "record.circle", color: Color(red: 1.0, green: 0.2196, blue: 0.2353))
        case "Shoshin": return AppTile(symbol: "circle.dashed", color: Color(red: 0.188, green: 0.69, blue: 0.78))
        default: return AppTile(symbol: nil, color: Color(nsColor: .systemGray))
        }
    }
}
