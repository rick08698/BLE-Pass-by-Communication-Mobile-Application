import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/video_service.dart';

class FullscreenVideoWidget extends StatefulWidget {
  final String videoPath;
  final VoidCallback? onVideoCompleted;
  final Duration? autoDismissAfter;

  const FullscreenVideoWidget({
    Key? key,
    required this.videoPath,
    this.onVideoCompleted,
    this.autoDismissAfter,
  }) : super(key: key);

  @override
  State<FullscreenVideoWidget> createState() => _FullscreenVideoWidgetState();
}

class _FullscreenVideoWidgetState extends State<FullscreenVideoWidget> {
  VideoPlayerController? _controller;
  final VideoService _videoService = VideoService();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      // 直接VideoPlayerControllerを作成
      _controller = VideoPlayerController.asset(widget.videoPath);
      
      // 初期化を実行
      await _controller!.initialize();
      
      if (mounted && _controller!.value.isInitialized) {
        _controller!.setLooping(false); // 1回だけ再生
        _controller!.setVolume(0.5); // 適度な音量
        
        // 動画完了時のリスナーを追加
        _controller!.addListener(_videoListener);
        
        setState(() {
          _isInitialized = true;
        });

        // 動画を自動再生
        await _controller!.play();

        // 自動解除タイマー（設定されている場合）
        if (widget.autoDismissAfter != null) {
          Future.delayed(widget.autoDismissAfter!, () {
            if (mounted) {
              _onVideoCompleted();
            }
          });
        }
      }
    } catch (e) {
      // 動画が初期化できない場合は即座に完了コールバックを呼ぶ
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _onVideoCompleted();
        }
      });
    }
  }

  void _videoListener() {
    if (_controller != null && 
        _controller!.value.isInitialized && 
        _controller!.value.position >= _controller!.value.duration) {
      _onVideoCompleted();
    }
  }

  void _onVideoCompleted() {
    if (widget.onVideoCompleted != null) {
      widget.onVideoCompleted!();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          // フルスクリーン動画
          if (_isInitialized && _controller != null)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
          
          // フォールバック表示（動画が読み込まれない場合）
          if (!_isInitialized)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [
                          Colors.pink,
                          Colors.purple,
                          Colors.blue,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.favorite,
                      size: 80,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    '🎉 告白成功！ 🎉',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'おめでとうございます！',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          
          // スキップボタン（右上）
          Positioned(
            top: 50,
            right: 20,
            child: GestureDetector(
              onTap: _onVideoCompleted,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'スキップ',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}