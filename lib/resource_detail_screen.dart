import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main.dart' show Resource;
import 'sarvam_service.dart';

class ResourceDetailScreen extends StatefulWidget {
  const ResourceDetailScreen({required this.resource, super.key});

  final Resource resource;

  @override
  State<ResourceDetailScreen> createState() => _ResourceDetailScreenState();
}

class _ResourceDetailScreenState extends State<ResourceDetailScreen>
    with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _player = AudioPlayer();
  final _sarvam = SarvamService();
  bool _isSaved = false;
  bool _isSaving = false;
  bool _isSpeaking = false;
  String? _status;
  String? _pendingFeedbackAction;

  Resource get resource => widget.resource;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadSavedState());
    unawaited(_readProfileAloud());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep this route mounted while the dialer, Maps, or share sheet is open.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => _status = 'Returned to ${resource.name}.');
      final action = _pendingFeedbackAction;
      _pendingFeedbackAction = null;
      if (action != null) unawaited(_offerFeedback(action));
    }
  }

  Future<void> _loadSavedState() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('saved')
        .doc(resource.id)
        .get();
    if (mounted) setState(() => _isSaved = snapshot.exists);
  }

  String _summary() {
    final parts = <String>[
      resource.name,
      if (resource.address.isNotEmpty) resource.address,
      if (resource.locationLabel.isNotEmpty) resource.locationLabel,
      if (resource.servicesText.isNotEmpty) resource.servicesText,
      if (resource.eligibilityText.isNotEmpty)
        'Eligibility: ${resource.eligibilityText}',
      if (resource.phones.isNotEmpty) 'Phone: ${resource.phones.join(', ')}',
      if (resource.emails.isNotEmpty) 'Email: ${resource.emails.join(', ')}',
      if (resource.website.isNotEmpty) resource.website,
    ];
    return parts.join('\n');
  }

  Future<void> _readProfileAloud() async {
    if (_isSpeaking) return;
    if (mounted) setState(() => _isSpeaking = true);
    final spoken = [
      resource.name,
      resource.locationLabel,
      resource.servicesText,
      if (resource.eligibilityText.isNotEmpty)
        'Eligibility: ${resource.eligibilityText}',
    ].where((part) => part.trim().isNotEmpty).join('. ');
    final bytes = await _sarvam.textToSpeech(
      text: spoken,
      languageCode: 'en-IN',
    );
    if (bytes != null) {
      await _player.play(BytesSource(bytes));
      await _player.onPlayerComplete.first;
    }
    if (mounted) setState(() => _isSpeaking = false);
  }

  Future<void> _call() async {
    if (resource.phones.isEmpty) return;
    _pendingFeedbackAction = 'call';
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: resource.phones.first),
    );
    if (!launched) _pendingFeedbackAction = null;
  }

  Future<void> _save() async {
    var user = _auth.currentUser;
    user ??= await Navigator.of(context).push<User>(
      MaterialPageRoute(builder: (_) => const PhoneSignInScreen()),
    );
    if (user == null || !mounted) return;
    setState(() => _isSaving = true);
    final reference = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('saved')
        .doc(resource.id);
    try {
      if (_isSaved) {
        await reference.delete();
      } else {
        await reference.set({
          'resourceId': resource.id,
          'savedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) {
        setState(() {
          _isSaved = !_isSaved;
          _isSaving = false;
          _status = _isSaved
              ? 'Resource saved.'
              : 'Resource removed from saved resources.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _status = 'Could not update saved resources.';
        });
      }
    }
  }

  Future<void> _share() async {
    _pendingFeedbackAction = 'share';
    await SharePlus.instance.share(
      ShareParams(text: _summary(), subject: resource.name),
    );
  }

  Future<void> _directions() async {
    if (resource.address.isEmpty) return;
    final query = Uri.encodeQueryComponent(
      '${resource.address}, ${resource.locationLabel}',
    );
    _pendingFeedbackAction = 'directions';
    final launched = await launchUrl(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
      mode: LaunchMode.externalApplication,
    );
    if (!launched) _pendingFeedbackAction = null;
  }

  Future<void> _offerFeedback(String action) async {
    var user = _auth.currentUser;
    user ??= await Navigator.of(context).push<User>(
      MaterialPageRoute(builder: (_) => const PhoneSignInScreen()),
    );
    if (user == null || !mounted) return;
    final response = await showDialog<FeedbackResponse>(
      context: context,
      builder: (_) => FeedbackDialog(resourceName: resource.name),
    );
    if (response == null) return;
    await _firestore
        .collection('organizations')
        .doc(resource.id)
        .collection('feedback')
        .add({
      'action': action,
      'didTheyAnswer': response.didTheyAnswer,
      'wasInformationAccurate': response.wasInformationAccurate,
      'wasServiceAvailable': response.wasServiceAvailable,
      'wasContactHelpful': response.wasContactHelpful,
      'notes': response.notes,
      'reporterUserId': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (mounted) setState(() => _status = 'Feedback submitted. Thank you.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(resource.name)),
      ),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              header: true,
              child: Text(
                resource.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            if (resource.address.isNotEmpty)
              _detailText('Address', resource.address),
            if (resource.locationLabel.isNotEmpty)
              _detailText('Location', resource.locationLabel),
            _detailText(
              'Services',
              resource.servicesText.isEmpty
                  ? 'Not available'
                  : resource.servicesText,
            ),
            _detailText(
              'Eligibility',
              resource.eligibilityText.isEmpty
                  ? 'Not specified'
                  : resource.eligibilityText,
            ),
            _detailText(
              'Phone',
              resource.phones.isEmpty
                  ? 'Not available'
                  : resource.phones.join(', '),
            ),
            _detailText(
              'Email',
              resource.emails.isEmpty
                  ? 'Not available'
                  : resource.emails.join(', '),
            ),
            _detailText(
              'Website',
              resource.website.isEmpty ? 'Not available' : resource.website,
            ),
            _detailText(
              'Last verified',
              resource.lastVerifiedAt.isEmpty
                  ? 'Not available'
                  : resource.lastVerifiedAt,
            ),
            if (resource.matchExplanation.isNotEmpty)
              Semantics(
                liveRegion: true,
                label: resource.matchExplanation,
                child: Text(resource.matchExplanation),
              ),
            if (_status != null)
              Semantics(
                liveRegion: true,
                label: _status!,
                child: Text(_status!),
              ),
            const SizedBox(height: 16),
            _action(
              label: 'Read resource profile aloud',
              hint: 'Double tap to listen',
              icon: Icons.volume_up,
              onPressed: _isSpeaking ? null : _readProfileAloud,
            ),
            _action(
              label: resource.phones.isEmpty
                  ? 'Phone number unavailable'
                  : 'Call ${resource.name}',
              icon: Icons.phone,
              onPressed: resource.phones.isEmpty ? null : _call,
            ),
            _action(
              label: _isSaved
                  ? 'Remove ${resource.name} from saved resources'
                  : 'Save ${resource.name}',
              icon: _isSaved ? Icons.bookmark : Icons.bookmark_border,
              onPressed: _isSaving ? null : _save,
            ),
            _action(
              label: 'Share ${resource.name}',
              icon: Icons.share,
              onPressed: _share,
            ),
            _action(
              label: resource.address.isEmpty
                  ? 'Directions unavailable'
                  : 'Get directions to ${resource.name}',
              icon: Icons.directions,
              onPressed: resource.address.isEmpty ? null : _directions,
            ),
            _action(
              label: 'Share feedback about ${resource.name}',
              icon: Icons.feedback_outlined,
              onPressed: () => _offerFeedback('manual'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailText(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Semantics(
          label: '$label: $value',
          child: Text('$label: $value'),
        ),
      );

  Widget _action({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    String? hint,
  }) =>
      Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        hint: hint,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
          ),
        ),
      );
}

class PhoneSignInScreen extends StatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen> {
  final _phone = TextEditingController(text: '+91');
  final _code = TextEditingController();
  String? _verificationId;
  String? _status;
  bool _waitingForCode = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() => _status = 'Sending verification code.');
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phone.text.trim(),
      verificationCompleted: (credential) async {
        final result =
            await FirebaseAuth.instance.signInWithCredential(credential);
        if (mounted) Navigator.of(context).pop(result.user);
      },
      verificationFailed: (error) {
        if (mounted) {
          setState(() => _status =
              'Could not verify this number: ${error.message ?? error.code}');
        }
      },
      codeSent: (id, _) {
        if (mounted) {
          setState(() {
            _verificationId = id;
            _waitingForCode = true;
            _status = 'Enter the verification code sent by SMS.';
          });
        }
      },
      codeAutoRetrievalTimeout: (id) => _verificationId = id,
    );
  }

  Future<void> _verifyCode() async {
    final id = _verificationId;
    if (id == null) return;
    final credential = PhoneAuthProvider.credential(
      verificationId: id,
      smsCode: _code.text.trim(),
    );
    final result = await FirebaseAuth.instance.signInWithCredential(credential);
    if (mounted) Navigator.of(context).pop(result.user);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sign in to save resources')),
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                  'Use your phone number to save resources to your list.'),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
              if (_waitingForCode)
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'SMS verification code'),
                ),
              if (_status != null)
                Semantics(
                    liveRegion: true, label: _status!, child: Text(_status!)),
              Semantics(
                button: true,
                label: _waitingForCode
                    ? 'Verify phone number'
                    : 'Send verification code',
                child: ElevatedButton(
                  onPressed: _waitingForCode ? _verifyCode : _sendCode,
                  child: Text(_waitingForCode ? 'Verify code' : 'Send code'),
                ),
              ),
            ],
          ),
        ),
      );
}

class FeedbackResponse {
  const FeedbackResponse({
    required this.didTheyAnswer,
    required this.wasInformationAccurate,
    required this.wasServiceAvailable,
    required this.wasContactHelpful,
    required this.notes,
  });

  final String didTheyAnswer;
  final String wasInformationAccurate;
  final String wasServiceAvailable;
  final String wasContactHelpful;
  final String notes;
}

class FeedbackDialog extends StatefulWidget {
  const FeedbackDialog({required this.resourceName, super.key});

  final String resourceName;

  @override
  State<FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends State<FeedbackDialog> {
  final _notes = TextEditingController();
  String _didTheyAnswer = 'unknown';
  String _wasInformationAccurate = 'unsure';
  String _wasServiceAvailable = 'unsure';
  String _wasContactHelpful = 'unsure';

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Semantics(
          header: true,
          child: Text('Feedback about ${widget.resourceName}'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _question(
                'Did they answer your call?',
                _didTheyAnswer,
                {'yes': 'Yes', 'no': 'No', 'unknown': 'I did not call'},
                (value) => _didTheyAnswer = value,
              ),
              _question(
                'Was the information accurate?',
                _wasInformationAccurate,
                {
                  'yes': 'Yes',
                  'partly': 'Partly',
                  'no': 'No',
                  'unsure': 'Not sure'
                },
                (value) => _wasInformationAccurate = value,
              ),
              _question(
                'Was the service available?',
                _wasServiceAvailable,
                {'yes': 'Yes', 'no': 'No', 'unsure': 'Not sure'},
                (value) => _wasServiceAvailable = value,
              ),
              _question(
                'Was contacting them helpful?',
                _wasContactHelpful,
                {'yes': 'Yes', 'no': 'No', 'unsure': 'Not sure'},
                (value) => _wasContactHelpful = value,
              ),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Anything else? Optional',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          Semantics(
            button: true,
            label: 'Submit feedback',
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(
                FeedbackResponse(
                  didTheyAnswer: _didTheyAnswer,
                  wasInformationAccurate: _wasInformationAccurate,
                  wasServiceAvailable: _wasServiceAvailable,
                  wasContactHelpful: _wasContactHelpful,
                  notes: _notes.text.trim(),
                ),
              ),
              child: const Text('Submit feedback'),
            ),
          ),
        ],
      );

  Widget _question(
    String label,
    String value,
    Map<String, String> options,
    void Function(String) onChanged,
  ) =>
      Semantics(
        label: label,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: options.entries
              .map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ))
              .toList(),
          onChanged: (next) {
            if (next != null) setState(() => onChanged(next));
          },
        ),
      );
}
