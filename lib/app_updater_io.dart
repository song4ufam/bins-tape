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
/// usePackageInstaller=false가 쓰는 ACTION_INSTALL_PACKAGE는 최신 안드로이드에서
/// 폐지(deprecated)돼서 처리할 액티비티가 없으면 예외로 앱이 죽는다(실제로 겪은 문제).
/// PackageInstaller 세션 방식(true)은 REQUEST_INSTALL_PACKAGES 권한이 매니페스트에
/// 있어야 설치 확인창이 뜬다 - 이 권한은 나중에 추가됐고 이 방식은 그 이후 제대로
/// 테스트된 적이 없어서 다시 이걸로 되돌린다.
Stream<UpdateProgress> installUpdate(UpdateInfo info) async* {
  await for (final event in OtaUpdate().execute(
    info.apkUrl,
    destinationFilename: 'BinsTape-update.apk',
    usePackageInstaller: true,
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
