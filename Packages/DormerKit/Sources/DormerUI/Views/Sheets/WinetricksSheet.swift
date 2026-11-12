import DormerCore
import SwiftUI

/// Curated winetricks verbs with search, multi-select and progress.
struct WinetricksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottleID: UUID
    let preselected: Set<String>

    @State private var verbs: [WinetricksVerb] = []
    @State private var selection: Set<String> = []
    @State private var searchText = ""
    @State private var progress: Progress?
    @State private var installTask: Task<Void, Never>?
    @State private var loadError: String?

    struct Progress: Equatable {
        var current: String
        var index: Int
        var total: Int
        var isFinished = false
    }

    private var filtered: [WinetricksVerb] {
        guard !searchText.isEmpty else { return verbs }
        return verbs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var estimatedMinutes: Int {
        verbs.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.estimatedMinutes }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Componentes de Windows").font(.title3.bold())
                Text("Instala bibliotecas que algunos programas necesitan. Usa winetricks (LGPL).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            TextField("Buscar", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            if !model.dependencyInstaller.isAvailable {
                Label(
                    "La instalación de componentes se conecta en la Fase 4. Por ahora puedes ver la lista.",
                    systemImage: "clock"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            if let progress {
                progressView(progress)
            } else if let loadError {
                ContentUnavailableView(
                    "No se pudo cargar la lista", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(width: 480, height: 520)
        .task {
            do {
                verbs = try await model.dependencyInstaller.curatedVerbs()
                selection = preselected
            } catch {
                loadError = error.localizedDescription
            }
        }
        .onDisappear { installTask?.cancel() }
    }

    private var list: some View {
        List {
            ForEach(WinetricksVerb.Category.allCases) { category in
                let items = filtered.filter { $0.category == category }
                if !items.isEmpty {
                    Section(category.title) {
                        ForEach(items) { verb in
                            Toggle(
                                isOn: Binding(
                                    get: { selection.contains(verb.id) },
                                    set: { if $0 { selection.insert(verb.id) } else { selection.remove(verb.id) } }
                                )
                            ) {
                                HStack {
                                    Text(verb.title)
                                    Text(verbatim: verb.id)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("~\(verb.estimatedMinutes) min")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private func progressView(_ progress: Progress) -> some View {
        VStack(spacing: 14) {
            Spacer()
            if progress.isFinished {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                Text("Componentes instalados").font(.headline)
            } else {
                ProgressView(value: Double(progress.index), total: Double(progress.total))
                    .frame(maxWidth: 300)
                Text("Instalando \(progress.current) (\(progress.index + 1) de \(progress.total))…")
                    .monospacedDigit()
                Text("Puede tardar unos minutos. Algunos instaladores abren ventanas propias.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.isPreview {
                Label("Vista previa: la instalación es simulada.", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var footer: some View {
        HStack {
            if progress == nil, !selection.isEmpty {
                Text("^[\(selection.count) componente](inflect: true) · ~\(estimatedMinutes) min")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if progress?.isFinished == true {
                Button("Listo") { dismiss() }.keyboardShortcut(.defaultAction)
            } else if progress != nil {
                Button("Cancelar", role: .cancel) {
                    installTask?.cancel()
                    progress = nil
                }
            } else {
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Instalar") { install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection.isEmpty || !model.dependencyInstaller.isAvailable)
            }
        }
        .padding(16)
    }

    private func install() {
        guard let bottle = model.bottle(withID: bottleID) else { return }
        let ordered = verbs.map(\.id).filter(selection.contains)
        progress = Progress(current: ordered.first ?? "", index: 0, total: ordered.count)
        installTask = Task {
            do {
                for try await event in model.dependencyInstaller.install(verbs: ordered, in: bottle) {
                    if case .started(let verb, let index, let total) = event {
                        progress = Progress(current: verb, index: index, total: total)
                    }
                }
                progress?.isFinished = true
            } catch is CancellationError {
                progress = nil
            } catch {
                progress = nil
                model.present(error, title: "No se pudieron instalar los componentes")
            }
        }
    }
}

#Preview {
    PreviewHost { model in
        WinetricksSheet(bottleID: model.bottles[1].id, preselected: ["vcrun2022"])
    }
}
