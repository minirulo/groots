import AVFoundation
import CoreAudio

/// Low-level AVAudioEngine recorder that bypasses AVCaptureSession entirely.
/// AVCaptureSession applies microphone-oriented AGC that clips line-in signals;
/// AVAudioEngine feeds raw, unprocessed PCM straight from the HAL.
class VinylRecorder {

  private var engine: AVAudioEngine?
  private var audioFile: AVAudioFile?
  // Two-engine monitoring: inputEngine taps the source, outputEngine plays it back.
  // A single AVAudioEngine cannot bridge I/O across different HAL devices
  // (kAUGraphErr_OutputNodeErr -10875), so we decouple them entirely.
  private var monitorInputEngine: AVAudioEngine?
  private var monitorOutputEngine: AVAudioEngine?
  private var monitorPlayerNode: AVAudioPlayerNode?
  private var _amplitude: Float = -160.0
  private let lock = NSLock()

  var isRunning: Bool { engine?.isRunning ?? false }

  // MARK: – Device enumeration (Core Audio, not AVCaptureDevice)

  func listInputDevices() -> [[String: String]] {
    guard let ids = allAudioDeviceIDs() else { return [] }
    return ids.compactMap { id -> [String: String]? in
      guard inputChannelCount(for: id) > 0,
            let uid  = stringProp(id, kAudioDevicePropertyDeviceUID),
            let name = stringProp(id, kAudioDevicePropertyDeviceNameCFString)
      else { return nil }
      return ["id": uid, "label": name]
    }
  }

  func listOutputDevices() -> [[String: String]] {
    guard let ids = allAudioDeviceIDs() else { return [] }
    return ids.compactMap { id -> [String: String]? in
      guard outputChannelCount(for: id) > 0,
            let uid  = stringProp(id, kAudioDevicePropertyDeviceUID),
            let name = stringProp(id, kAudioDevicePropertyDeviceNameCFString)
      else { return nil }
      return ["id": uid, "label": name]
    }
  }

  // MARK: – Input monitoring

  func startMonitoring(inputDeviceUID: String?, outputDeviceUID: String?) throws {
    stopMonitoring()

    // ── Input engine ──────────────────────────────────────────────────────
    let inEngine  = AVAudioEngine()
    let inputNode = inEngine.inputNode

    if let uid = inputDeviceUID,
       let audioUnit = inputNode.audioUnit,
       var devID = audioDeviceID(forUID: uid) {
      AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                           kAudioUnitScope_Global, 0, &devID,
                           UInt32(MemoryLayout<AudioDeviceID>.size))
    }

    // inputNode.outputFormat(forBus:) is unreliable before start() — even
    // after prepare() the AUHAL may report 0 Hz / 0 ch.  Query CoreAudio
    // directly to get the device's actual nominal sample rate and channel count.
    let devID      = inputDeviceUID.flatMap { audioDeviceID(forUID: $0) }
    let sampleRate = devID.map { nominalSampleRate(for: $0) } ?? 48000.0

    // AVAudioFormat(standardFormatWithSampleRate:channels:) only accepts
    // standard channel layouts (1 or 2).  Multi-channel devices like the ES-8
    // report 8 ch, which causes it to return nil.  Vinyl is always stereo,
    // so we cap at 2 for both the tap and the player.
    let inChRaw = devID.map { inputChannelCount(for: $0) } ?? 0
    let tapCh   = AVAudioChannelCount(inChRaw >= 2 ? 2 : max(inChRaw, 1))

    // Use explicit settings rather than standardFormatWithSampleRate:channels:
    // which silently returns nil for non-standard sample rates or channel counts.
    let fmtSettings: [String: Any] = [
      AVFormatIDKey:              kAudioFormatLinearPCM,
      AVLinearPCMIsFloatKey:      true,
      AVLinearPCMIsNonInterleaved: true,
      AVLinearPCMBitDepthKey:     32,
      AVSampleRateKey:            sampleRate,
      AVNumberOfChannelsKey:      Int(tapCh),
    ]
    guard let tapFormat    = AVAudioFormat(settings: fmtSettings),
          let playerFormat = AVAudioFormat(settings: fmtSettings) else {
      throw NSError(domain: "VinylRecorder", code: -1,
                    userInfo: [NSLocalizedDescriptionKey:
                      "Cannot create audio format sr=\(sampleRate) ch=\(tapCh) inChRaw=\(inChRaw)"])
    }

    // ── Output engine ─────────────────────────────────────────────────────
    let outEngine  = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    outEngine.attach(playerNode)
    outEngine.connect(playerNode, to: outEngine.mainMixerNode, format: playerFormat)

    if let uid = outputDeviceUID,
       let audioUnit = outEngine.outputNode.audioUnit,
       var devID = audioDeviceID(forUID: uid) {
      AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice,
                           kAudioUnitScope_Global, 0, &devID,
                           UInt32(MemoryLayout<AudioDeviceID>.size))
    }
    try outEngine.start()

    // ── Tap: amplitude + forward to output ───────────────────────────────
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self, weak playerNode] buf, _ in
      guard let self else { return }

      if let data = buf.floatChannelData {
        var peak: Float = 0
        for ch in 0..<Int(buf.format.channelCount) {
          for i in 0..<Int(buf.frameLength) {
            let v = abs(data[ch][i]); if v > peak { peak = v }
          }
        }
        self.lock.lock()
        self._amplitude = peak > 0 ? max(-160, 20 * log10(peak)) : -160
        self.lock.unlock()
      }

      guard let playerNode,
            let mixed = AVAudioPCMBuffer(pcmFormat: playerFormat,
                                         frameCapacity: buf.frameLength),
            let srcData = buf.floatChannelData,
            let dstData = mixed.floatChannelData else { return }

      mixed.frameLength = buf.frameLength
      let frames = Int(buf.frameLength)
      for ch in 0..<Int(tapCh) {
        memcpy(dstData[ch], srcData[ch], frames * MemoryLayout<Float>.size)
      }

      playerNode.scheduleBuffer(mixed)
      if !playerNode.isPlaying { playerNode.play() }
    }

    try inEngine.start()

    monitorInputEngine  = inEngine
    monitorOutputEngine = outEngine
    monitorPlayerNode   = playerNode
  }

  func stopMonitoring() {
    monitorInputEngine?.inputNode.removeTap(onBus: 0)
    monitorInputEngine?.stop()
    monitorInputEngine = nil
    monitorPlayerNode?.stop()
    monitorPlayerNode = nil
    monitorOutputEngine?.stop()
    monitorOutputEngine = nil
    lock.lock(); _amplitude = -160.0; lock.unlock()
  }

  // MARK: – Recording

  func start(deviceUID: String?, path: String) throws {
    stopMonitoring()
    stop()

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode

    // Point the HAL audio unit at the requested device before querying its format
    if let uid = deviceUID,
       let audioUnit = inputNode.audioUnit,
       var devID = audioDeviceID(forUID: uid) {
      AudioUnitSetProperty(
        audioUnit,
        kAudioOutputUnitProperty_CurrentDevice,
        kAudioUnitScope_Global,
        0,
        &devID,
        UInt32(MemoryLayout<AudioDeviceID>.size)
      )
    }

    // Write 32-bit int WAV at the device's native rate — no SRC, no processing.
    // 32-bit preserves full precision from higher-end interfaces; cheap 16-bit
    // hardware pads the lower bytes with zeros (slightly larger temp file, no downside).
    // Use the hardware's reported channel count so AVAudioEngine never has to pad
    // silent channels; mono→stereo upmix happens at export time instead.
    let hwFormat   = inputNode.outputFormat(forBus: 0)
    let nativeRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48000.0
    let chCount    = max(hwFormat.channelCount, 1)

    let fileSettings: [String: Any] = [
      AVFormatIDKey:                kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey:       32,
      AVLinearPCMIsFloatKey:        false,
      AVLinearPCMIsBigEndianKey:    false,
      AVLinearPCMIsNonInterleaved:  false,
      AVSampleRateKey:              nativeRate,
      AVNumberOfChannelsKey:        Int(chCount),
    ]

    let file = try AVAudioFile(
      forWriting: URL(fileURLWithPath: path),
      settings: fileSettings
    )

    // Install tap in the file's processingFormat so we can write directly
    // (AVAudioEngine converts from hardware format to tap format for us)
    let tapFormat = file.processingFormat
    self.audioFile = file

    inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buf, _ in
      guard let self else { return }

      // Peak amplitude (used for the VU meter)
      if let data = buf.floatChannelData {
        var peak: Float = 0
        let frames = Int(buf.frameLength)
        for ch in 0..<Int(buf.format.channelCount) {
          for i in 0..<frames {
            let v = abs(data[ch][i])
            if v > peak { peak = v }
          }
        }
        self.lock.lock()
        self._amplitude = peak > 0 ? max(-160, 20 * log10(peak)) : -160
        self.lock.unlock()
      }

      // Write — buffer is already in processingFormat so no conversion needed
      try? self.audioFile?.write(from: buf)
    }

    try engine.start()
    self.engine = engine
  }

  func stop() {
    engine?.inputNode.removeTap(onBus: 0)
    engine?.stop()
    engine    = nil
    audioFile = nil
    lock.lock(); _amplitude = -160.0; lock.unlock()
  }

  func getAmplitude() -> Float {
    lock.lock(); defer { lock.unlock() }
    return _amplitude
  }

  // MARK: – Core Audio helpers

  private func allAudioDeviceIDs() -> [AudioDeviceID]? {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope:    kAudioObjectPropertyScopeGlobal,
      mElement:  kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
    ) == noErr else { return nil }

    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
    ) == noErr else { return nil }
    return ids
  }

  private func channelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope:    scope,
      mElement:  kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size) == noErr,
          size > 0 else { return 0 }

    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                               alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, raw) == noErr else { return 0 }

    let abl = raw.assumingMemoryBound(to: AudioBufferList.self)
    return UnsafeMutableAudioBufferListPointer(abl).reduce(0) { $0 + Int($1.mNumberChannels) }
  }

  private func inputChannelCount(for deviceID: AudioDeviceID) -> Int {
    channelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)
  }

  private func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
    channelCount(for: deviceID, scope: kAudioDevicePropertyScopeOutput)
  }

  private func nominalSampleRate(for deviceID: AudioDeviceID) -> Double {
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyNominalSampleRate,
      mScope:    kAudioObjectPropertyScopeGlobal,
      mElement:  kAudioObjectPropertyElementMain
    )
    var rate: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &rate) == noErr,
          rate > 0 else { return 48000.0 }
    return rate
  }

  private func stringProp(_ deviceID: AudioDeviceID,
                          _ selector: AudioObjectPropertySelector) -> String? {
    var addr = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope:    kAudioObjectPropertyScopeGlobal,
      mElement:  kAudioObjectPropertyElementMain
    )
    var size: UInt32 = UInt32(MemoryLayout<CFString?>.size)
    var value: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
  }

  func audioDeviceID(forUID uid: String) -> AudioDeviceID? {
    guard let ids = allAudioDeviceIDs() else { return nil }
    return ids.first { stringProp($0, kAudioDevicePropertyDeviceUID) == uid }
  }

  // MARK: – File operations (replaces ffprobe / ffmpeg in sandboxed builds)

  func probeInfo(path: String) throws -> [String: Any] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let sr   = file.processingFormat.sampleRate
    let dur  = sr > 0 ? Double(file.length) / sr : 0.0
    return ["duration": dur, "sampleRate": sr]
  }

  func exportSegment(inputPath: String, outputPath: String,
                     startSec: Double, endSec: Double) throws {
    let inputFile = try AVAudioFile(forReading: URL(fileURLWithPath: inputPath))
    let fmt = inputFile.processingFormat
    let sr  = fmt.sampleRate

    let startFrame = AVAudioFramePosition(startSec * sr)
    let endFrame   = AVAudioFramePosition(min(endSec * sr, Double(inputFile.length)))
    let totalFrames = AVAudioFrameCount(max(0, endFrame - startFrame))
    guard totalFrames > 0 else {
      throw NSError(domain: "VinylRecorder", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Empty segment"])
    }

    let chunkSize: AVAudioFrameCount = 65536

    // ── Pass 1: find peak amplitude ──────────────────────────────────────────
    inputFile.framePosition = startFrame
    var peak: Float = 0
    var scanRemaining = totalFrames
    while scanRemaining > 0 {
      let n = min(chunkSize, scanRemaining)
      guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { break }
      try inputFile.read(into: buf, frameCount: n)
      guard buf.frameLength > 0 else { break }
      if let data = buf.floatChannelData {
        for ch in 0..<Int(buf.format.channelCount) {
          for i in 0..<Int(buf.frameLength) {
            let v = abs(data[ch][i]); if v > peak { peak = v }
          }
        }
      }
      scanRemaining -= buf.frameLength
    }

    // Normalise to -1 dBFS. Only skip if the segment is pure silence (< -60 dBFS)
    // so that quiet phono signals (which routinely sit below -20 dBFS) are always
    // brought up rather than left untouched.
    let targetPeak: Float = 0.891  // -1 dBFS
    let gain: Float = peak > 0.001 ? targetPeak / peak : 1.0

    // ── Pass 2: write with gain applied ──────────────────────────────────────
    inputFile.framePosition = startFrame

    // Always export stereo: upmix mono captures by duplicating the channel.
    let outChannels = max(Int(fmt.channelCount), 2)
    let flacSettings: [String: Any] = [
      AVFormatIDKey:            kAudioFormatFLAC,
      AVSampleRateKey:          sr,
      AVNumberOfChannelsKey:    outChannels,
      AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
    ]
    let outputFile = try AVAudioFile(forWriting: URL(fileURLWithPath: outputPath),
                                     settings: flacSettings)
    let outFmt = outputFile.processingFormat
    let isMono = fmt.channelCount == 1 && outChannels == 2

    var remaining = totalFrames
    while remaining > 0 {
      let n = min(chunkSize, remaining)
      guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: n) else { break }
      try inputFile.read(into: buf, frameCount: n)
      guard buf.frameLength > 0 else { break }

      if isMono {
        // Duplicate mono → L and R with gain applied.
        guard let stereo = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: buf.frameLength),
              let src = buf.floatChannelData,
              let dst = stereo.floatChannelData else { break }
        stereo.frameLength = buf.frameLength
        for i in 0..<Int(buf.frameLength) {
          let s = src[0][i] * gain
          dst[0][i] = s
          dst[1][i] = s
        }
        try outputFile.write(from: stereo)
      } else {
        if gain != 1.0, let data = buf.floatChannelData {
          for ch in 0..<Int(buf.format.channelCount) {
            for i in 0..<Int(buf.frameLength) { data[ch][i] *= gain }
          }
        }
        try outputFile.write(from: buf)
      }
      remaining -= buf.frameLength
    }
  }

  func generateWaveform(path: String, numSamples: Int) throws -> [Double] {
    let file  = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let fmt   = file.processingFormat
    let total = file.length
    guard total > 0, numSamples > 0 else { return [] }

    let framesPerBucket = max(1, Int(total) / numSamples)
    var result = [Double]()
    result.reserveCapacity(numSamples)
    file.framePosition = 0

    for _ in 0..<numSamples {
      guard let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                       frameCapacity: AVAudioFrameCount(framesPerBucket))
      else { break }
      do { try file.read(into: buf, frameCount: AVAudioFrameCount(framesPerBucket)) }
      catch { break }
      guard buf.frameLength > 0 else { break }

      var peak: Float = 0
      if let data = buf.floatChannelData {
        for ch in 0..<Int(buf.format.channelCount) {
          for i in 0..<Int(buf.frameLength) {
            let v = abs(data[ch][i]); if v > peak { peak = v }
          }
        }
      }
      let db   = peak > 0 ? max(-60.0, 20.0 * log10(peak)) : -60.0
      let norm = (db + 60.0) / 60.0
      result.append(Double(min(1.0, max(0.0, norm))))
    }
    return result
  }
}
