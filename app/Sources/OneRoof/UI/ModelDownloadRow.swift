import SwiftUI
import OneRoofCore

/// LAB-675 · Get the model: the button, progress and result line, in Settings' model row and the Foundations check.
struct ModelDownloadRow: View {
    @ObservedObject var download: ModelDownloadController
    /// The model in use is missing or is Arch-Router.
    var offer: Bool

    private var retry: Bool {
        switch download.state { case .failed, .cancelled: return true; default: return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if download.state.isBusy {
                    if let f = download.state.fraction {
                        ProgressView(value: f).frame(width: 180).accessibilityLabel("Model download, \(Int(f * 100)) percent")
                    } else {
                        ProgressView().controlSize(.small).accessibilityLabel("Checking the model file")
                    }
                    Button("Stop") { download.cancel() }.controlSize(.small)
                        .help("Stops the download; Get the model continues from where it stopped")
                } else if offer || retry {
                    Button(retry ? "Get the model again" : "Get the model (\(ModelDownload.size(LocalModel.downloadBytes)))") { download.start() }
                        .controlSize(.small)
                        .help("Downloads \(LocalModel.modelFileName) (\(LocalModel.displayName), Apache-2.0) from Hugging Face into ~/Library/Application Support/One Roof/models/, checks its SHA-256, and puts its licence next to it")
                }
            }
            if !download.state.text.isEmpty {
                Text(download.state.text).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
