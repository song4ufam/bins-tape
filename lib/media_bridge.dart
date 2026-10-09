import 'package:audio_service/audio_service.dart';

/// 잠금화면/알림의 재생 컨트롤(재생·일시정지·다음·이전)을 담당하는 다리 역할.
///
/// 실제 재생 로직은 여전히 main.dart의 MusicPlayerScreen이 audioplayers로 직접
/// 관리한다 — 이 핸들러는 그 상태를 안드로이드 미디어 세션에 그대로 비춰주고,
/// 잠금화면에서 버튼을 누르면 등록된 콜백을 통해 기존 재생 로직을 불러주는
/// 얇은 중개자일 뿐이다. (재생 엔진을 통째로 바꾸는 건 위험이 너무 커서 피했다.)
class BinsTapeAudioHandler extends BaseAudioHandler {
  Future<void> Function()? onPlayPressed;
  Future<void> Function()? onPausePressed;
  Future<void> Function()? onNextPressed;
  Future<void> Function()? onPreviousPressed;
  Future<void> Function(Duration)? onSeekPressed;

  @override
  Future<void> play() async => onPlayPressed?.call();

  @override
  Future<void> pause() async => onPausePressed?.call();

  @override
  Future<void> skipToNext() async => onNextPressed?.call();

  @override
  Future<void> skipToPrevious() async => onPreviousPressed?.call();

  @override
  Future<void> seek(Duration position) async => onSeekPressed?.call(position);

  /// 지금 재생 중인 곡 정보를 잠금화면/알림에 반영한다.
  void publishMediaItem({
    required String title,
    required String artist,
    required Duration duration,
    Uri? artUri,
  }) {
    mediaItem.add(MediaItem(
      id: title, // 로컬 재생 전용이라 실제 URI 대신 식별용 문자열이면 충분하다.
      title: title,
      artist: artist,
      duration: duration,
      artUri: artUri,
    ));
  }

  /// 재생/일시정지, 위치를 잠금화면/알림에 반영한다.
  void publishPlaybackState({
    required bool playing,
    required Duration position,
    bool buffering = false,
  }) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.skipToPrevious,
        MediaAction.skipToNext,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: buffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
    ));
  }
}

BinsTapeAudioHandler? _audioHandler;

/// main()에서 한 번만 초기화한다. 실패해도(웹 등) 앱이 죽지 않도록 조용히 넘어간다.
Future<BinsTapeAudioHandler?> initAudioHandler() async {
  try {
    _audioHandler = await AudioService.init(
      builder: () => BinsTapeAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.bins_tape.audio',
        androidNotificationChannelName: "Bin's Tape 재생 중",
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
    return _audioHandler;
  } catch (_) {
    return null;
  }
}

BinsTapeAudioHandler? get audioHandler => _audioHandler;
