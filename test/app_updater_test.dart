import 'package:bins_tape/app_updater_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> release(String tag, {List<Map<String, dynamic>>? assets}) => {
        'tag_name': tag,
        'body': '새 기능',
        'assets': assets ??
            [
              {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt'},
              {'name': 'BinsTape.apk', 'browser_download_url': 'https://x/BinsTape.apk'},
            ],
      };

  test('태그에서 빌드 번호와 APK 주소를 읽는다', () {
    final info = UpdateInfo.fromGithubRelease(release('v0.1.0+7'))!;
    expect(info.build, 7);
    expect(info.version, '0.1.0+7');
    expect(info.apkUrl, 'https://x/BinsTape.apk');
    expect(info.notes, '새 기능');
  });

  test('v 없는 태그도 읽는다', () {
    expect(UpdateInfo.fromGithubRelease(release('0.2.0+12'))!.build, 12);
  });

  test('빌드 번호가 없는 태그는 무시한다', () {
    expect(UpdateInfo.fromGithubRelease(release('v1.0')), isNull);
  });

  test('APK 파일이 없으면 무시한다', () {
    expect(
      UpdateInfo.fromGithubRelease(release('v0.1.0+2', assets: [
        {'name': 'notes.txt', 'browser_download_url': 'https://x/notes.txt'},
      ])),
      isNull,
    );
  });
}
