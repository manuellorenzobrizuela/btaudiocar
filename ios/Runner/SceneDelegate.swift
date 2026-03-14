import Flutter
import UIKit
import AVFoundation

class SceneDelegate: FlutterSceneDelegate {
  private var scoChannel: FlutterMethodChannel?
  private var silencePlayer: AVAudioPlayer?
  private var silenceTimer: Timer?

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
      // mixWithOthers: allows other apps' audio to play through the same route
      // allowBluetooth: forces HFP profile
      try session.setCategory(
        .playAndRecord,
        options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker]
      )
      try session.setActive(true)

      // Find BT HFP input and set it as preferred
      let inputs = session.availableInputs ?? []
      for input in inputs {
        if input.portType == .bluetoothHFP {
          try session.setPreferredInput(input)
          break
        }
      }

      // Re-activate after setting preferred input
      try session.setActive(true)

      // Check the actual route
      let route = session.currentRoute
      var btDeviceName: String? = nil
      for output in route.outputs {
        if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP {
          btDeviceName = output.portName
          break
        }
      }

      if btDeviceName == nil {
        // Check inputs too
        for input in route.inputs {
          if input.portType == .bluetoothHFP {
            btDeviceName = input.portName
            break
          }
        }
      }

      if btDeviceName != nil {
        // Start playing silence to keep the HFP channel alive
        startSilenceLoop()
        result([
          "success": true,
          "deviceName": btDeviceName!
        ])
      } else {
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

  private func startSilenceLoop() {
    stopSilenceLoop()

    // Generate a tiny silent WAV in memory (1 second, 8kHz mono, 16-bit)
    let sampleRate: Int = 8000
    let numSamples = sampleRate // 1 second
    let bitsPerSample = 16
    let numChannels = 1
    let dataSize = numSamples * numChannels * (bitsPerSample / 8)
    let fileSize = 44 + dataSize

    var wav = Data()
    // RIFF header
    wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
    wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    // fmt chunk
    wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(numChannels)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(sampleRate)).littleEndian) { Array($0) })
    let byteRate = sampleRate * numChannels * (bitsPerSample / 8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(byteRate)).littleEndian) { Array($0) })
    let blockAlign = numChannels * (bitsPerSample / 8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(blockAlign)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(bitsPerSample)).littleEndian) { Array($0) })
    // data chunk
    wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(dataSize)).littleEndian) { Array($0) })
    // Silent samples (all zeros)
    wav.append(Data(count: dataSize))

    do {
      silencePlayer = try AVAudioPlayer(data: wav)
      silencePlayer?.numberOfLoops = -1 // loop forever
      silencePlayer?.volume = 0.01 // near-silent
      silencePlayer?.play()
    } catch {
      print("BT Audio Car: silence player error: \(error)")
    }
  }

  private func stopSilenceLoop() {
    silencePlayer?.stop()
    silencePlayer = nil
  }

  private func stopSco(result: @escaping FlutterResult) {
    stopSilenceLoop()
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
