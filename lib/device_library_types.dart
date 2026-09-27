/// 폰에 있는 음악 한 곡 (MediaStore에서 읽어온 정보).
class DeviceSong {
  final String path; // 실제 파일 경로 (기존 Track.audioAsset과 같은 키로 씀)
  final String title;
  final String artist;
  final Duration duration;

  const DeviceSong({
    required this.path,
    required this.title,
    required this.artist,
    required this.duration,
  });
}
