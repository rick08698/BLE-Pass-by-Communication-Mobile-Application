import 'package:flutter/material.dart';
import '../services/personality_service.dart';

class AvatarWidget extends StatelessWidget {
  final String macAddress;
  final double size;
  final bool showSpeakingAnimation;

  const AvatarWidget({
    Key? key,
    required this.macAddress,
    this.size = 50,
    this.showSpeakingAnimation = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (showSpeakingAnimation) {
      return SpeakingAvatarWidget(macAddress: macAddress, size: size);
    }
    return StaticAvatarWidget(macAddress: macAddress, size: size);
  }
}

class StaticAvatarWidget extends StatelessWidget {
  final String macAddress;
  final double size;

  const StaticAvatarWidget({
    Key? key,
    required this.macAddress,
    required this.size,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final avatarPath = PersonalityService().generateAvatarPath(macAddress);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.pink, width: 2),
      ),
      child: ClipOval(
        child: Image.asset(
          avatarPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // フォールバック：画像が見つからない場合
            return Container(
              width: size,
              height: size,
              color: Colors.grey[300],
              child: Icon(
                Icons.person,
                size: size * 0.6,
                color: Colors.grey[600],
              ),
            );
          },
        ),
      ),
    );
  }
}

class SpeakingAvatarWidget extends StatefulWidget {
  final String macAddress;
  final double size;

  const SpeakingAvatarWidget({
    Key? key,
    required this.macAddress,
    required this.size,
  }) : super(key: key);

  @override
  State<SpeakingAvatarWidget> createState() => _SpeakingAvatarWidgetState();
}

class _SpeakingAvatarWidgetState extends State<SpeakingAvatarWidget>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    // アニメーションをループ
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.pink.withOpacity(0.3),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: StaticAvatarWidget(
              macAddress: widget.macAddress,
              size: widget.size,
            ),
          ),
        );
      },
    );
  }
}