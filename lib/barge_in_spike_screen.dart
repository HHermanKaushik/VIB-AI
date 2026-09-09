import 'package:flutter/material.dart';

import 'barge_in_playback_controller.dart';
import 'language_config.dart';
import 'sarvam_service.dart';

/// Manual real-device test harness for [BargeInPlaybackController]. The
/// capture/VAD/STT logic itself now lives in that shared service so other
/// screens can reuse it; this screen just drives it and shows a live log,
/// which is still useful for tuning against a real room and device.
class BargeInSpikeScreen extends StatefulWidget {
  const BargeInSpikeScreen({super.key});

  @override
  State<BargeInSpikeScreen> createState() => _BargeInSpikeScreenState();
}

class _BargeInSpikeScreenState extends State<BargeInSpikeScreen> {
  BargeInPlaybackController? _controller;
  final _logs = <String>[];
  bool _running = false;
  String? _transcript;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() => _logs.insert(0, message));
  }

  Future<void> _startSpike() async {
    if (_running) return;
    setState(() {
      _logs.clear();
      _transcript = null;
      _running = true;
    });
    final controller = BargeInPlaybackController(
      sarvam: SarvamService(),
      languageCode: defaultLanguage.languageCode,
      onLog: _log,
    );
    _controller = controller;
    try {
      await controller.open();
      final text = List.filled(
        5,
        'This is a long speech sample for the barge in test. '
        'Please listen while the microphone watches for a real person speaking. '
        'The playback should stop as soon as speech is detected in the room. ',
      ).join();
      final result = await controller.speak(text);
      if (mounted) setState(() => _transcript = result.transcript);
    } catch (error) {
      _log('START ERROR: $error');
    } finally {
      await controller.close();
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Barge-in VAD spike')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Raw energy VAD, no recorder echo cancellation/noise suppression. '
            'Use the phone speaker and built-in microphone in a normal room.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _running ? null : _startSpike,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start 30+ second TTS test'),
          ),
          const SizedBox(height: 12),
          Text('State: ${_running ? 'Running' : 'Idle'}'),
          if (_transcript != null) Text('Transcript: $_transcript'),
          const Divider(),
          const Text('Event log', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._logs.map((entry) => Text(entry, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
