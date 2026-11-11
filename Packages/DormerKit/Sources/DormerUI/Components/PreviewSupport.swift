import SwiftUI

/// Wraps a preview with a loaded sample ``AppModel``.
struct PreviewHost<Content: View>: View {
    @State private var model = AppModel.preview()
    private let content: (AppModel) -> Content

    init(@ViewBuilder content: @escaping (AppModel) -> Content) {
        self.content = content
    }

    var body: some View {
        Group {
            if model.isLoaded {
                content(model)
            } else {
                ProgressView()
            }
        }
        .environment(model)
        .task { await model.load() }
    }
}
