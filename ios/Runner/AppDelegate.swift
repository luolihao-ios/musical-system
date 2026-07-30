import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "LocalMusicLibrary"
    ) else { return }
    let channel = FlutterMethodChannel(
      name: "local_music_player/media_library",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestAccess":
        MPMediaLibrary.requestAuthorization { status in
          let value: String
          switch status {
          case .authorized: value = "authorized"
          case .denied: value = "denied"
          case .restricted: value = "restricted"
          case .notDetermined: value = "notDetermined"
          @unknown default: value = "restricted"
          }
          DispatchQueue.main.async { result(value) }
        }
      case "listTracks":
        guard MPMediaLibrary.authorizationStatus() == .authorized else {
          result(FlutterError(code: "permission_denied", message: "音乐资料库未授权", details: nil))
          return
        }
        let rows = (MPMediaQuery.songs().items ?? []).map { item in
          [
            "id": String(item.persistentID),
            "title": item.title ?? "未知歌曲",
            "artist": item.artist ?? "未知歌手",
            "album": item.albumTitle as Any,
            "uri": item.assetURL?.absoluteString as Any,
            "durationMs": item.playbackDuration * 1000,
          ] as [String: Any]
        }
        result(rows)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
