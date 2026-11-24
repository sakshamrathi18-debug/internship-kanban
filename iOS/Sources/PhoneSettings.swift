import CoreTransferable
import KanbanCore
import SwiftUI
import UniformTypeIdentifiers

/// Work-in-progress limit, archive window, summary line, export and import.
struct PhoneSettings: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var importCandidate: BoardFile?
    @State private var dataNote: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Board") {
                    Picker("Work-in-progress limit", selection: wipLimit) {
                        Text("Off").tag(Int?.none)
                        ForEach(BoardSettings.wipLimitRange, id: \.self) { value in
                            Text("\(value)").tag(Int?.some(value))
                        }
                    }
                    Stepper(value: archiveDays, in: BoardSettings.archiveDaysRange) {
                        LabeledContent("Archive Done after", value: "\(store.settings.archiveAfterDays) days")
                    }
                    Toggle("Show summary", isOn: showSummary)
                }
                .listRowBackground(Palette.fill(.none))

                Section {
                    ShareLink(item: BoardExport(data: (try? store.exportData()) ?? Data()),
                              preview: SharePreview("Kanban Board")) {
                        Label("Export Board", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("Import Board…", systemImage: "square.and.arrow.down")
                    }
                    .disabled(store.isReadOnly)
                    if let dataNote {
                        Text(dataNote)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Export saves the whole board as a file. Import replaces the board; your current one is backed up first.")
                }
                .listRowBackground(Palette.fill(.none))

                Section {
                    LabeledContent("Tasks", value: "\(store.stats.total + store.archived.count)")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
                .listRowBackground(Palette.fill(.none))
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { read(url) }
            }
            .alert("Replace your board?", isPresented: Binding(
                get: { importCandidate != nil },
                set: { if !$0 { importCandidate = nil } }
            ), presenting: importCandidate) { file in
                Button("Replace Board", role: .destructive) { performImport(file) }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text("Your \(store.stats.total + store.archived.count) current tasks will be replaced by the \(file.cards.count) in this file. A backup of the current board is saved first.")
            }
        }
        .tint(Palette.appAccent)
        .presentationBackground(Palette.background)
    }

    // MARK: - Bindings

    private var wipLimit: Binding<Int?> {
        Binding(get: { store.settings.wipLimit }, set: { value in store.updateSettings { $0.wipLimit = value } })
    }

    private var archiveDays: Binding<Int> {
        Binding(get: { store.settings.archiveAfterDays }, set: { value in store.updateSettings { $0.archiveAfterDays = value } })
    }

    private var showSummary: Binding<Bool> {
        Binding(get: { store.settings.showSummaryStrip }, set: { value in store.updateSettings { $0.showSummaryStrip = value } })
    }

    // MARK: - Import

    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
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
            dataNote = "That file isn't a Kanban Board board."
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

/// The board as a .json file for the share sheet.
struct BoardExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("Kanban Board.json")
    }
}
