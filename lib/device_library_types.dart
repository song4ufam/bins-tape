/// 폰에 있는 음악 한 곡 (MediaStore에서 읽어온 정보).
class DeviceSong {
  final String path; // 실제 파일 경로 (기존 Track.audioAsset과 같은 키로 씀)
  final String title;
  final String artist;
  final Duration duration;

  /// MediaStore 안에서의 고유 id. 파일에 박혀있는 앨범아트(임베드 아트워크)를
  /// 나중에 다시 꺼내올 때 이 id가 필요하다.
  final int id;

  const DeviceSong({
    required this.path,
    required this.title,
    required this.artist,
    required this.duration,
    required this.id,
  });
}
