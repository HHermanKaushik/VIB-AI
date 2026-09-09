import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'barge_in_playback_controller.dart';
import 'command_lexicon_service.dart';
import 'firebase_options.dart';
import 'geo_search_service.dart';
import 'sarvam_service.dart';
import 'resource_detail_screen.dart';
import 'language_config.dart';
import 'language_onboarding_screen.dart';
import 'voice_intent_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final preferences = await SharedPreferences.getInstance();
    runApp(DrishtiButionApp(
      initialLanguage: preferences.getString('preferredLanguage'),
    ));
  } catch (error) {
    runApp(FirebaseSetupErrorApp(error: error));
  }
}

class DrishtiButionApp extends StatelessWidget {
  const DrishtiButionApp({this.initialLanguage, super.key});

  final String? initialLanguage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrishtiBution resources',
      home: AppHome(initialLanguage: initialLanguage),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class AppHome extends StatefulWidget {
  const AppHome({this.initialLanguage, super.key});

  final String? initialLanguage;

  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  String? _selectedLanguage;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.initialLanguage;
  }

  void _completeOnboarding(String languageCode) {
    setState(() => _selectedLanguage = languageCode);
  }

  Future<void> _changeLanguage() async {
    final languageCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LanguageOnboardingScreen(
          onCompleted: (language) => Navigator.of(context).pop(language),
        ),
      ),
    );
    if (languageCode != null && mounted) {
      _completeOnboarding(languageCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = _selectedLanguage;
    if (language == null) {
      return LanguageOnboardingScreen(onCompleted: _completeOnboarding);
    }
    return ResourceSearchScreen(
      initialLanguage: language,
      onChangeLanguage: _changeLanguage,
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

  Future<List<Resource>> savedResourcesFor(String uid) async {
    final saved = await _firestore
        .collection('users')
        .doc(uid)
        .collection('saved')
        .orderBy('savedAt', descending: true)
        .get();
    final resources = <Resource>[];
    for (final savedDoc in saved.docs) {
      final doc =
          await _firestore.collection('organizations').doc(savedDoc.id).get();
      final data = doc.data();
      if (!doc.exists || data == null) continue;
      resources.add(Resource.fromMap(<String, dynamic>{'id': doc.id, ...data}));
    }
    return resources;
  }
}

class ResourceSearchScreen extends StatefulWidget {
  const ResourceSearchScreen({
    this.initialLanguage,
    this.onChangeLanguage,
    super.key,
  });

  final String? initialLanguage;
  final VoidCallback? onChangeLanguage;

  @override
  State<ResourceSearchScreen> createState() => _ResourceSearchScreenState();
}

class _ResourceSearchScreenState extends State<ResourceSearchScreen> {
  final _searchController = TextEditingController();
  final _repository = ResourceRepository();
  final _sarvam = SarvamService();
  final _lexicon = CommandLexiconService();
  final _geoSearch = const GeoSearchService();
  final _auth = FirebaseAuth.instance;
  final _recorder = FlutterSoundRecorder();
  final _player = AudioPlayer();
  BargeInPlaybackController? _bargeIn;
  Timer? _searchDebounce;
  Future<List<Resource>>? _results;
  Future<List<Resource>>? _savedResources;
  String? _selectedService;
  String? _selectedState;
  String _voiceLanguage = defaultLanguage.languageCode;
  bool _isRecording = false;
  bool _isSpeaking = false;
  String? _voiceStatus;

  @override
  void initState() {
    super.initState();
    _voiceLanguage = widget.initialLanguage ?? defaultLanguage.languageCode;
    _results = _runSearch();
    _savedResources = _loadSavedResources();
  }

  Future<List<Resource>> _loadSavedResources() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Future.value(const <Resource>[]);
    return _repository.savedResourcesFor(uid);
  }

  Future<void> _openResource(Resource resource) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ResourceDetailScreen(resource: resource)),
    );
    if (mounted) setState(() => _savedResources = _loadSavedResources());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _recorder.closeRecorder();
    _player.dispose();
    _searchController.dispose();
    unawaited(_bargeIn?.dispose());
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
      final matchedIntent =
          await _lexicon.matchIntent(transcription.transcript, _voiceLanguage);
      if (matchedIntent == 'change_language') {
        widget.onChangeLanguage?.call();
        return;
      }
      _searchController.text = transcription.transcript;
      await _runGeoVoiceSearch(transcription.transcript);
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
      await _speakMessage('Voice search failed. Please try again.');
    }
  }

  Future<void> _runGeoVoiceSearch(String transcript) async {
    if (mounted) setState(() => _voiceStatus = 'Finding matching resources.');
    final intent = const VoiceIntentExtractor().extract(transcript);
    final searchResult = await _geoSearch.search(intent);
    if (searchResult.hasError) {
      await _speakMessage(searchResult.error!);
      return;
    }
    if (mounted) setState(() => _results = Future.value(searchResult.resources));
    if (searchResult.resources.isEmpty) {
      await _speakMessage(
        "I couldn't find anything matching that — want to try a different "
        'location or service?',
      );
      return;
    }
    await _speakResourcesWithBargeIn(searchResult.resources);
  }

  Future<void> _speakResourcesWithBargeIn(List<Resource> resources) async {
    if (mounted) setState(() => _isSpeaking = true);
    final bargeIn = BargeInPlaybackController(
      sarvam: _sarvam,
      languageCode: _voiceLanguage,
    );
    _bargeIn = bargeIn;
    try {
      await bargeIn.open();
      var index = 0;
      while (index < resources.length) {
        final resource = resources[index];
        final message = _announcement(resource, index, resources.length);
        if (mounted) setState(() => _voiceStatus = message);
        final result = await bargeIn.speak(message);
        if (!result.interrupted) {
          index += 1;
          continue;
        }
        final transcript = result.transcript;
        if (transcript == null || transcript.trim().isEmpty) {
          index += 1;
          continue;
        }
        final command = await _lexicon.matchIntent(transcript, _voiceLanguage);
        switch (command) {
          case 'stop':
            return;
          case 'repeat':
            continue;
          case 'more_detail':
            await bargeIn.close();
            await _openResource(resource);
            if (!mounted) return;
            await bargeIn.open();
            continue;
          case 'next':
            index += 1;
            continue;
          default:
            index += 1;
            continue;
        }
      }
      if (mounted) {
        setState(() => _voiceStatus = 'That was all $index results.');
      }
    } finally {
      await bargeIn.close();
      await bargeIn.dispose();
      if (identical(_bargeIn, bargeIn)) _bargeIn = null;
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  String _announcement(Resource resource, int index, int total) {
    final summary = resource.matchExplanation.isNotEmpty
        ? resource.matchExplanation
        : (resource.servicesText.isEmpty
            ? 'Services not available in the database.'
            : resource.servicesText.split('.').first);
    final location = resource.locationLabel.isEmpty
        ? 'Location not available'
        : resource.locationLabel;
    return 'Result ${index + 1} of $total. ${resource.name}. $location. $summary.';
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
            FutureBuilder<List<Resource>>(
              future: _savedResources,
              builder: (context, snapshot) {
                final saved = snapshot.data ?? const <Resource>[];
                if (saved.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          'Saved resources',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 116,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: saved.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) =>
                              _savedResourceTile(saved[index]),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
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
                items: validatedLanguages
                    .map(
                      (language) => DropdownMenuItem(
                        value: language.languageCode,
                        child: Text(language.displayNameNative),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _isRecording
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _voiceLanguage = value);
                        }
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
          onTap: () => _openResource(resource),
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

  Widget _savedResourceTile(Resource resource) {
    final location = resource.locationLabel.isEmpty
        ? 'Location not available'
        : resource.locationLabel;
    return Semantics(
      button: true,
      hint: 'Double tap to open the full resource profile',
      container: true,
      label: 'Saved: ${resource.name}. $location.',
      child: SizedBox(
        width: 200,
        child: Card(
          child: InkWell(
            onTap: () => _openResource(resource),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    resource.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(location, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
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
