import 'package:on_audio_query/on_audio_query.dart';

import 'device_library_types.dart';

bool get deviceLibrarySupported => true;

final _query = OnAudioQuery();

Future<bool> requestDeviceLibraryPermission() async {
  if (await _query.permissionsStatus()) return true;
  return _query.permissionsRequest();
}

/// 폰에 있는 모든 오디오 파일을 훑어서 제목/가수 순으로 돌려준다.
/// 카카오톡 다운로드 폴더처럼 어디에 저장돼 있든, MediaStore에 잡히기만 하면 나온다.
Future<List<DeviceSong>> queryDeviceSongs() async {
  final songs = await _query.querySongs(
    sortType: SongSortType.TITLE,
    orderType: OrderType.ASC_OR_SMALLER,
    uriType: UriType.EXTERNAL,
  );
  // MediaStore가 같은 파일을 여러 행으로 중복 인덱싱할 때가 있다. 경로 문자열만
  // 비교하면 /storage/emulated/0/... 와 /sdcard/... 처럼 같은 파일을 가리키는
  // 다른 표기를 놓치므로, 제목+길이+파일 크기를 묶어서 판단한다.
  final seenKeys = <String>{};
  return [
    for (final s in songs)
      if (s.data.isNotEmpty &&
          seenKeys.add('${s.title}|${s.duration}|${s.size}'))
        DeviceSong(
          path: s.data,
          title: s.title,
          artist: (s.artist == null || s.artist == '<unknown>')
              ? '알 수 없는 아티스트'
              : s.artist!,
          duration: Duration(milliseconds: s.duration ?? 0),
        ),
  ];
}
