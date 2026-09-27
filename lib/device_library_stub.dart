import 'device_library_types.dart';

/// 웹 빌드용: 폰 음악 라이브러리 스캔은 모바일에서만 된다.
bool get deviceLibrarySupported => false;

Future<bool> requestDeviceLibraryPermission() async => false;

Future<List<DeviceSong>> queryDeviceSongs() async => [];
