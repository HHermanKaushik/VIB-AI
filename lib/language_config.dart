/// Supported voice languages and their rollout state.
///
/// Keep user-facing language availability behind [validatedLanguages]. A
/// language is not ready for users until native command review and real-device
/// barge-in testing are complete.
class LanguageConfig {
  const LanguageConfig({
    required this.languageCode,
    required this.displayNameNative,
    required this.selectionPrompt,
    required this.sttSupported,
    required this.ttsSupported,
    required this.validated,
    required this.rolloutTranche,
  });

  final String languageCode;
  final String displayNameNative;
  final String selectionPrompt;
  final bool sttSupported;
  final bool ttsSupported;
  final bool validated;
  final int rolloutTranche;
}

const supportedLanguages = <LanguageConfig>[
  LanguageConfig(
    languageCode: 'en-IN',
    displayNameNative: 'English',
    selectionPrompt: "For English, say 'English'.",
    sttSupported: true,
    ttsSupported: true,
    validated: true,
    rolloutTranche: 1,
  ),
  LanguageConfig(
    languageCode: 'hi-IN',
    displayNameNative: 'हिन्दी',
    selectionPrompt: "हिन्दी के लिए 'हिन्दी' कहें।",
    sttSupported: true,
    ttsSupported: true,
    validated: true,
    rolloutTranche: 1,
  ),
  LanguageConfig(
    languageCode: 'ta-IN',
    displayNameNative: 'தமிழ்',
    selectionPrompt: "தமிழுக்கு 'தமிழ்' என்று சொல்லுங்கள்.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'te-IN',
    displayNameNative: 'తెలుగు',
    selectionPrompt: "తెలుగు కోసం 'తెలుగు' అని చెప్పండి.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'bn-IN',
    displayNameNative: 'বাংলা',
    selectionPrompt: "বাংলার জন্য 'বাংলা' বলুন।",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'ml-IN',
    displayNameNative: 'മലയാളം',
    selectionPrompt: "മലയാളത്തിനായി 'മലയാളം' എന്ന് പറയുക.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'mr-IN',
    displayNameNative: 'मराठी',
    selectionPrompt: "मराठीसाठी 'मराठी' म्हणा.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'gu-IN',
    displayNameNative: 'ગુજરાતી',
    selectionPrompt: "ગુજરાતી માટે 'ગુજરાતી' કહો.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'kn-IN',
    displayNameNative: 'ಕನ್ನಡ',
    selectionPrompt: "ಕನ್ನಡಕ್ಕಾಗಿ 'ಕನ್ನಡ' ಎಂದು ಹೇಳಿ.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'pa-IN',
    displayNameNative: 'ਪੰਜਾਬੀ',
    selectionPrompt: "ਪੰਜਾਬੀ ਲਈ 'ਪੰਜਾਬੀ' ਕਹੋ.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'od-IN',
    displayNameNative: 'ଓଡ଼ିଆ',
    selectionPrompt: "ଓଡ଼ିଆ ପାଇଁ 'ଓଡ଼ିଆ' କୁହନ୍ତୁ.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
  LanguageConfig(
    languageCode: 'as-IN',
    displayNameNative: 'অসমীয়া',
    selectionPrompt: "অসমীয়াৰ বাবে 'অসমীয়া' কওক.",
    sttSupported: true,
    ttsSupported: true,
    validated: false,
    rolloutTranche: 2,
  ),
];

/// Languages eligible to appear in user-facing flows.
List<LanguageConfig> get validatedLanguages => supportedLanguages
    .where((language) => language.validated)
    .toList(growable: false);

LanguageConfig get defaultLanguage => validatedLanguages.first;
