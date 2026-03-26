import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../game/chain_pop_game.dart';
import '../services/storage_service.dart';

class GameScreen extends StatefulWidget {
  final int level;

  const GameScreen({super.key, required this.level});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late ChainPopGame game;

  @override
  void initState() {
    super.initState();
    game = ChainPopGame(
      levelId: widget.level,
      onWin: _handleWin,
    );
  }
  
  void _handleWin() async {
    // Unlock next level
    await StorageService.unlockLevel(widget.level + 1);
    
    if (!mounted) return;
    
    // Show win dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Level Cleared!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Awesome job. Ready for the next puzzle?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pop(); // game screen, back to menu
            },
            child: const Text('MAIN MENU', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F2FE),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.of(context).pop(); // dialog
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => GameScreen(level: widget.level + 1)),
              );
            },
            child: const Text('NEXT LEVEL', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GameWidget(game: game),
          
          // HUD / Back Button
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: 60,
            right: 20,
            child: Text(
              'LEVEL ${widget.level}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
