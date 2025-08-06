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
  String _currentLanguage = 'ja'; // デフォルト言語

  // 多言語対応テキスト
  final Map<String, Map<String, String>> _texts = {
    'ja': {
      'title': '好みのタイプを選択',
      'subtitle': 'マッチした相手の性格タイプを選んでください',
      'start_button': 'アプリを開始',
      'select_first': '性格を選択してください',
    },
    'en': {
      'title': 'Select Your Preferred Type',
      'subtitle': 'Choose the personality type for your matched partners',
      'start_button': 'Start App',
      'select_first': 'Please select a personality',
    },
  };

  String _getText(String key) {
    return _texts[_currentLanguage]?[key] ?? _texts['ja']?[key] ?? key;
  }

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
                
                // 言語切り替えボタン
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _currentLanguage = _currentLanguage == 'ja' ? 'en' : 'ja';
                        });
                      },
                      child: Text(
                        _currentLanguage == 'ja' ? 'English' : '日本語',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // タイトル
                Text(
                  _getText('title'),
                  style: const TextStyle(
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
                
                Text(
                  _getText('subtitle'),
                  style: const TextStyle(
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
                        _selectedPersonality != null ? _getText('start_button') : _getText('select_first'),
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
      case 'gentle':
        return Colors.green;
      case 'cool':
        return Colors.blue;
      case 'cute':
        return Colors.pink.shade300;
      case 'aggressive':
        return Colors.red;
      case 'seductive':
        return Colors.pink;
      case 'cheerful':
        return Colors.orange;
      case 'shy':
        return Colors.purple.shade300;
      case 'mysterious':
        return Colors.indigo;
      case 'energetic':
        return Colors.amber;
      case 'intellectual':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getPersonalityIcon(String style) {
    switch (style) {
      case 'gentle':
        return Icons.favorite_border;
      case 'cool':
        return Icons.ac_unit;
      case 'cute':
        return Icons.emoji_emotions;
      case 'aggressive':
        return Icons.flash_on;
      case 'seductive':
        return Icons.favorite;
      case 'cheerful':
        return Icons.wb_sunny;
      case 'shy':
        return Icons.sentiment_neutral;
      case 'mysterious':
        return Icons.visibility_off;
      case 'energetic':
        return Icons.bolt;
      case 'intellectual':
        return Icons.school;
      default:
        return Icons.person;
    }
  }

  String _getPersonalityDescription(String style) {
    final descriptions = {
      'ja': {
        'gentle': '心優しく思いやりのある性格',
        'cool': 'クールで冷静沈着な性格',
        'cute': '可愛らしく愛らしい性格',
        'aggressive': 'ツンデレで情熱的な性格',
        'seductive': '魅力的で色っぽい性格',
        'cheerful': '明るくポジティブな性格',
        'shy': '恥ずかしがり屋で控えめな性格',
        'mysterious': 'ミステリアスで謎めいた性格',
        'energetic': '元気いっぱいでパワフルな性格',
        'intellectual': '知的で論理的な性格',
      },
      'en': {
        'gentle': 'Kind and caring personality',
        'cool': 'Cool and composed personality',
        'cute': 'Adorable and charming personality',
        'aggressive': 'Tsundere and passionate personality',
        'seductive': 'Attractive and alluring personality',
        'cheerful': 'Bright and positive personality',
        'shy': 'Shy and reserved personality',
        'mysterious': 'Mysterious and enigmatic personality',
        'energetic': 'Energetic and powerful personality',
        'intellectual': 'Intelligent and logical personality',
      },
    };
    
    return descriptions[_currentLanguage]?[style] ?? 
           descriptions['ja']?[style] ?? 
           'General personality';
  }

  void _startApp() {
    if (_selectedPersonality != null) {
      // ユーザーの好みの性格を保存
      _personalityService.setUserPreferredPersonality(_selectedPersonality!);
      
      // メインアプリに遷移（選択した言語を引き渡し）
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => BleTestPage(language: _currentLanguage),
        ),
      );
    }
  }
}