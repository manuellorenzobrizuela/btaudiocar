import Flutter
import UIKit
import AVFoundation

class SceneDelegate: FlutterSceneDelegate {
  private var scoChannel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    if let windowScene = scene as? UIWindowScene,
       let controller = windowScene.windows.first?.rootViewController as? FlutterViewController {
      scoChannel = FlutterMethodChannel(
        name: "com.btaudiocar/sco",
        binaryMessenger: controller.binaryMessenger
      )
      scoChannel?.setMethodCallHandler(handleMethodCall)
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startSco":
      startSco(result: result)
    case "stopSco":
      stopSco(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startSco(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        options: [.allowBluetooth, .defaultToSpeaker]
      )
      try session.setActive(true)

      let route = session.currentRoute
      var btDeviceName: String? = nil
      for output in route.outputs {
        if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP {
          btDeviceName = output.portName
          break
        }
      }

      if btDeviceName != nil {
        result([
          "success": true,
          "deviceName": btDeviceName!
        ])
      } else {
        let inputs = session.availableInputs ?? []
        for input in inputs {
          if input.portType == .bluetoothHFP {
            try session.setPreferredInput(input)
            try session.setActive(true)
            result([
              "success": true,
              "deviceName": input.portName
            ])
            return
          }
        }
        result([
          "success": false,
          "error": "No se encontró manos libres Bluetooth conectado"
        ])
      }
    } catch {
      result([
        "success": false,
        "error": "Error: \(error.localizedDescription)"
      ])
    }
  }

  private func stopSco(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback)
      try session.setActive(true)
      result(nil)
    } catch {
      result(nil)
    }
  }
}
