import AppKit
import DormerCore
import SwiftUI
import UniformTypeIdentifiers

/// Live Wine output with filters, suggestions, export and "copy for report".
struct LogsView: View {
    @Environment(AppModel.self) private var model
    let bottleID: UUID
    @State private var searchText = ""
    @State private var visibleLevels: Set<LogLine.Level> = [.error, .warning, .fixme, .info]
    @State private var isExporting = false
    @State private var didCopy = false

    private var sessions: [LogSession] { model.sessions(for: bottleID) }

    private var session: LogSession? {
        sessions.first { $0.id == model.selectedLogSessionID } ?? sessions.first
    }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                filterBar(for: session)
                Divider()
                LogLinesView(session: session, searchText: searchText, visibleLevels: visibleLevels)
                Divider()
                footer(for: session)
            } else {
                ContentUnavailableView(
                    "Sin registros", systemImage: "doc.text.magnifyingglass",
                    description: Text("Abre un programa de esta botella para ver aquí lo que dice Wine, en vivo."))
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: PlainTextDocument(text: session.map { $0.lines.map(\.raw).joined(separator: "\n") } ?? ""),
            contentType: .plainText,
            defaultFilename: session.map { "\($0.title)-log.txt" } ?? "log.txt"
        ) { _ in }
    }

    // MARK: Bars

    private func filterBar(for session: LogSession) -> some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Picker("Sesión", selection: Binding(get: { session.id }, set: { model.selectedLogSessionID = $0 })) {
                ForEach(sessions) { item in
                    Text("\(item.title) · \(item.startedAt, format: Formatters.time)").tag(item.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 260)

            TextField("Filtrar", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)

            HStack(spacing: 4) {
                ForEach([LogLine.Level.error, .warning, .fixme, .info]) { level in
                    Toggle(
                        isOn: Binding(
                            get: { visibleLevels.contains(level) },
                            set: { isOn in
                                if isOn { visibleLevels.insert(level) } else { visibleLevels.remove(level) }
                            }
                        )
                    ) {
                        Text(level.title)
                    }
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }

            Spacer()

            if session.isLive {
                Label("En vivo", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .symbolEffect(.pulse)
            } else if let status = session.exitStatus {
                Text("Terminó · código \(status)")
                    .font(.caption)
                    .foregroundStyle(status == 0 ? Color.secondary : Color.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func footer(for session: LogSession) -> some View {
        let suggestions = LogDiagnostics.suggestions(for: session.lines)
        return HStack(spacing: 10) {
            if let suggestion = suggestions.first {
                Label {
                    Text("Falta \(suggestion.missingComponent).")
                } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                }
                Button("Instalar \(suggestion.winetricksVerb)") {
                    model.activeSheet = .winetricks(
                        bottleID: bottleID, preselected: Set(suggestions.map(\.winetricksVerb)))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer()
            Button(didCopy ? "Copiado" : "Copiar para reporte", systemImage: didCopy ? "checkmark" : "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.diagnosticReport(for: session), forType: .string)
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    didCopy = false
                }
            }
            .help("Copia la información del sistema y el registro, sin tu nombre de usuario ni rutas personales")
            Button("Exportar…", systemImage: "square.and.arrow.up") { isExporting = true }
            Button("Limpiar", systemImage: "trash") { model.clearLogs(in: bottleID) }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// The scrolling list of lines; auto-scrolls while the session is live.
private struct LogLinesView: View {
    let session: LogSession
    let searchText: String
    let visibleLevels: Set<LogLine.Level>

    private var filtered: [LogLine] {
        session.lines.filter { line in
            let levelVisible = visibleLevels.contains(line.level == .trace ? .info : line.level)
            return levelVisible && (searchText.isEmpty || line.raw.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        let lines = filtered
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(lines) { line in
                        LogLineRow(line: line)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .overlay {
                if lines.isEmpty {
                    Text(session.lines.isEmpty ? "Esperando salida de Wine…" : "Ninguna línea coincide con el filtro.")
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: session.lines.count) {
                guard session.isLive, let last = lines.last else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
    }
}

private struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(line.timestamp, format: Formatters.time)
                .foregroundStyle(.tertiary)
            Text(line.raw)
                .foregroundStyle(line.level.color)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout.monospaced())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(line.level.title) + Text(verbatim: ": ") + Text(line.message))
    }
}

/// Minimal document used to export a log as `.txt`.
struct PlainTextDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

#Preview {
    PreviewHost { model in
        LogsView(bottleID: model.bottles[1].id)
            .task { await model.launch(model.bottles[1].pinnedPrograms[1], in: model.bottles[1].id) }
    }
    .frame(width: 820, height: 420)
}
