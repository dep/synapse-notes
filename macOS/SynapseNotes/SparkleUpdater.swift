import Sparkle

/// Wraps Sparkle's standard updater controller to provide a ``checkForUpdates()`` action
/// for the app's menu and lifecycle.
final class SparkleUpdater: NSObject, ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
