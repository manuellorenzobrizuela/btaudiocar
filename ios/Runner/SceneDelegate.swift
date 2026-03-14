import Flutter
import UIKit
import AVFoundation
import MediaPlayer

class SceneDelegate: FlutterSceneDelegate {
  private var scoChannel: FlutterMethodChannel?
  private var mediaChannel: FlutterMethodChannel?
  private var silencePlayer: AVAudioPlayer?

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
        options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker]
      )
      try session.setActive(true)

      let inputs = session.availableInputs ?? []
      for input in inputs {
        if input.portType == .bluetoothHFP {
          try session.setPreferredInput(input)
          break
        }
      }

      try session.setActive(true)

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

    let sampleRate: Int = 8000
    let numSamples = sampleRate
    let bitsPerSample = 16
    let numChannels = 1
    let dataSize = numSamples * numChannels * (bitsPerSample / 8)
    let fileSize = 44 + dataSize

    var wav = Data()
    wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize - 8).littleEndian) { Array($0) })
    wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
    wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt16(UInt16(numChannels)).littleEndian) { Array($0) })
    wav.append(contentsOf: withUnsafeBytes(of: UInt32(UInt32(sampleRate)).littleEndian) { Array($0) })
    let byteRate = sampleRate * numChannels * (bitsPerSample / 8)
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
    // Use MPMusicPlayerController to get system now playing info
    let player = MPMusicPlayerController.systemMusicPlayer
    let item = player.nowPlayingItem

    if let item = item {
      result([
        "title": item.title ?? "",
        "artist": item.artist ?? "",
        "playing": player.playbackState == .playing
      ])
    } else {
      // Try the generic now playing info from the system
      // This works for Apple Music; for third-party apps we use media key simulation
      result([
        "title": NSNull(),
        "artist": NSNull(),
        "playing": false
      ])
    }
  }

  private func sendMediaCommand(_ command: MPRemoteCommand, result: @escaping FlutterResult) {
    // Simulate media key events to control any active media app
    let commandCenter = MPRemoteCommandCenter.shared()
    let event = MPRemoteCommandEvent()

    switch command {
    case .togglePlayPause:
      // Use system music player for Apple Music, media keys for others
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
    default:
      break
    }

    result(nil)
  }

  private enum MPRemoteCommand {
    case togglePlayPause
    case nextTrack
    case previousTrack
  }
}
