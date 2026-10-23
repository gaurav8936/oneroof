import Foundation
import OneRoofCore

extension AppModel {
    /// LAB-675: the model is downloaded and checked. Point Settings at it (unless you chose another model of your
    /// own), stop the server running the old one so the next question starts the new one, and check again.
    func modelDownloaded() {
        let next = LocalModel.settingAfterDownload(settings.localModelPath)
        if next != settings.localModelPath { settings.localModelPath = next }
        DispatchQueue.global(qos: .utility).async {
            LocalModel.shared.stop()
            ResourceMonitor.stopLeftoverLocalModel()
        }
        runFoundations()
    }
}
