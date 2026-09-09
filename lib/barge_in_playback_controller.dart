import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

import 'sarvam_service.dart';

/// Result of speaking one message through [BargeInPlaybackController.speak].
class BargeInSpeechResult {
  const BargeInSpeechResult({required this.interrupted, this.transcript});

  static const notInterrupted = BargeInSpeechResult(interrupted: false);

  /// True if the listener started speaking before playback finished.
  final bool interrupted;

  /// The transcribed interruption. Null if not [interrupted], or if the
  /// interruption audio could not be transcribed.
  final String? transcript;
}

/// Reusable playback + barge-in (voice activity detection) service.
///
/// This is the validated logic from the standalone spike at
/// lib/barge_in_spike_screen.dart, productionized: raw-energy VAD against a
/// calibrated noise floor, with no recorder echo cancellation or noise
/// suppression (both were found to suppress the barge-in signal itself
/// during spike testing). Any screen that plays a sequence of TTS messages
/// and wants the listener to be able to interrupt with a spoken command
/// should use this instead of re-implementing capture/VAD.
class BargeInPlaybackController {
  BargeInPlaybackController({
    required SarvamService sarvam,
    required String languageCode,
    void Function(String message)? onLog,
  })  : _sarvam = sarvam,
        _languageCode = languageCode,
        _onLog = onLog;

  static const _sampleRate = 16000;
  static const _silenceDuration = Duration(milliseconds: 900);
  static const _calibrationDuration = Duration(milliseconds: 800);
  static const _minThreshold = 800.0;

  final SarvamService _sarvam;
  final String _languageCode;
  final void Function(String message)? _onLog;

  final _recorder = FlutterSoundRecorder();
  final _player = AudioPlayer();
  final _pcm = <Uint8List>[];

  StreamController<Uint8List>? _streamController;
  StreamSubscription<Uint8List>? _streamSubscription;
  Timer? _silenceTimer;
  Completer<void>? _silenceCompleter;

  double _noiseFloor = 0;
  double _threshold = _minThreshold;
  bool _sessionOpen = false;
  bool _calibrating = false;
  bool _armedForBargeIn = false;
  bool _speechDetected = false;
  int _speechPcmStartIndex = 0;

  void _log(String message) {
    debugPrint('[barge-in] $message');
    _onLog?.call(message);
  }

  /// Opens the microphone and calibrates the noise floor. [speak] calls this
  /// automatically if the session is not already open; call it explicitly
  /// to pay the calibration cost once before the first message.
  Future<void> open() async {
    if (_sessionOpen) return;
    await _recorder.openRecorder();
    _pcm.clear();
    _noiseFloor = 0;
    _threshold = _minThreshold;
    _streamController = StreamController<Uint8List>();
    _streamSubscription = _streamController!.stream.listen(_onPcm);
    await _recorder.startRecorder(
      codec: Codec.pcm16,
      toStream: _streamController!.sink,
      sampleRate: _sampleRate,
      numChannels: 1,
      bufferSize: 2048,
      enableEchoCancellation: false,
      enableNoiseSuppression: false,
    );
    _sessionOpen = true;
    _calibrating = true;
    _log('Calibrating room noise for ${_calibrationDuration.inMilliseconds} ms.');
    await Future<void>.delayed(_calibrationDuration);
    _calibrating = false;
    _threshold = math.max(_minThreshold, _noiseFloor * 3.0);
    _log('Noise floor=${_noiseFloor.toStringAsFixed(1)}, '
        'threshold=${_threshold.toStringAsFixed(1)}.');
  }

  /// Speaks [text] via TTS. If the listener starts talking while it plays,
  /// playback stops immediately, their speech is captured until a silence
  /// gap, and the result carries the transcribed interruption.
  Future<BargeInSpeechResult> speak(String text) async {
    if (!_sessionOpen) await open();
    final audio = await _sarvam.textToSpeech(text: text, languageCode: _languageCode);
    if (audio == null) {
      _log('TTS ERROR: no audio returned.');
      return BargeInSpeechResult.notInterrupted;
    }

    _speechDetected = false;
    _speechPcmStartIndex = _pcm.length;
    _armedForBargeIn = true;
    _log('Playback started.');

    final playbackComplete = Completer<void>();
    final subscription = _player.onPlayerComplete.listen((_) {
      if (!playbackComplete.isCompleted) playbackComplete.complete();
    });
    await _player.play(BytesSource(audio));
    await playbackComplete.future;
    await subscription.cancel();
    _armedForBargeIn = false;

    if (!_speechDetected) {
      _log('Playback completed without interruption.');
      return BargeInSpeechResult.notInterrupted;
    }

    _log('Speech detected; waiting for the listener to finish.');
    await _waitForSilence();
    final speechPcm = _pcm.skip(_speechPcmStartIndex).toList();
    if (speechPcm.isEmpty) return const BargeInSpeechResult(interrupted: true);

    final file = await _writeWav(speechPcm);
    final result = await _sarvam.speechToText(audioFile: file, languageCode: _languageCode);
    _log(result == null
        ? 'Interruption STT returned nothing.'
        : 'Interruption transcript: ${result.transcript}');
    return BargeInSpeechResult(interrupted: true, transcript: result?.transcript);
  }

  Future<void> _waitForSilence() {
    _silenceCompleter = Completer<void>();
    return _silenceCompleter!.future;
  }

  void _onPcm(Uint8List bytes) {
    if (!_sessionOpen) return;
    _pcm.add(bytes);
    final rms = _rms(bytes);

    if (_calibrating) {
      _noiseFloor = (_noiseFloor * 0.9) + (rms * 0.1);
      return;
    }

    if (!_speechDetected) {
      if (_armedForBargeIn && rms >= _threshold) {
        _speechDetected = true;
        _log('Speech detected (RMS=${rms.toStringAsFixed(1)}); stopping playback.');
        unawaited(_player.stop());
      }
      return;
    }

    if (rms >= _threshold) {
      _silenceTimer?.cancel();
    } else if (_silenceTimer == null || !_silenceTimer!.isActive) {
      _silenceTimer = Timer(_silenceDuration, () {
        _silenceCompleter?.complete();
      });
    }
  }

  double _rms(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    var sum = 0.0;
    var count = 0;
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      sum += sample * sample;
      count++;
    }
    return count == 0 ? 0 : math.sqrt(sum / count);
  }

  Future<File> _writeWav(List<Uint8List> chunks) async {
    final pcmBuilder = BytesBuilder();
    for (final chunk in chunks) {
      pcmBuilder.add(chunk);
    }
    final data = pcmBuilder.takeBytes();
    final output = BytesBuilder();
    final header = ByteData(44);
    header.setUint32(0, 0x52494646, Endian.big);
    header.setUint32(4, 36 + data.length, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big);
    header.setUint32(12, 0x666d7420, Endian.big);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(36, 0x64617461, Endian.big);
    header.setUint32(40, data.length, Endian.little);
    output.add(header.buffer.asUint8List());
    output.add(data);

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/barge-in-capture.wav');
    await file.writeAsBytes(output.takeBytes(), flush: true);
    return file;
  }

  /// Stops recording and playback but keeps the controller reusable via
  /// [open]/[speak] again.
  Future<void> close() async {
    if (!_sessionOpen) return;
    _silenceTimer?.cancel();
    _silenceTimer = null;
    try {
      await _recorder.stopRecorder();
    } catch (_) {}
    await _streamSubscription?.cancel();
    await _streamController?.close();
    _streamSubscription = null;
    _streamController = null;
    _sessionOpen = false;
  }

  /// Releases the recorder and player. The controller cannot be reused after
  /// this; create a new one instead.
  Future<void> dispose() async {
    await close();
    await _recorder.closeRecorder();
    await _player.dispose();
  }
}
