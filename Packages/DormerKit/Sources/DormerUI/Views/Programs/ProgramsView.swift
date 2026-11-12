import BottleManager
import DormerCore
import SwiftUI

/// Pinned programs grid, detected executables and the drop zone.
struct ProgramsView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle
    @State private var isDropTargeted = false
    @State private var showsHelperExecutables = false

    private var detected: [Program] {
        let unpinned = model.unpinnedDetectedPrograms(in: bottle)
        return showsHelperExecutables ? unpinned : unpinned.filter(ProgramDiscoveryFilter.isUserFacing)
    }

    private var hiddenCount: Int {
        model.unpinnedDetectedPrograms(in: bottle).count { !ProgramDiscoveryFilter.isUserFacing($0) }
    }

    var body: some View {
        Group {
            if bottle.pinnedPrograms.isEmpty && model.unpinnedDetectedPrograms(in: bottle).isEmpty {
                EmptyProgramsView(bottleName: bottle.name, isDropTargeted: isDropTargeted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        pinnedSection
                        detectedSection
                        DropZone(bottleName: bottle.name, isTargeted: isDropTargeted)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.handleOpenedFiles(urls, preferredBottleID: bottle.id)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.15)) { isDropTargeted = targeted }
        }
    }

    // MARK: Pinned

    @ViewBuilder
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Anclados")
            if bottle.pinnedPrograms.isEmpty {
                Text("Ancla un programa detectado para tenerlo siempre a mano.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 140), spacing: 12)], spacing: 12) {
                    ForEach(bottle.pinnedPrograms) { program in
                        ProgramTile(
                            program: program,
                            bottleID: bottle.id,
                            isRunning: model.isRunning(program, in: bottle.id),
                            onLaunch: { Task { await model.launch(program, in: bottle.id) } }
                        )
                        .contextMenu { tileMenu(for: program) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tileMenu(for program: Program) -> some View {
        Button("Abrir") { Task { await model.launch(program, in: bottle.id) } }
        Divider()
        Button("Editar…") { model.activeSheet = .editProgram(bottleID: bottle.id, programID: program.id) }
        Button("Desanclar") {
            withAnimation(.snappy) { model.unpin(program.id, in: bottle.id) }
        }
        Divider()
        Button("Crear lanzador .app…") { Task { await model.createLauncher(for: program, in: bottle.id) } }
        Button("Mostrar en Finder") { model.revealProgram(program, in: bottle.id) }
    }

    // MARK: Detected

    @ViewBuilder
    private var detectedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Detectados en esta botella")
                Spacer()
                if hiddenCount > 0 || showsHelperExecutables {
                    Toggle("Mostrar ejecutables auxiliares", isOn: $showsHelperExecutables)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("Desinstaladores, actualizadores y otros ejecutables que normalmente no abres tú")
                }
            }
            if detected.isEmpty {
                Text("No hay otros programas instalados.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(detected) { program in
                        DetectedProgramRow(
                            program: program,
                            bottleID: bottle.id,
                            onPin: { withAnimation(.snappy) { model.pin(program, in: bottle.id) } },
                            onLaunch: { Task { await model.launch(program, in: bottle.id) } }
                        )
                        if program.id != detected.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .padding(.vertical, 4)
                .surface(cornerRadius: 10)
            }
        }
    }
}

private struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tile

struct ProgramTile: View {
    let program: Program
    let bottleID: UUID
    let isRunning: Bool
    let onLaunch: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            ProgramIconView(name: program.name, size: 56, program: program, bottleID: bottleID)
                .overlay(alignment: .bottomTrailing) {
                    if isRunning {
                        RunningIndicator()
                            .padding(2)
                            .background(Circle().fill(.background))
                            .offset(x: 4, y: 4)
                    }
                }
            Text(program.name)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 118)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovering || isFocused ? Color.primary.opacity(0.07) : .clear)
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: onLaunch) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .padding(6)
                // The tile itself already opens the program (Return, double-click, accessibility action).
                .accessibilityHidden(true)
                .help("Abrir \(program.name)")
                .transition(.opacity)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
        .onTapGesture(count: 2, perform: onLaunch)
        .focusable()
        .focused($isFocused)
        .onKeyPress(.return) {
            onLaunch()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(program.name)
        .accessibilityValue(isRunning ? Text("En ejecución") : Text(""))
        .accessibilityHint("Doble clic o Retorno para abrir")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onLaunch)
    }
}

// MARK: - Detected row

private struct DetectedProgramRow: View {
    let program: Program
    let bottleID: UUID
    let onPin: () -> Void
    let onLaunch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgramIconView(name: program.name, size: 24, program: program, bottleID: bottleID)
            VStack(alignment: .leading, spacing: 1) {
                Text(program.name)
                Text(program.windowsPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            Button("Abrir", systemImage: "play.fill", action: onLaunch)
                .labelStyle(.iconOnly)
                .help("Abrir \(program.fileName)")
            Button("Anclar", systemImage: "pin", action: onPin)
                .help("Anclar \(program.fileName) arriba")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(program.fileName)
    }
}

// MARK: - Drop zone & empty state

private struct DropZone: View {
    let bottleName: String
    let isTargeted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.title2)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(
                isTargeted
                    ? "Suelta para ejecutar en «\(bottleName)»"
                    : "Suelta aquí un .exe, .msi, .bat o .iso para ejecutarlo")
        }
        .foregroundStyle(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        .frame(maxWidth: .infinity, minHeight: 72)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.clear))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: isTargeted ? [] : [6, 4]))
        }
        .scaleEffect(isTargeted ? 1.01 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyProgramsView: View {
    @Environment(AppModel.self) private var model
    let bottleName: String
    let isDropTargeted: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                isDropTargeted ? "Suelta para instalar en «\(bottleName)»" : "Esta botella aún no tiene programas",
                systemImage: isDropTargeted ? "arrow.down.circle.fill" : "macwindow.badge.plus")
        } description: {
            Text("Arrastra aquí un instalador (.exe o .msi) o elige uno desde tu Mac.")
        } actions: {
            Button("Ejecutar instalador…") { model.isFileImporterPresented = true }
                .buttonStyle(.borderedProminent)
        }
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
                    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(16)
            }
        }
    }
}

#Preview("Con programas") {
    PreviewHost { model in
        ProgramsView(bottle: model.bottles[1])
    }
    .frame(width: 720, height: 560)
}

#Preview("Vacía · oscuro") {
    PreviewHost { model in
        ProgramsView(bottle: model.bottles[2])
    }
    .frame(width: 720, height: 480)
    .preferredColorScheme(.dark)
}
