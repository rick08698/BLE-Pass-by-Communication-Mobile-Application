import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';
import '../services/video_service.dart';

class BackgroundVideoWidget extends StatefulWidget {
  final String videoPath;
  final Widget child;
  final bool shouldPlay;
  final double opacity;

  const BackgroundVideoWidget({
    Key? key,
    required this.videoPath,
    required this.child,
    this.shouldPlay = true,
    this.opacity = 0.7,
  }) : super(key: key);

  @override
  State<BackgroundVideoWidget> createState() => _BackgroundVideoWidgetState();
}

class _BackgroundVideoWidgetState extends State<BackgroundVideoWidget> {
  VideoPlayerController? _controller;
  final VideoService _videoService = VideoService();
  final Logger _logger = Logger();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _logger.i("BackgroundVideoWidget: 動画初期化開始 - ${widget.videoPath}");
    _logger.i("BackgroundVideoWidget: shouldPlay = ${widget.shouldPlay}");
    
    try {
      // VideoPlayerControllerを直接作成
      _controller = VideoPlayerController.asset(widget.videoPath);
      _logger.i("VideoPlayerController作成完了");
      
      // 初期化を実行
      await _controller!.initialize();
      _logger.i("動画初期化完了 - サイズ: ${_controller!.value.size}, 時間: ${_controller!.value.duration}");
      
      // 初期化成功時の設定
      if (mounted && _controller!.value.isInitialized) {
        _controller!.setLooping(true);
        _controller!.setVolume(0.0);
        
        setState(() {
          _isInitialized = true;
        });
        _logger.i("BackgroundVideoWidget: 初期化フラグ設定完了");
        
        if (widget.shouldPlay) {
          _logger.i("BackgroundVideoWidget: 動画再生開始");
          await _controller!.play();
        }
      }
      
    } catch (e) {
      _logger.e("BackgroundVideoWidget: 初期化エラー", error: e);
      _logger.e("エラー詳細: ${e.toString()}");
      
      // エラーの場合はフォールバック背景を表示
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(BackgroundVideoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.shouldPlay != oldWidget.shouldPlay && _controller != null) {
      if (widget.shouldPlay) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i("BackgroundVideoWidget: build() - _isInitialized = $_isInitialized, _controller != null = ${_controller != null}");
    
    return Stack(
      children: [
        // 背景動画
        if (_isInitialized && _controller != null)
          Positioned.fill(
            child: Opacity(
              opacity: widget.opacity,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),
        
        // フォールバック背景（動画が読み込まれない場合）
        if (!_isInitialized)
          Positioned.fill(
            child: Container(
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
            ),
          ),
        
        
        // 子ウィジェット
        widget.child,
      ],
    );
  }
}