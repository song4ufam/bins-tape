import 'app_updater_types.dart';

/// 웹 빌드용: 앱 자체 업데이트는 폰 앱(APK)에서만 동작한다.
Future<UpdateInfo?> checkForUpdate() async => null;

Stream<UpdateProgress> installUpdate(UpdateInfo info) => const Stream.empty();
