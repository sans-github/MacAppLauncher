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
                        .resizable()
                        .frame(width: 22, height: 22)
                    Text(app.name)
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
            .help(app.url == nil ? "\(app.name) is not installed" : "Open \(app.name)")

            Button(action: quit) { Image(systemName: "power") }
                .buttonStyle(CapsuleControlButtonStyle(tint: RowPalette.control, isOn: isRunning))
                .disabled(!isRunning)
                .help("Quit \(app.name)")
        }
    }

    private var icon: Image {
        guard let url = app.url else { return Image(systemName: "app.dashed") }
        return Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
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
