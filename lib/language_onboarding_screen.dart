import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'language_config.dart';
import 'sarvam_service.dart';

class LanguageOnboardingScreen extends StatefulWidget {
  const LanguageOnboardingScreen({required this.onCompleted, super.key});

  final ValueChanged<String> onCompleted;

  @override
  State<LanguageOnboardingScreen> createState() =>
      _LanguageOnboardingScreenState();
}

class _LanguageOnboardingScreenState extends State<LanguageOnboardingScreen> {
  final _sarvam = SarvamService();
  final _recorder = FlutterSoundRecorder();
  final _player = AudioPlayer();
  bool _announcing = true;
  bool _recording = false;
  bool _busy = false;
  bool _showFallback = false;
  String _status = 'Please listen for the language choices.';
  int _attempts = 0;

  List<LanguageConfig> get _candidates => validatedLanguages
      .where((language) => language.sttSupported && language.ttsSupported)
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    unawaited(_announceChoices());
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.dispose();
    super.dispose();
  }

  Future<void> _announceChoices() async {
    for (final language in _candidates) {
      if (!_announcing || !mounted) return;
      setState(() => _status = language.selectionPrompt);
      final audio = await _sarvam.textToSpeech(
        text: language.selectionPrompt,
        languageCode: language.languageCode,
      );
      if (!_announcing || !mounted) return;
      if (audio != null) {
        await _player.play(BytesSource(audio));
        await _player.onPlayerComplete.first;
      }
    }
    if (mounted && _announcing) {
      setState(() {
        _announcing = false;
        _status = 'Tap the button, then say one of the language names.';
      });
    }
  }

  Future<void> _interruptAndListen() async {
    if (_busy || _recording) return;
    _announcing = false;
    await _player.stop();
    if (mounted) setState(() => _status = 'Listening. Say a language name.');
    try {
      await _recorder.openRecorder();
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/drishtibution-language.wav';
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.pcm16WAV,
        sampleRate: 16000,
        numChannels: 1,
      );
      if (mounted) setState(() => _recording = true);
    } catch (_) {
      if (mounted) setState(() => _status = 'Microphone could not start.');
      _showFallbackList();
    }
  }

  Future<void> _finishListening() async {
    if (!_recording || _busy) return;
    setState(() {
      _recording = false;
      _busy = true;
      _status = 'Checking the language you said.';
    });
    try {
      final path = await _recorder.stopRecorder();
      if (path == null || path.isEmpty) throw StateError('No recording');
      final result = await _sarvam.speechToTextAutoDetect(
        audioFile: File(path),
        candidateLanguageCodes:
            _candidates.map((language) => language.languageCode).toList(),
      );
      final code = result?.languageCode;
      final language = _candidates.firstWhere(
        (candidate) => candidate.languageCode == code,
        orElse: () => throw StateError('Language not detected'),
      );
      await _confirmLanguage(language);
    } catch (_) {
      _attempts += 1;
      if (_attempts >= 2) {
        _showFallbackList();
      } else if (mounted) {
        setState(() {
          _busy = false;
          _status = 'I could not identify that language. Please try again.';
        });
      }
    }
  }

  Future<void> _confirmLanguage(LanguageConfig language) async {
    final prompt = language.languageCode == 'hi-IN'
        ? 'आपने हिन्दी चुना है। सही है?'
        : 'You selected ${language.displayNameNative}. Is that right?';
    final audio = await _sarvam.textToSpeech(
      text: prompt,
      languageCode: language.languageCode,
    );
    if (audio != null) {
      await _player.play(BytesSource(audio));
      await _player.onPlayerComplete.first;
    }
    if (!mounted) return;
    setState(() => _status = prompt);
    final confirmed = await _recordConfirmation(language);
    if (confirmed == true) {
      await _persist(language);
    } else {
      _attempts += 1;
      if (_attempts >= 2) {
        _showFallbackList();
      } else if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Let us try another language choice.';
        });
      }
    }
  }

  Future<bool?> _recordConfirmation(LanguageConfig language) async {
    try {
      await _recorder.openRecorder();
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/drishtibution-language-confirm.wav';
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.pcm16WAV,
        sampleRate: 16000,
        numChannels: 1,
      );
      if (mounted) setState(() => _recording = true);
      await Future<void>.delayed(const Duration(seconds: 4));
      if (_recording) {
        final stoppedPath = await _recorder.stopRecorder();
        if (mounted) setState(() => _recording = false);
        if (stoppedPath == null || stoppedPath.isEmpty) return null;
        final result = await _sarvam.speechToText(
          audioFile: File(stoppedPath),
          languageCode: language.languageCode,
        );
        return _isYes(result?.transcript, language.languageCode);
      }
    } catch (_) {
      if (_recording) await _recorder.stopRecorder();
      if (mounted) setState(() => _recording = false);
    }
    return null;
  }

  bool _isYes(String? transcript, String languageCode) {
    final value = (transcript ?? '').toLowerCase();
    final yes = languageCode == 'hi-IN'
        ? ['हाँ', 'हां', 'जी']
        : ['yes', 'yeah', 'correct', 'right'];
    return yes.any(value.contains);
  }

  void _showFallbackList() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _recording = false;
      _showFallback = true;
      _status = 'Choose a language below.';
    });
  }

  Future<void> _persist(LanguageConfig language) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('preferredLanguage', language.languageCode);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'preferredLanguage': language.languageCode},
        SetOptions(merge: true),
      );
    }
    if (mounted) widget.onCompleted(language.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Language setup')),
      body: Semantics(
        liveRegion: true,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(_status, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            if (!_showFallback)
              FilledButton.icon(
                onPressed: _recording ? _finishListening : _interruptAndListen,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                label: Text(_recording ? 'Finish speaking' : 'Speak now'),
              ),
            if (_showFallback) ...[
              const Text('Tap a language to continue.'),
              const SizedBox(height: 12),
              ..._candidates.map(
                (language) => ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(language.displayNameNative),
                  onTap: () => _persist(language),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
