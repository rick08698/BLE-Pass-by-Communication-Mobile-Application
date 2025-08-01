import 'package:flutter/material.dart';
import 'services/personality_service.dart';
import 'main.dart';

class PersonalitySelectionPage extends StatefulWidget {
  const PersonalitySelectionPage({Key? key}) : super(key: key);

  @override
  State<PersonalitySelectionPage> createState() => _PersonalitySelectionPageState();
}

class _PersonalitySelectionPageState extends State<PersonalitySelectionPage> {
  String? _selectedPersonality;
  final PersonalityService _personalityService = PersonalityService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF6B6B),
              Color(0xFFFFE66D),
              Color(0xFF4ECDC4),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 40),
                
                // タイトル
                const Text(
                  '好みのタイプを選択',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black26,
                        offset: Offset(2.0, 2.0),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                const Text(
                  'マッチした相手の性格タイプを選んでください',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        blurRadius: 5.0,
                        color: Colors.black26,
                        offset: Offset(1.0, 1.0),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 60),
                
                // 性格選択カード
                Expanded(
                  child: ListView.builder(
                    itemCount: PersonalityService.availablePersonalities.length,
                    itemBuilder: (context, index) {
                      final personality = PersonalityService.availablePersonalities[index];
                      final isSelected = _selectedPersonality == personality['style'];
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedPersonality = personality['style'];
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isSelected 
                                ? Colors.white.withOpacity(0.9)
                                : Colors.white.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected 
                                  ? const Color(0xFFFF6B6B)
                                  : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // 性格アイコン
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: _getPersonalityColor(personality['style']),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _getPersonalityIcon(personality['style']),
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                                
                                const SizedBox(width: 20),
                                
                                // 性格情報
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        personality['name'],
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected 
                                            ? const Color(0xFFFF6B6B)
                                            : Colors.grey[800],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _getPersonalityDescription(personality['style']),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                
                                // 選択アイコン
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFFFF6B6B),
                                    size: 30,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // 開始ボタン
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _selectedPersonality != null ? _startApp : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B6B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 8,
                        shadowColor: Colors.black.withOpacity(0.3),
                      ),
                      child: Text(
                        _selectedPersonality != null ? 'アプリを開始' : '性格を選択してください',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getPersonalityColor(String style) {
    switch (style) {
      case 'aggressive':
        return Colors.red;
      case 'seductive':
        return Colors.pink;
      case 'religious':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getPersonalityIcon(String style) {
    switch (style) {
      case 'aggressive':
        return Icons.flash_on;
      case 'seductive':
        return Icons.favorite;
      case 'religious':
        return Icons.auto_awesome;
      default:
        return Icons.person;
    }
  }

  String _getPersonalityDescription(String style) {
    switch (style) {
      case 'aggressive':
        return 'ツンデレで情熱的な性格';
      case 'seductive':
        return '魅力的で色っぽい性格';
      case 'religious':
        return '神聖で平和的な性格';
      default:
        return '一般的な性格';
    }
  }

  void _startApp() {
    if (_selectedPersonality != null) {
      // ユーザーの好みの性格を保存
      _personalityService.setUserPreferredPersonality(_selectedPersonality!);
      
      // メインアプリに遷移
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const BleTestPage(language: 'ja'),
        ),
      );
    }
  }
}