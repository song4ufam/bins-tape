import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_updater_types.dart';

/// 새 버전이 있으면 정보를 돌려주고, 없거나 확인에 실패하면 null (조용히 넘어간다).
Future<UpdateInfo?> checkForUpdate() async {
  if (kUpdateRepo.isEmpty) return null;
  try {
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final latest = UpdateInfo.fromGithubRelease(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    if (latest == null) return null;

    final current =
        int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;
    return latest.build > current ? latest : null;
  } catch (_) {
    return null;
  }
}

/// APK를 내려받고 설치 화면을 띄운다. 진행 상황을 스트림으로 알려준다.
///
/// usePackageInstaller(PackageInstaller 세션 방식)를 켜면 설치 성공/실패를 돌려받을 수
/// 있지만, 일부 기기(특히 제조사 커스텀 안드로이드)에서 설치 확인창 자체를 안 띄우고
/// 무한 대기에 빠지는 문제가 있었다. 그래서 더 단순하고 호환성 좋은 ACTION_INSTALL_PACKAGE
/// 방식을 쓴다 - 설치 화면은 확실히 뜨지만, 설치가 끝났는지는 앱이 알 수 없다(그래서
/// "완료" 신호 없이 스트림이 곧바로 끝난다).
Stream<UpdateProgress> installUpdate(UpdateInfo info) async* {
  await for (final event in OtaUpdate().execute(
    info.apkUrl,
    destinationFilename: 'BinsTape-update.apk',
    usePackageInstaller: false,
  )) {
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        yield UpdateProgress(
          UpdateStage.downloading,
          percent: int.tryParse(event.value ?? ''),
        );
      case OtaStatus.INSTALLING:
        yield const UpdateProgress(UpdateStage.installing);
      case OtaStatus.INSTALLATION_DONE:
        yield const UpdateProgress(UpdateStage.done);
      case OtaStatus.CANCELED:
        yield const UpdateProgress(
          UpdateStage.error,
          message: '설치를 취소했어요.',
        );
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        yield const UpdateProgress(
          UpdateStage.error,
          message: '설치 권한이 필요해요. 설정에서 이 앱의 "출처를 알 수 없는 앱 설치"를 허용해주세요.',
        );
      default:
        yield UpdateProgress(
          UpdateStage.error,
          message: event.value ?? '업데이트에 실패했어요.',
        );
    }
  }
}
