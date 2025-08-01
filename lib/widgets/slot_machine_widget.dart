import 'package:flutter/material.dart';

class SlotMachineWidget extends StatelessWidget {
  final Animation<double> animation;
  final int intimacyLevel;

  const SlotMachineWidget({
    Key? key,
    required this.animation,
    required this.intimacyLevel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.yellow, width: 3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildSlotReel(isFixed: true, symbol: '7'),
          _buildSlotReel(isFixed: false, symbol: '?'),
          _buildSlotReel(isFixed: true, symbol: '7'),
        ],
      ),
    );
  }

  Widget _buildSlotReel({required bool isFixed, required String symbol}) {
    if (isFixed) {
      return _buildFixedReel();
    } else {
      return _buildAnimatedReel();
    }
  }

  Widget _buildFixedReel() {
    return Container(
      width: 60,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: const Center(
        child: Text(
          '7',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedReel() {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        String currentSymbol;
        
        if (animation.isCompleted) {
          // アニメーション完了時は結果に基づいて最終シンボルを決定
          double successRate;
          if (intimacyLevel >= 30) {
            successRate = 1.0;
          } else {
            successRate = 0.2 + (intimacyLevel / 30.0 * 0.8);
            successRate = successRate.clamp(0.2, 0.95);
          }
          
          final random = DateTime.now().millisecondsSinceEpoch % 100;
          final shouldSucceed = random < (successRate * 100);
          currentSymbol = shouldSucceed ? '7' : '3';
        } else {
          // アニメーション中はランダムにシンボルを変化
          final symbols = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
          final currentIndex = (animation.value * symbols.length * 15).floor() % symbols.length;
          currentSymbol = symbols[currentIndex];
        }
        
        return Container(
          width: 60,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Center(
            child: Text(
              currentSymbol,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: currentSymbol == '7' ? Colors.red : Colors.black,
              ),
            ),
          ),
        );
      },
    );
  }
}