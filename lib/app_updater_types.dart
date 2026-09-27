/// 앱 자체 업데이트 설정과 공용 타입.
///
/// 새 버전을 올려두는 곳은 GitHub 릴리스다. 저장소를 만든 뒤 아래에 'GitHub아이디/저장소이름'을
/// 적으면(예: 'binsmusic/bins-tape') 앱이 실행될 때 새 버전이 있는지 확인한다.
/// 비워두면 업데이트 확인 기능은 꺼져 있다.
const String kUpdateRepo = 'song4ufam/bins-tape';

class UpdateInfo {
  final String version; // 예: 0.1.0+3
  final int build; // 버전 뒤 + 다음 숫자(빌드 번호). 이게 클수록 새 버전.
  final String apkUrl;
  final String notes;

  const UpdateInfo({
    required this.version,
    required this.build,
    required this.apkUrl,
    required this.notes,
  });

  /// GitHub 'releases/latest' 응답에서 만든다. 태그 이름은 pubspec 버전과 같게 붙인다
  /// (예: 0.1.0+3 또는 v0.1.0+3). APK 파일이 없거나 빌드 번호를 못 읽으면 null.
  static UpdateInfo? fromGithubRelease(Map<String, dynamic> json) {
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final buildMatch = RegExp(r'\+(\d+)').firstMatch(tag);
    if (buildMatch == null) return null;

    final assets = (json['assets'] as List<dynamic>? ?? const []);
    for (final a in assets) {
      final asset = a as Map<String, dynamic>;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String?;
      if (name.endsWith('.apk') && url != null) {
        return UpdateInfo(
          version: tag.startsWith('v') ? tag.substring(1) : tag,
          build: int.parse(buildMatch.group(1)!),
          apkUrl: url,
          notes: (json['body'] as String?)?.trim() ?? '',
        );
      }
    }
    return null;
  }
}

enum UpdateStage { downloading, installing, done, error }

class UpdateProgress {
  final UpdateStage stage;
  final int? percent;
  final String? message;
  const UpdateProgress(this.stage, {this.percent, this.message});
}
