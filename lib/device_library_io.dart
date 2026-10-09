import 'dart:io';

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
          s.isMusic != false &&
          !_looksLikeSystemSound(s.data) &&
          seenKeys.add('${s.title}|${s.duration}|${s.size}'))
        DeviceSong(
          path: s.data,
          title: s.title,
          artist: (s.artist == null || s.artist == '<unknown>')
              ? '알 수 없는 아티스트'
              : s.artist!,
          duration: Duration(milliseconds: s.duration ?? 0),
          id: s.id,
        ),
  ];
}

/// 삼성 기본 벨소리/알림음처럼 시스템이 미리 깔아둔 소리 파일은 사용자 음악이
/// 아니라서 제외한다. isMusic 플래그가 false거나 안 믿을만한 기종도 있어서,
/// 경로로도 한 번 더 걸러준다.
bool _looksLikeSystemSound(String path) {
  final lower = path.toLowerCase();
  return lower.contains('/ringtones/') ||
      lower.contains('/notifications/') ||
      lower.contains('/alarms/') ||
      lower.contains('/product/media/') ||
      lower.contains('/system/media/') ||
      // 삼성 기기는 "Over the Horizon" 같은 기본 샘플곡을 Music/Samsung/ 안에 심어둔다.
      lower.contains('/music/samsung/');
}

/// 파일 안에 박혀있는 앨범아트(ID3 임베드 이미지)를 꺼내서 캐시 파일로 저장하고
/// 그 경로를 돌려준다. 임베드된 이미지가 없으면 null (인터넷 검색으로 넘어간다).
Future<String?> fetchEmbeddedArtworkPath(int songId) async {
  try {
    final bytes = await _query.queryArtwork(
      songId,
      ArtworkType.AUDIO,
      format: ArtworkFormat.JPEG,
      size: 600,
    );
    if (bytes == null || bytes.isEmpty) return null;

    final dir = await Directory.systemTemp.createTemp('bins_tape_art_');
    final file = File('${dir.path}/$songId.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
