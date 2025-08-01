import 'package:audioplayers/audioplayers.dart';
import 'package:logger/logger.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer(); // 効果音用
  final AudioPlayer _bgmPlayer = AudioPlayer();   // BGM用
  final Logger _logger = Logger();
  
  String? _currentBgm; // 現在再生中のBGM

  // 成功音を再生
  Future<void> playSuccessSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/success.mp3'));
      _logger.i("成功音を再生しました");
    } catch (e) {
      _logger.e("音声再生エラー", error: e);
    }
  }

  // 告白イベント開始時の音声を再生
  Future<void> playConfessionStartSound(int intimacyLevel) async {
    try {
      String audioFile;
      
      if (intimacyLevel >= 30) {
        audioFile = 'audio/変動開始時エンブレム完成音（激アツ）.mp3';
        _logger.i("激アツ音声を再生: 親密度=$intimacyLevel");
      } else {
        audioFile = 'audio/変動開始時エンブレム完成音（チャンス）.mp3';
        _logger.i("チャンス音声を再生: 親密度=$intimacyLevel");
      }
      
      await _audioPlayer.play(AssetSource(audioFile));
    } catch (e) {
      _logger.e("告白音声再生エラー", error: e);
    }
  }

  // カップル成立時のサウンドを再生
  Future<void> playCoupleFormationSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/BATTLE_BONUS_3000獲得音.mp3'));
      _logger.i("カップル成立音を再生しました");
    } catch (e) {
      _logger.e("カップル成立音再生エラー", error: e);
    }
  }

  // 音声再生を停止
  Future<void> stop() async {
    try {
      await _audioPlayer.stop();
    } catch (e) {
      _logger.e("音声停止エラー", error: e);
    }
  }

  // BGMを再生
  Future<void> playBGM(String audioFile, {bool loop = true}) async {
    try {
      if (_currentBgm == audioFile) {
        return; // 同じBGMが既に再生中の場合は何もしない
      }
      
      await _bgmPlayer.stop(); // 現在のBGMを停止
      
      if (loop) {
        await _bgmPlayer.setReleaseMode(ReleaseMode.loop);
      } else {
        await _bgmPlayer.setReleaseMode(ReleaseMode.stop);
      }
      
      await _bgmPlayer.setVolume(0.3); // BGMは少し音量を下げる
      await _bgmPlayer.play(AssetSource(audioFile));
      _currentBgm = audioFile;
      
      _logger.i("BGM再生開始: $audioFile");
    } catch (e) {
      _logger.e("BGM再生エラー", error: e);
    }
  }

  // BGMを停止
  Future<void> stopBGM() async {
    try {
      await _bgmPlayer.stop();
      _currentBgm = null;
      _logger.i("BGMを停止しました");
    } catch (e) {
      _logger.e("BGM停止エラー", error: e);
    }
  }

  // BGMの音量を調整
  Future<void> setBGMVolume(double volume) async {
    try {
      await _bgmPlayer.setVolume(volume.clamp(0.0, 1.0));
    } catch (e) {
      _logger.e("BGM音量調整エラー", error: e);
    }
  }

  // 現在再生中のBGMを取得
  String? getCurrentBGM() => _currentBgm;

  // リソースを解放
  void dispose() {
    _audioPlayer.dispose();
    _bgmPlayer.dispose();
  }
}