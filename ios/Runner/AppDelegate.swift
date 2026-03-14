import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var scoChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      scoChannel = FlutterMethodChannel(
        name: "com.btaudiocar/sco",
        binaryMessenger: controller.binaryMessenger
      )
      scoChannel?.setMethodCallHandler(handleMethodCall)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
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
      // .allowBluetooth forces HFP profile (mono, hands-free)
      try session.setCategory(
        .playAndRecord,
        options: [.allowBluetooth, .defaultToSpeaker]
      )
      try session.setActive(true)

      // Check if routed to Bluetooth
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
        // HFP not available, but audio session is set
        // Try to find any BT input
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
