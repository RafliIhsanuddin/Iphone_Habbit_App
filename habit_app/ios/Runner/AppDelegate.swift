import Flutter
import UIKit

import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {

  static var activePlayers: [String: AVAudioPlayer] = [:]
  static var alarmChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    let channel = FlutterMethodChannel(
      name: "habit_app/alarm",
      binaryMessenger: controller.binaryMessenger
    )
    AppDelegate.alarmChannel = channel

    channel.setMethodCallHandler { (call, result) in
      let args = call.arguments as? [String: Any]
      let habitId = args?["habitId"] as? String ?? ""

      switch call.method {
      case "playAlarm":
        AppDelegate.startAlarmSound(habitId: habitId)
        result(nil)

      case "stopAlarm":
        AppDelegate.stopAlarmSound(habitId: habitId)
        result(nil)

      case "scheduleNativeAlarmSound":
        result(nil)

      case "cancelNativeAlarmSound":
        result(nil)

      case "showSnoozeToast":
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  static func startAlarmSound(habitId: String) {
    if activePlayers[habitId] != nil {
      return
    }

    for (otherId, player) in activePlayers where otherId != habitId {
      player.stop()
    }
    activePlayers = activePlayers.filter { $0.key == habitId }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.duckOthers])
      try session.setActive(true)

      guard let url = Bundle.main.url(forResource: "alarm_sound", withExtension: "caf")
        ?? Bundle.main.url(forResource: "alarm_sound", withExtension: "wav")
        ?? Bundle.main.url(forResource: "alarm_sound", withExtension: "mp3") else {
        return
      }

      let player = try AVAudioPlayer(contentsOf: url)
      player.numberOfLoops = -1
      player.prepareToPlay()
      player.play()
      activePlayers[habitId] = player

      alarmChannel?.invokeMethod("nativeAlarmFired", arguments: ["habitId": habitId])
    } catch {
      print("startAlarmSound failed for \(habitId): \(error)")
    }
  }

  static func stopAlarmSound(habitId: String) {
    guard let player = activePlayers.removeValue(forKey: habitId) else { return }
    player.stop()
    if activePlayers.isEmpty {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
}