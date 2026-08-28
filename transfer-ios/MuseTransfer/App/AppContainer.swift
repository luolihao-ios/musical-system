import Foundation

@MainActor
final class AppContainer {
    let browser = NearbyDeviceBrowser()
    let sender = TransferClient()
    let receiver: ReceiverServer
    let history: TransferHistoryStore
    let musicHandoff = MuseMusicHandoff()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "MuseTransfer", directoryHint: .isDirectory)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Received", directoryHint: .isDirectory)
        receiver = ReceiverServer(destination: documents, temporaryRoot: support.appending(path: "Incoming", directoryHint: .isDirectory))
        history = TransferHistoryStore(url: support.appending(path: "history-v1.json"))
    }
}
