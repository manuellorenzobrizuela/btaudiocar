import Flutter
import UIKit
import AVFoundation
import MediaPlayer

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
      // 1. Configure category with ONLY .allowBluetooth (forces HFP)
      //    No .defaultToSpeaker (fights with BT routing)
      //    No .mixWithOthers (reduces priority)
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,  // Optimized for HFP, enables echo cancellation
        options: [.allowBluetooth]
      )

      // 2. Request 16kHz sample rate for wide-band mSBC codec
      //    If device doesn't support it, iOS falls back to 8kHz CVSD automatically
      //    mSBC sounds MUCH better than CVSD (16kHz vs 8kHz)
      try session.setPreferredSampleRate(16000)

      // 3. Set small IO buffer for lower latency (better sync)
      try session.setPreferredIOBufferDuration(0.005)  // 5ms

      // 4. Select HFP input BEFORE activating (faster negotiation)
      let inputs = session.availableInputs ?? []
      for input in inputs {
        if input.portType == .bluetoothHFP {
          try session.setPreferredInput(input)
          break
        }
      }

      // 5. Activate session (only once)
      try session.setActive(true, options: .notifyOthersOnDeactivation)

      // 6. Verify route
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

        // Report actual codec info
        let actualRate = Int(session.sampleRate)
        let codec = actualRate >= 16000 ? "mSBC (wide-band)" : "CVSD (narrow-band)"
        print("BT Audio Car: connected at \(actualRate)Hz (\(codec))")

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

  // MARK: - Silence loop (keeps HFP channel alive)

  private func startSilenceLoop(sampleRate: Double) {
    stopSilenceLoop()

    // Use the ACTUAL session sample rate (16000 if mSBC, 8000 if CVSD)
    // This avoids resampling artifacts that degrade quality
    let rate = Int(sampleRate)
    let numChannels = 1
    let bitsPerSample = 16
    // Generate 2 seconds of silence (longer = fewer wakeups = less CPU)
    let numSamples = rate * 2
    let dataSize = numSamples * numChannels * (bitsPerSample / 8)
    let fileSize = 44 + dataSize

    var wav = Data(capacity: fileSize)
    // RIFF header
    wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
    wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
    // fmt chunk
    wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(numChannels)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(rate)).littleEndian) { Array($0) })
    let byteRate = rate * numChannels * (bitsPerSample / 8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(byteRate)).littleEndian) { Array($0) })
    let blockAlign = numChannels * (bitsPerSample / 8)
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(blockAlign)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(bitsPerSample)).littleEndian) { Array($0) })
    // data chunk
    wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(dataSize)).littleEndian) { Array($0) })
    wav.append(Data(count: dataSize)) // silence

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

  // MARK: - Route change observer (auto-reconnect)

  private func startRouteChangeObserver() {
    stopRouteChangeObserver()
    routeChangeObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self, self.isActive else { return }

      let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
      let session = AVAudioSession.sharedInstance()

      // Check if we lost our BT route
      let hasBT = session.currentRoute.outputs.contains { $0.portType == .bluetoothHFP }
        || session.currentRoute.inputs.contains { $0.portType == .bluetoothHFP }

      if !hasBT {
        print("BT Audio Car: lost BT route (reason: \(reason ?? 0)), attempting reconnect...")
        // Try to re-establish HFP
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          guard let self = self, self.isActive else { return }
          do {
            let inputs = session.availableInputs ?? []
            for input in inputs {
              if input.portType == .bluetoothHFP {
                try session.setPreferredInput(input)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                self.startSilenceLoop(sampleRate: session.sampleRate)
                print("BT Audio Car: reconnected to HFP")
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

  // MARK: - Interruption observer (phone calls)

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
        // Phone call ended - restore our audio session
        print("BT Audio Car: interruption ended, restoring HFP...")
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
            print("BT Audio Car: HFP restored after call")
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

  // MARK: - Media Controls

  private func handleMediaCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getNowPlaying":
      getNowPlaying(result: result)
    case "playPause":
      sendMediaCommand(.togglePlayPause, result: result)
    case "next":
      sendMediaCommand(.nextTrack, result: result)
    case "previous":
      sendMediaCommand(.previousTrack, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func getNowPlaying(result: @escaping FlutterResult) {
    let player = MPMusicPlayerController.systemMusicPlayer
    let item = player.nowPlayingItem

    if let item = item {
      result([
        "title": item.title ?? "",
        "artist": item.artist ?? "",
        "playing": player.playbackState == .playing
      ])
    } else {
      result([
        "title": NSNull(),
        "artist": NSNull(),
        "playing": false
      ])
    }
  }

  private func sendMediaCommand(_ command: MediaCommand, result: @escaping FlutterResult) {
    switch command {
    case .togglePlayPause:
      let player = MPMusicPlayerController.systemMusicPlayer
      if player.playbackState == .playing {
        player.pause()
      } else {
        player.play()
      }
    case .nextTrack:
      MPMusicPlayerController.systemMusicPlayer.skipToNextItem()
    case .previousTrack:
      MPMusicPlayerController.systemMusicPlayer.skipToPreviousItem()
    }
    result(nil)
  }

  private enum MediaCommand {
    case togglePlayPause
    case nextTrack
    case previousTrack
  }
}
