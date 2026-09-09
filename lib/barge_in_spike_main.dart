import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'barge_in_spike_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  runApp(const BargeInSpikeApp());
}

class BargeInSpikeApp extends StatelessWidget {
  const BargeInSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barge-in VAD spike',
      theme: ThemeData(useMaterial3: true),
      home: const BargeInSpikeScreen(),
    );
  }
}
