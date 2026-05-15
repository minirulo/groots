import AVFoundation
import FlutterMacOS

class VinylRecorderChannel {

  private let recorder = VinylRecorder()

  init(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "vinyl_recorder",
                                  binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {

    case "listDevices":
      result(recorder.listInputDevices())

    case "start":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
        return
      }
      let deviceUID = args["deviceId"] as? String
      do {
        try recorder.start(deviceUID: deviceUID, path: path)
        result(nil)
      } catch {
        result(FlutterError(code: "RECORD_ERROR",
                            message: error.localizedDescription,
                            details: nil))
      }

    case "stop":
      recorder.stop()
      result(nil)

    case "getAmplitude":
      result(Double(recorder.getAmplitude()))

    case "hasPermission":
      handlePermission(result: result)

    case "probeInfo":
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
        return
      }
      do { result(try recorder.probeInfo(path: path)) }
      catch { result(FlutterError(code: "PROBE_ERROR", message: error.localizedDescription, details: nil)) }

    case "exportSegment":
      guard let args      = call.arguments as? [String: Any],
            let inputPath  = args["inputPath"]  as? String,
            let outputPath = args["outputPath"] as? String,
            let startSec   = args["startSec"]   as? Double,
            let endSec     = args["endSec"]     as? Double else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try self.recorder.exportSegment(inputPath: inputPath, outputPath: outputPath,
                                          startSec: startSec, endSec: endSec)
          DispatchQueue.main.async { result(nil) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "EXPORT_ERROR",
                                message: error.localizedDescription, details: nil))
          }
        }
      }

    case "generateWaveform":
      guard let args       = call.arguments as? [String: Any],
            let path       = args["path"] as? String,
            let numSamples = args["numSamples"] as? Int else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let waveform = try self.recorder.generateWaveform(path: path, numSamples: numSamples)
          DispatchQueue.main.async { result(waveform) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "WAVEFORM_ERROR",
                                message: error.localizedDescription, details: nil))
          }
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handlePermission(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      result(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { result(granted) }
      }
    default:
      result(false)
    }
  }
}
