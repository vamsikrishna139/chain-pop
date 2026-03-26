import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/main_menu_screen.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Storage (Hive)
  await Hive.initFlutter();
  await StorageService.init();

  // Mock Initialization for Firebase, Ads, Analytics
  await _mockInitExternalServices();

  runApp(const ChainPopApp());
}

Future<void> _mockInitExternalServices() async {
  // Simulate init delay
  await Future.delayed(const Duration(milliseconds: 100));
}

class ChainPopApp extends StatelessWidget {
  const ChainPopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chain Pop',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E24), // Sleek dark mode
        fontFamily: 'Inter',
        useMaterial3: true,
      ),
      home: const MainMenuScreen(),
    );
  }
}
