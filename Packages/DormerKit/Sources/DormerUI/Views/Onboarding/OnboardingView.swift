import DormerCore
import SwiftUI

/// First-launch flow: Rosetta → Wine runtime → first bottle.
struct OnboardingView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case rosetta, runtime, bottle
        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .rosetta: "Rosetta"
            case .runtime: "Motor Wine"
            case .bottle: "Primera botella"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .rosetta

    var body: some View {
        VStack(spacing: 0) {
            StepIndicator(current: step)
                .padding(.top, 24)
                .padding(.bottom, 16)
            Divider()
            Group {
                switch step {
                case .rosetta: RosettaStep { advance() }
                case .runtime: RuntimeStep { advance() }
                case .bottle: FirstBottleStep { finish() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .transition(
                .asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)).combined(with: .opacity)
            )
            .id(step)
        }
        .frame(width: 560, height: 460)
        .interactiveDismissDisabled()
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.snappy) { step = next }
    }

    private func finish() {
        model.hasCompletedOnboarding = true
        dismiss()
    }
}

private struct StepIndicator: View {
    let current: OnboardingView.Step

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingView.Step.allCases) { step in
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(step.rawValue <= current.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                            .frame(width: 24, height: 24)
                        if step.rawValue < current.rawValue {
                            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                        } else {
                            Text(verbatim: "\(step.rawValue + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(step == current ? .white : .secondary)
                        }
                    }
                    Text(step.title)
                        .font(.callout)
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
                if step != OnboardingView.Step.allCases.last {
                    Rectangle()
                        .fill(step.rawValue < current.rawValue ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 40, height: 2)
                        .padding(.horizontal, 10)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Paso \(current.rawValue + 1) de 3"))
        .accessibilityValue(Text(current.title))
    }
}

// MARK: - Step 1: Rosetta

private struct RosettaStep: View {
    @Environment(AppModel.self) private var model
    let onContinue: () -> Void
    @State private var status: RosettaStatus?
    @State private var isInstalling = false
    @State private var showsRosettaInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rosetta 2").font(.title2.bold())
            Text(
                "Los motores Wine gratuitos para Mac están hechos para procesadores Intel. Rosetta 2, de Apple, los traduce para que funcionen en tu Mac con Apple Silicon."
            )
            .fixedSize(horizontal: false, vertical: true)

            Group {
                switch status {
                case nil:
                    ProgressView().controlSize(.small)
                case .installed, .notRequired:
                    Label("Rosetta está listo.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .notInstalled:
                    Label(
                        "Rosetta no está instalado. Al pulsar Instalar aceptas la licencia de Rosetta de Apple; macOS te pedirá tu contraseña.",
                        systemImage: "exclamationmark.circle"
                    )
                    .foregroundStyle(.orange)
                }
            }
            .font(.callout)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text("Apple limitará Rosetta a partir de macOS 28.")
                Button("Saber más") { showsRosettaInfo.toggle() }
                    .buttonStyle(.link)
                    .popover(isPresented: $showsRosettaInfo) {
                        Text(
                            "Apple anunció que Rosetta seguirá completo hasta macOS 27 y que en macOS 28 solo quedará para algunos juegos antiguos. Dormer está preparado para cambiar a un motor Wine nativo para Apple Silicon cuando exista uno gratuito; si Rosetta deja de funcionar, la app te lo dirá claramente."
                        )
                        .frame(width: 320)
                        .padding()
                    }
            }
            .font(.callout)

            Spacer()
            HStack {
                Spacer()
                if status == .notInstalled {
                    Button(isInstalling ? "Instalando…" : "Instalar Rosetta") {
                        Task {
                            isInstalling = true
                            defer { isInstalling = false }
                            do {
                                try await model.runtimeService.installRosetta()
                                status = await model.runtimeService.rosettaStatus()
                            } catch {
                                model.present(error, title: "No se pudo instalar Rosetta")
                            }
                        }
                    }
                    .disabled(isInstalling)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Continuar", action: onContinue)
                        .keyboardShortcut(.defaultAction)
                        .disabled(status == nil)
                }
            }
        }
        .task { status = await model.runtimeService.rosettaStatus() }
    }
}

// MARK: - Step 2: Wine runtime

private struct RuntimeStep: View {
    @Environment(AppModel.self) private var model
    let onContinue: () -> Void

    @State private var runtime: WineRuntimeDescriptor?
    @State private var phase: Phase = .idle
    @State private var installTask: Task<Void, Never>?

    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double, detail: String)
        case verifying
        case extracting
        case done
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Motor Wine").font(.title2.bold())
            Text(
                "Wine es el software libre que permite abrir programas de Windows. Dormer lo descarga una sola vez y comprueba que el archivo no haya sido alterado."
            )
            .fixedSize(horizontal: false, vertical: true)

            if let runtime {
                GroupBox {
                    HStack(spacing: 12) {
                        Image(systemName: "wineglass")
                            .font(.title)
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(runtime.displayName).font(.headline)
                            Text("Compilación de Gcenx · \(Formatters.bytes(runtime.sizeBytes)) · \(runtime.license)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }

            progressView

            if model.isPreview {
                Label("Vista previa: la descarga es simulada.", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            HStack {
                Spacer()
                switch phase {
                case .idle:
                    Button("Descargar e instalar", action: install)
                        .keyboardShortcut(.defaultAction)
                        .disabled(runtime == nil)
                case .failed:
                    Button("Reintentar", action: install)
                        .keyboardShortcut(.defaultAction)
                case .done:
                    Button("Continuar", action: onContinue)
                        .keyboardShortcut(.defaultAction)
                default:
                    Button("Cancelar", role: .cancel) {
                        installTask?.cancel()
                        phase = .idle
                    }
                }
            }
        }
        .task {
            do {
                runtime = try await model.runtimeService.recommendedRuntime()
                if let runtime, model.installedRuntimes.contains(where: { $0.id == runtime.id }), !model.isPreview {
                    phase = .done
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
        .onDisappear { installTask?.cancel() }
    }

    @ViewBuilder
    private var progressView: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .downloading(let fraction, let detail):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction)
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Descargando Wine")
        case .verifying:
            ProgressView { Text("Verificando la suma SHA-256…") }.progressViewStyle(.linear)
        case .extracting:
            ProgressView { Text("Descomprimiendo…") }.progressViewStyle(.linear)
        case .done:
            Label("Wine está instalado y verificado.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func install() {
        guard let runtime else { return }
        phase = .downloading(fraction: 0, detail: "")
        installTask = Task {
            do {
                for try await progress in model.runtimeService.install(runtime) {
                    switch progress {
                    case .downloading(let received, let total, let speed):
                        let fraction = total > 0 ? Double(received) / Double(total) : 0
                        let detail =
                            "\(Formatters.bytes(received)) de \(Formatters.bytes(total)) · \(Formatters.bytes(Int64(speed)))/s"
                        phase = .downloading(fraction: fraction, detail: detail)
                    case .verifying:
                        phase = .verifying
                    case .extracting:
                        phase = .extracting
                    case .finished(let installed):
                        model.runtimeInstalled(installed)
                        phase = .done
                    }
                }
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Step 3: First bottle

private struct FirstBottleStep: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void
    @State private var name = String(localized: "Mis programas")
    @State private var windowsVersion: WindowsVersion = .windows10
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Crea tu primera botella").font(.title2.bold())
            Text(
                "Cada botella es un Windows aislado. Puedes tener una para cada programa o agrupar varios en la misma."
            )
            .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Nombre", text: $name)
                Picker("Windows", selection: $windowsVersion) {
                    ForEach(WindowsVersion.allCases) { Text($0.displayName).tag($0) }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 120)
            Spacer()
            HStack {
                Button("Omitir", action: onFinish)
                Spacer()
                Button(isCreating ? "Creando…" : "Crear botella") {
                    Task {
                        isCreating = true
                        await model.createBottle(
                            named: name, symbolName: Bottle.defaultSymbolName, windowsVersion: windowsVersion)
                        isCreating = false
                        onFinish()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            }
        }
    }
}

#Preview("Claro") {
    PreviewHost { _ in OnboardingView() }
}

#Preview("Oscuro") {
    PreviewHost { _ in OnboardingView() }
        .preferredColorScheme(.dark)
}
