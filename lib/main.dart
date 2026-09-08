import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'sarvam_service.dart';
import 'resource_detail_screen.dart';

const serviceCategories = <String>[
  'eye_bank',
  'eye_care',
  'healthcare',
  'education',
  'vocational_training',
  'rehabilitation',
  'employment',
  'financial_support',
  'assistive_technology',
  'hostel',
  'advocacy_or_government',
  'library_or_information',
];

const indianStates = <String>[
  'Andaman and Nicobar',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu and Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Pondicherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env', isOptional: true);
    await Firebase.initializeApp();
    runApp(const DrishtiButionApp());
  } catch (error) {
    runApp(FirebaseSetupErrorApp(error: error));
  }
}

class DrishtiButionApp extends StatelessWidget {
  const DrishtiButionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrishtiBution resources',
      home: const ResourceSearchScreen(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class FirebaseSetupErrorApp extends StatelessWidget {
  const FirebaseSetupErrorApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrishtiBution setup',
      home: Scaffold(
        appBar: AppBar(title: const Text('DrishtiBution')),
        body: Center(
          child: Semantics(
            liveRegion: true,
            child: Text(
              'Firebase is not configured for this app yet. Run flutterfire configure.\n\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class Resource {
  const Resource({
    required this.id,
    required this.name,
    required this.city,
    required this.state,
    required this.address,
    required this.phones,
    required this.servicesText,
    required this.matchExplanation,
    required this.emails,
    required this.website,
    required this.eligibilityText,
    required this.lastVerifiedAt,
  });

  factory Resource.fromMap(Map<String, dynamic> map) {
    final organization = _map(map['organization']);
    final location = _map(map['location']);
    final contact = _map(map['contact']);
    final services = _map(map['services']);
    final match = _map(map['match']);
    final eligibility = _map(map['eligibility']);
    final verification = _map(map['verification']);
    return Resource(
      id: map['id'] as String? ?? '',
      name: organization['name'] as String? ?? 'Unnamed organization',
      city: location['city'] as String? ?? '',
      state: location['state'] as String? ?? '',
      address: location['address'] as String? ?? '',
      phones: _strings(contact['phones']),
      servicesText: services['rawDescription'] as String? ?? '',
      matchExplanation: match['explanation'] as String? ?? '',
      emails: _strings(contact['emails']),
      website: contact['websiteUrl'] as String? ?? '',
      eligibilityText: eligibility['rawText'] as String? ?? '',
      lastVerifiedAt: _dateText(verification['lastVerifiedAt']),
    );
  }

  final String id;
  final String name;
  final String city;
  final String state;
  final String address;
  final List<String> phones;
  final String servicesText;
  final String matchExplanation;
  final List<String> emails;
  final String website;
  final String eligibilityText;
  final String lastVerifiedAt;

  String get locationLabel =>
      [city, state].where((value) => value.isNotEmpty).join(', ');

  String get searchText =>
      [name, servicesText, city, state].join(' ').toLowerCase();

  static Map<String, dynamic> _map(Object? value) {
    return value is Map<String, dynamic> ? value : <String, dynamic>{};
  }

  static List<String> _strings(Object? value) {
    return value is List ? value.whereType<String>().toList() : <String>[];
  }

  static String _dateText(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toLocal().toString().split(' ').first;
    }
    return value?.toString() ?? '';
  }
}

class ResourceRepository {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<List<Resource>> search({
    String? serviceCategory,
    String? state,
    required String search,
  }) async {
    Query<Map<String, dynamic>> query = _firestore
        .collection('organizations')
        .where('review.status', isEqualTo: 'clean');
    if (serviceCategory != null) {
      query = query.where(
        'services.codes',
        arrayContains: serviceCategory,
      );
    }
    if (state != null) {
      query = query.where('location.state', isEqualTo: state);
    }
    final snapshot = await query.get();
    final normalizedSearch = search.toLowerCase();
    return snapshot.docs
        .map((doc) => Resource.fromMap(<String, dynamic>{
              'id': doc.id,
              ...doc.data(),
            }))
        .where((resource) => resource.searchText.contains(normalizedSearch))
        .toList();
  }
}

class ResourceSearchScreen extends StatefulWidget {
  const ResourceSearchScreen({super.key});

  @override
  State<ResourceSearchScreen> createState() => _ResourceSearchScreenState();
}

class _ResourceSearchScreenState extends State<ResourceSearchScreen> {
  final _searchController = TextEditingController();
  final _repository = ResourceRepository();
  final _sarvam = SarvamService();
  final _recorder = FlutterSoundRecorder();
  final _player = AudioPlayer();
  Timer? _searchDebounce;
  Future<List<Resource>>? _results;
  String? _selectedService;
  String? _selectedState;
  String _voiceLanguage = 'en-IN';
  bool _isRecording = false;
  bool _isSpeaking = false;
  String? _voiceStatus;

  @override
  void initState() {
    super.initState();
    _results = _runSearch();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _recorder.closeRecorder();
    _player.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Resource>> _runSearch() {
    return _repository.search(
      serviceCategory: _selectedService,
      state: _selectedState,
      search: _searchController.text.trim(),
    );
  }

  void _scheduleSearch(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _results = _runSearch());
    });
  }

  void _changeFilter({String? service, String? state}) {
    setState(() {
      _selectedService = service;
      _selectedState = state;
      _results = _runSearch();
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _changeFilter();
  }

  Future<void> _toggleVoiceSearch() async {
    if (_isRecording) {
      await _finishVoiceSearch();
      return;
    }
    try {
      await _recorder.openRecorder();
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/drishtibution-search.wav';
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.pcm16WAV,
        sampleRate: 16000,
        numChannels: 1,
      );
      if (mounted) {
        setState(() {
          _isRecording = true;
          _voiceStatus =
              'Listening. Double tap the microphone again when finished.';
        });
      }
    } catch (_) {
      await _speakMessage(
          'I could not start the microphone. Please try again.');
    }
  }

  Future<void> _finishVoiceSearch() async {
    try {
      final path = await _recorder.stopRecorder();
      if (mounted) setState(() => _isRecording = false);
      if (path == null || path.isEmpty) {
        await _speakMessage('I could not hear anything. Please try again.');
        return;
      }
      if (mounted) setState(() => _voiceStatus = 'Transcribing your search.');
      final transcription = await _sarvam.speechToText(
        audioFile: File(path),
        languageCode: _voiceLanguage,
      );
      if (transcription == null || transcription.transcript.trim().isEmpty) {
        await _speakMessage('I could not understand that. Please try again.');
        return;
      }
      _searchController.text = transcription.transcript;
      if (mounted) {
        setState(() {
          _voiceStatus = 'Searching for ${transcription.transcript}.';
          _results = _runSearch();
        });
      }
      final resources = await _results;
      if (resources != null) await _speakResults(resources);
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
      await _speakMessage('Voice search failed. Please try again.');
    }
  }

  Future<void> _speakMessage(String message) async {
    if (!mounted) return;
    setState(() => _voiceStatus = message);
    final audio = await _sarvam.textToSpeech(
      text: message,
      languageCode: _voiceLanguage,
    );
    if (audio != null) await _player.play(BytesSource(audio));
  }

  Future<void> _speakResults(List<Resource> resources) async {
    if (resources.isEmpty) {
      await _speakMessage('No matching resources found.');
      return;
    }
    if (mounted) setState(() => _isSpeaking = true);
    try {
      for (final resource in resources) {
        final summary = resource.servicesText.isEmpty
            ? 'Services not available in the database.'
            : resource.servicesText.split('.').first;
        final message =
            '${resource.name}. ${resource.locationLabel.isEmpty ? 'Location not available' : resource.locationLabel}. $summary.';
        final audio = await _sarvam.textToSpeech(
          text: message,
          languageCode: _voiceLanguage,
        );
        if (audio == null) continue;
        await _player.play(BytesSource(audio));
        await _player.onPlayerComplete.first;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: const Text('Find support resources'),
        ),
      ),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Semantics(
              textField: true,
              label: 'Search organization names and services',
              child: TextField(
                controller: _searchController,
                onChanged: _scheduleSearch,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  labelText: 'Search',
                  hintText: 'Organization name or service',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Voice input language',
              child: DropdownButtonFormField<String>(
                initialValue: _voiceLanguage,
                decoration: const InputDecoration(
                  labelText: 'Voice input language',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'en-IN', child: Text('English')),
                  DropdownMenuItem(value: 'hi-IN', child: Text('Hindi')),
                ],
                onChanged: _isRecording
                    ? null
                    : (value) {
                        if (value != null)
                          setState(() => _voiceLanguage = value);
                      },
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: _isRecording ? 'Stop speaking' : 'Start voice search',
              hint: _isRecording
                  ? 'Double tap to stop speaking'
                  : 'Double tap to speak',
              enabled: !_isSpeaking,
              child: SizedBox(
                width: double.infinity,
                height: 88,
                child: ElevatedButton.icon(
                  onPressed: _isSpeaking ? null : _toggleVoiceSearch,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? 'Stop listening' : 'Speak search'),
                ),
              ),
            ),
            if (_voiceStatus != null)
              Semantics(
                liveRegion: true,
                label: _voiceStatus!,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_voiceStatus!),
                ),
              ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Filter by service category',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedService,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Service category',
                  border: OutlineInputBorder(),
                ),
                items: serviceCategories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    _changeFilter(service: value, state: _selectedState),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              label: 'Filter by state',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedState,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'State',
                  border: OutlineInputBorder(),
                ),
                items: indianStates
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    _changeFilter(service: _selectedService, state: value),
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              button: true,
              label: 'Clear search and filters',
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear filters'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<Resource>>(
              future: _results,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Semantics(
                    liveRegion: true,
                    label: 'Loading resources',
                    child: const Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Semantics(
                    liveRegion: true,
                    child: Text('Could not load resources: ${snapshot.error}'),
                  );
                }
                final resources = snapshot.data ?? <Resource>[];
                if (resources.isEmpty) {
                  return Semantics(
                    liveRegion: true,
                    child: const Text('No matching resources found.'),
                  );
                }
                return Semantics(
                  liveRegion: true,
                  label: '${resources.length} resources found',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: resources.map(_resourceTile).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _resourceTile(Resource resource) {
    final location = resource.locationLabel.isEmpty
        ? 'Location not available'
        : resource.locationLabel;
    final phone = resource.phones.isEmpty ? null : resource.phones.first;
    return Semantics(
      button: true,
      hint: 'Double tap to open the full resource profile',
      container: true,
      label: '${resource.name}. $location.',
      child: Card(
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ResourceDetailScreen(resource: resource),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  resource.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(location),
                if (resource.address.isNotEmpty) Text(resource.address),
                if (resource.matchExplanation.isNotEmpty)
                  Semantics(
                    container: true,
                    label: resource.matchExplanation,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(resource.matchExplanation),
                    ),
                  ),
                const SizedBox(height: 8),
                Semantics(
                  button: true,
                  enabled: phone != null,
                  label: phone == null
                      ? 'Phone number unavailable'
                      : 'Call ${resource.name}',
                  child: TextButton.icon(
                    onPressed: phone == null ? null : () => _call(phone),
                    icon: const Icon(Icons.phone),
                    label: Text(phone == null ? 'Phone unavailable' : 'Call'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the phone dialer.')),
      );
    }
  }
}
