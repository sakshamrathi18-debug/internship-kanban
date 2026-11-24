import AppKit
import KanbanCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// ⌘, — WIP limit, archive window, summary strip, launch at login, export/import.
struct SettingsView: View {
    @Environment(BoardStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?
    @State private var importCandidate: BoardFile?
    @State private var dataNote: String?

    var body: some View {
        Form {
            Section("Board") {
                Picker("Work-in-progress limit", selection: wipLimit) {
                    Text("Off").tag(Int?.none)
                    ForEach(BoardSettings.wipLimitRange, id: \.self) { value in
                        Text("\(value)").tag(Int?.some(value))
                    }
                }
                LabeledContent("Archive Done cards after") {
                    HStack(spacing: 6) {
                        Text("\(store.settings.archiveAfterDays) days").monospacedDigit()
                        Stepper("Archive after", value: archiveDays, in: BoardSettings.archiveDaysRange)
                            .labelsHidden()
                    }
                }
                Toggle("Show summary in toolbar", isOn: showStrip)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginNote {
                    Text(loginNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if SMAppService.mainApp.status == .requiresApproval {
                        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
            }

            Section {
                HStack {
                    Button("Export Board as JSON…", action: exportBoard)
                    Button("Import…", action: chooseImport)
                        .disabled(store.isReadOnly)
                }
                if let dataNote {
                    Text(dataNote)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Import replaces the whole board. Your current board is backed up first.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Replace your board?", isPresented: Binding(
            get: { importCandidate != nil },
            set: { if !$0 { importCandidate = nil } }
        ), presenting: importCandidate) { file in
            Button("Replace Board", role: .destructive) { performImport(file) }
            Button("Cancel", role: .cancel) {}
        } message: { file in
            Text("Your \(store.stats.total + store.archived.count) current tasks will be replaced by the \(file.cards.count) in this file. A backup of the current board is saved first.")
        }
        .onAppear { refreshLoginNote() }
    }

    // MARK: - Bindings

    private var wipLimit: Binding<Int?> {
        Binding(get: { store.settings.wipLimit }, set: { value in store.updateSettings { $0.wipLimit = value } })
    }

    private var archiveDays: Binding<Int> {
        Binding(get: { store.settings.archiveAfterDays }, set: { value in store.updateSettings { $0.archiveAfterDays = value } })
    }

    private var showStrip: Binding<Bool> {
        Binding(get: { store.settings.showSummaryStrip }, set: { value in store.updateSettings { $0.showSummaryStrip = value } })
    }

    // MARK: - Launch at login

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            loginNote = "Couldn't change this: \(error.localizedDescription)"
        }
        refreshLoginNote()
    }

    private func refreshLoginNote() {
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            loginNote = "macOS needs your OK in System Settings › General › Login Items."
        case .enabled:
            loginNote = nil
            if !launchAtLogin { launchAtLogin = true }
        default:
            if launchAtLogin, SMAppService.mainApp.status == .notFound {
                loginNote = "Move Kanban Board to Applications to launch it at login."
            }
        }
    }

    // MARK: - Export / import

    private func exportBoard() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let stamp = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "Kanban Board \(stamp).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            dataNote = "Exported \(store.stats.total + store.archived.count) tasks."
        } catch {
            dataNote = "Couldn't export: \(error.localizedDescription)"
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            dataNote = "Couldn't open that file."
            return
        }
        switch BoardCoding.decode(data) {
        case .board(let file):
            importCandidate = file
        case .newerSchema:
            dataNote = "That file is from a newer version of Kanban Board, so it can't be imported."
        case .corrupt:
            dataNote = "That file isn't an Kanban Board board."
        }
    }

    private func performImport(_ file: BoardFile) {
        do {
            try store.importBoard(file)
            dataNote = "Imported \(file.cards.count) tasks. The previous board was backed up."
        } catch {
            dataNote = "Couldn't import: \(error.localizedDescription)"
        }
        importCandidate = nil
    }
}
