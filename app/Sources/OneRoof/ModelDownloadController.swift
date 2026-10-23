import Foundation
import OneRoofCore

/// LAB-675 · Get the model, shared by Settings and the Foundations check: one download at a time into
/// `LocalModel.defaultModelPath`, with the bundled licence copied next to it.
final class ModelDownloadController: ObservableObject {
    @Published private(set) var state: ModelDownload.State = .idle
    /// Called on the main queue once the file is in place and checked.
    var onDone: ((String) -> Void)?
    private var downloader: ModelDownloader?

    func start() {
        if downloader == nil {
            let d = ModelDownloader(spec: LocalModel.download, destination: LocalModel.defaultModelPath, licenceSource: AppResources.modelLicence)
            d.onState = { [weak self] s in
                self?.state = s
                if case let .done(path) = s { self?.onDone?(path) }
            }
            downloader = d
        }
        downloader?.start()
    }

    func cancel() { downloader?.cancel() }
}
