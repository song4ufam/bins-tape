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
  // MediaStore가 같은 파일을 여러 행으로 중복 인덱싱할 때가 있어서, 실제 파일 경로
  // 기준으로 한 번씩만 남긴다.
  final seenPaths = <String>{};
  return [
    for (final s in songs)
      if (s.data.isNotEmpty && seenPaths.add(s.data))
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
