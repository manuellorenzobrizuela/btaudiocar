import Flutter
import UIKit
import AVFoundation

class SceneDelegate: FlutterSceneDelegate {
  private var scoChannel: FlutterMethodChannel?
  private var mediaChannel: FlutterMethodChannel?
  private var silencePlayer: AVAudioPlayer?
  private var routeChangeObserver: NSObjectProtocol?
  private var interruptionObserver: NSObjectProtocol?
  private var isActive = false

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
      scoChannel?.setMethodCallHandler(handleScoCall)

      mediaChannel = FlutterMethodChannel(
        name: "com.btaudiocar/media",
        binaryMessenger: controller.binaryMessenger
      )
      mediaChannel?.setMethodCallHandler(handleMediaCall)
    }
  }

  // MARK: - SCO

  private func handleScoCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
        mode: .voiceChat,
        options: [.allowBluetooth]
      )

      try session.setPreferredSampleRate(16000)
      try session.setPreferredIOBufferDuration(0.005)

      let inputs = session.availableInputs ?? []
      for input in inputs {
        if input.portType == .bluetoothHFP {
          try session.setPreferredInput(input)
          break
        }
      }

      try session.setActive(true, options: .notifyOthersOnDeactivation)

      let route = session.currentRoute
      var btDeviceName: String? = nil

      for output in route.outputs {
        if output.portType == .bluetoothHFP || output.portType == .bluetoothA2DP {
          btDeviceName = output.portName
          break
        }
      }
      if btDeviceName == nil {
        for input in route.inputs {
          if input.portType == .bluetoothHFP {
            btDeviceName = input.portName
            break
          }
        }
      }

      if btDeviceName != nil {
        isActive = true
        startSilenceLoop(sampleRate: session.sampleRate)
        startRouteChangeObserver()
        startInterruptionObserver()

        let actualRate = Int(session.sampleRate)
        let codec = actualRate >= 16000 ? "mSBC (wide-band)" : "CVSD (narrow-band)"

        result([
          "success": true,
          "deviceName": btDeviceName!,
          "sampleRate": actualRate,
          "codec": codec
        ])
      } else {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
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

  // MARK: - Silence loop

  private func startSilenceLoop(sampleRate: Double) {
    stopSilenceLoop()

    let rate = Int(sampleRate)
    let numChannels = 1
    let bitsPerSample = 16
    let numSamples = rate * 2
    let dataSize = numSamples * numChannels * (bitsPerSample / 8)
    let fileSize = 44 + dataSize

    var wav = Data(capacity: fileSize)
    wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
    wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
    wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(numChannels)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(rate)).littleEndian) { Array($0) })
    let byteRate = rate * numChannels * (bitsPerSample / 8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(byteRate)).littleEndian) { Array($0) })
    let blockAlign = numChannels * (bitsPerSample / 8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(blockAlign)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(bitsPerSample)).littleEndian) { Array($0) })
    wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(dataSize)).littleEndian) { Array($0) })
    wav.append(Data(count: dataSize))

    do {
      silencePlayer = try AVAudioPlayer(data: wav)
      silencePlayer?.numberOfLoops = -1
      silencePlayer?.volume = 0.01
      silencePlayer?.prepareToPlay()
      silencePlayer?.play()
    } catch {
      print("BT Audio Car: silence player error: \(error)")
    }
  }

  private func stopSilenceLoop() {
    silencePlayer?.stop()
    silencePlayer = nil
  }

  // MARK: - Route change observer

  private func startRouteChangeObserver() {
    stopRouteChangeObserver()
    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self, self.isActive else { return }

      let session = AVAudioSession.sharedInstance()
      let hasBT = session.currentRoute.outputs.contains { $0.portType == .bluetoothHFP }
        || session.currentRoute.inputs.contains { $0.portType == .bluetoothHFP }

      if !hasBT {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          guard let self = self, self.isActive else { return }
          do {
            let inputs = session.availableInputs ?? []
            for input in inputs {
              if input.portType == .bluetoothHFP {
                try session.setPreferredInput(input)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                self.startSilenceLoop(sampleRate: session.sampleRate)
                break
              }
            }
          } catch {
            print("BT Audio Car: reconnect failed: \(error)")
          }
        }
      }
    }
  }

  private func stopRouteChangeObserver() {
    if let observer = routeChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      routeChangeObserver = nil
    }
  }

  // MARK: - Interruption observer

  private func startInterruptionObserver() {
    stopInterruptionObserver()
    interruptionObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self, self.isActive else { return }

      let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
      if type == AVAudioSession.InterruptionType.ended.rawValue {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
          guard let self = self, self.isActive else { return }
          let session = AVAudioSession.sharedInstance()
          do {
            try session.setCategory(
              .playAndRecord,
              mode: .voiceChat,
              options: [.allowBluetooth]
            )
            try session.setPreferredSampleRate(16000)
            try session.setPreferredIOBufferDuration(0.005)

            let inputs = session.availableInputs ?? []
            for input in inputs {
              if input.portType == .bluetoothHFP {
                try session.setPreferredInput(input)
                break
              }
            }

            try session.setActive(true, options: .notifyOthersOnDeactivation)
            self.startSilenceLoop(sampleRate: session.sampleRate)
          } catch {
            print("BT Audio Car: failed to restore after call: \(error)")
          }
        }
      }
    }
  }

  private func stopInterruptionObserver() {
    if let observer = interruptionObserver {
      NotificationCenter.default.removeObserver(observer)
      interruptionObserver = nil
    }
  }

  // MARK: - Stop SCO

  private func stopSco(result: @escaping FlutterResult) {
    isActive = false
    stopSilenceLoop()
    stopRouteChangeObserver()
    stopInterruptionObserver()
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback)
      try session.setActive(true)
      result(nil)
    } catch {
      result(nil)
    }
  }

  // MARK: - Media (iOS: limited - no cross-app API)

  private func handleMediaCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getNowPlaying":
      // iOS has no public API to read now playing from third-party apps (Spotify, etc.)
      // Only isOtherAudioPlaying is available
      let session = AVAudioSession.sharedInstance()
      result([
        "title": NSNull(),
        "artist": NSNull(),
        "playing": session.isOtherAudioPlaying
      ])
    case "playPause", "next", "previous":
      // iOS has no public API to control third-party media apps
      // User must control from Spotify/music app or Control Center
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
