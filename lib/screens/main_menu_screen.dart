import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import 'game_screen.dart';

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  int _highestLevel = 1;

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  void _loadProgress() {
    setState(() {
      _highestLevel = StorageService.highestUnlockedLevel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'CHAIN POP',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Highest Level: $_highestLevel',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 48),
            // Sleek play button
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => GameScreen(level: _highestLevel),
                  ),
                ).then((_) => _loadProgress());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 10,
                shadowColor: Colors.white.withOpacity(0.5),
              ),
              child: const Text(
                'PLAY',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () async {
                await StorageService.clearProgress();
                _loadProgress();
              },
              child: const Text(
                'RESET PROGRESS',
                style: TextStyle(color: Colors.redAccent),
              ),
            )
          ],
        ),
      ),
    );
  }
}
