import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:logger/logger.dart';

class VideoService {
  static final VideoService _instance = VideoService._internal();
  factory VideoService() => _instance;
  VideoService._internal();

  final Logger _logger = Logger();
  VideoPlayerController? _currentController;

  // 動画プレイヤーコントローラを作成
  Future<VideoPlayerController?> createController(String videoPath) async {
    try {
      _logger.i("動画コントローラ作成開始: $videoPath");
      final controller = VideoPlayerController.asset(videoPath);
      _logger.i("VideoPlayerController.asset作成完了");
      
      await controller.initialize();
      _logger.i("動画コントローラ初期化完了: $videoPath");
      _logger.i("動画サイズ: ${controller.value.size}");
      _logger.i("動画時間: ${controller.value.duration}");
      
      return controller;
    } catch (e) {
      _logger.e("動画コントローラ初期化エラー: $videoPath", error: e);
      _logger.e("エラー詳細: ${e.toString()}");
      return null;
    }
  }

  // 現在のコントローラを設定
  void setCurrentController(VideoPlayerController? controller) {
    _currentController = controller;
  }

  // 現在のコントローラを取得
  VideoPlayerController? getCurrentController() => _currentController;

  // 動画を再生
  Future<void> play() async {
    try {
      await _currentController?.play();
      _logger.i("動画再生開始");
    } catch (e) {
      _logger.e("動画再生エラー", error: e);
    }
  }

  // 動画を停止
  Future<void> pause() async {
    try {
      await _currentController?.pause();
      _logger.i("動画再生停止");
    } catch (e) {
      _logger.e("動画停止エラー", error: e);
    }
  }

  // 動画をループ設定
  void setLooping(bool isLooping) {
    try {
      _currentController?.setLooping(isLooping);
      _logger.i("動画ループ設定: $isLooping");
    } catch (e) {
      _logger.e("動画ループ設定エラー", error: e);
    }
  }

  // 動画の音量を設定
  void setVolume(double volume) {
    try {
      _currentController?.setVolume(volume.clamp(0.0, 1.0));
      _logger.i("動画音量設定: $volume");
    } catch (e) {
      _logger.e("動画音量設定エラー", error: e);
    }
  }

  // コントローラを解放
  void disposeController(VideoPlayerController? controller) {
    try {
      controller?.dispose();
      if (controller == _currentController) {
        _currentController = null;
      }
      _logger.i("動画コントローラを解放しました");
    } catch (e) {
      _logger.e("動画コントローラ解放エラー", error: e);
    }
  }

  // すべてのリソースを解放
  void dispose() {
    try {
      _currentController?.dispose();
      _currentController = null;
      _logger.i("VideoService を解放しました");
    } catch (e) {
      _logger.e("VideoService 解放エラー", error: e);
    }
  }
}