import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'app_updater_types.dart';
import 'device_library_types.dart';
import 'device_library_stub.dart' if (dart.library.io) 'device_library_io.dart';
import 'app_updater_stub.dart' if (dart.library.io) 'app_updater_io.dart';
import 'lyrics_ocr.dart';
import 'ocr_service_stub.dart' if (dart.library.js_interop) 'ocr_service_web.dart';
import 'media_bridge.dart';
import 'package:home_widget/home_widget.dart';
import 'art_image_stub.dart' if (dart.library.io) 'art_image_io.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAudioHandler();
  runApp(const BinsTapeApp());
}

// ---------------------------------------------------------------------------
// 🎨 App Root & Theme  (에이전트 1: 딥 네이비 + 아날로그 감성)
// ---------------------------------------------------------------------------
class BinsTapeApp extends StatelessWidget {
  const BinsTapeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Bin's Tape",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: BinsTapeColors.deepNavy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: BinsTapeColors.tapeAmber,
          brightness: Brightness.dark,
          surface: BinsTapeColors.deepNavy,
        ),
        fontFamily: 'Georgia',
      ),
      home: const MusicPlayerScreen(),
    );
  }
}

/// 앱 전역 컬러 팔레트 — 'Bin's' 로고의 REC 카본 블랙 아이덴티티.
class BinsTapeColors {
  static const deepNavy = Color(0xFF0E0E10); // 카본 블랙 배경
  static const navyCard = Color(0xFF1C1C1F); // 카본 패널
  static const tapeAmber = Color(0xFFE0332F); // REC 레드 (포인트/활성 상태)
  static const tapeCream = Color(0xFFF5F1EC); // 오프화이트 텍스트
  static const magneticBrown = Color(0xFF2A2A2D); // 카본 텍스처 톤
  static const dimText = Color(0xFF8A8A8E);
}

/// 앱 톤(다크 + REC 레드)에 맞춘 공용 스낵바.
void showBinsTapeSnackBar(
  BuildContext context,
  String message, {
  IconData icon = Icons.auto_awesome,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(icon, color: BinsTapeColors.tapeAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: BinsTapeColors.tapeCream,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: BinsTapeColors.navyCard,
      behavior: SnackBarBehavior.floating,
      // Scaffold 자체는 브라우저 창 전체 폭이라, 폭을 안 정해두면 스낵바가
      // 실제 폰 비율 콘텐츠(480px) 밖으로 삐져나가 왼쪽에 텍스트만 걸쳐 보인다.
      width: 440,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: BinsTapeColors.tapeAmber.withValues(alpha: 0.4),
        ),
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}

// ---------------------------------------------------------------------------
// 🎵 데이터 모델 — 가사 한 줄 + 곡 메타데이터 (에이전트 2)
// ---------------------------------------------------------------------------
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

/// 반복 재생 모드: 꺼짐 → 전체 반복 → 한 곡 반복 순으로 순환한다.
enum RepeatMode { off, all, one }

class Track {
  final String title;
  final String artist;
  final String albumArtAsset;
  final String audioAsset;
  final List<LyricLine> lyrics;

  /// true면 audioAsset은 번들 애셋 경로가 아니라 기기 저장소의 실제 파일 경로.
  final bool isDeviceFile;

  /// true면 albumArtAsset은 로컬 애셋이 아니라 인터넷에서 찾아온 이미지 URL.
  final bool isNetworkArt;

  /// 가사 검색에만 쓰는 별도 아티스트/제목. 영어 파일명이 lrclib에서
  /// 로마자 표기 가사로 잘못 매칭될 때, 원어(한글) 키워드로 보정하기 위함.
  /// null이면 title/artist를 그대로 검색어로 쓴다.
  final String? lyricsSearchArtist;
  final String? lyricsSearchTitle;

  const Track({
    required this.title,
    required this.artist,
    required this.albumArtAsset,
    required this.audioAsset,
    required this.lyrics,
    this.isDeviceFile = false,
    this.isNetworkArt = false,
    this.lyricsSearchArtist,
    this.lyricsSearchTitle,
  });

  /// 파일명에서 "아티스트 - 제목.mp3" 패턴을 추론해 트랙을 만든다.
  factory Track.fromDeviceFile(String path) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    final dot = fileName.lastIndexOf('.');
    final nameNoExt = dot > 0 ? fileName.substring(0, dot) : fileName;

    String title = nameNoExt;
    String artist = '알 수 없는 아티스트';
    if (nameNoExt.contains(' - ')) {
      final parts = nameNoExt.split(' - ');
      artist = parts.first.trim();
      title = parts.sublist(1).join(' - ').trim();
    }

    return Track(
      title: title,
      artist: artist,
      albumArtAsset: 'assets/images/sample_cover.jpg',
      audioAsset: path,
      lyrics: const [],
      isDeviceFile: true,
    );
  }
}

/// "알 수 없는 아티스트"는 화면에 보여주기 위한 표시용 문구일 뿐인데, 그대로
/// 검색어에 섞어 보내면 인터넷 검색(가사/앨범아트)이 엉뚱한 결과를 찾아온다.
/// 검색어로 쓸 때는 빈 문자열로 바꿔서 제목만으로 검색되게 한다.
String searchableArtist(String artist) =>
    artist == '알 수 없는 아티스트' ? '' : artist;

/// audioplayers에 넘길 Source를 트랙 종류에 맞게 만들어준다.
Source buildAudioSource(Track track) {
  return track.isDeviceFile
      ? DeviceFileSource(track.audioAsset)
      : AssetSource(track.audioAsset);
}

/// 기기에서 추가한 재생목록(파일 경로 목록)을 앱을 껐다 켜도 유지되도록 저장.
class PlaylistStore {
  static const _key = 'bins_tape_device_playlist_paths';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? [];
  }

  static Future<void> save(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, paths);
  }
}

/// 사용자가 이름 붙여 만든 재생목록(이름 → 곡 키 목록)을 기기에 저장한다.
/// 곡 키는 Track.audioAsset (기기 파일 경로 또는 데모 애셋 경로).
class CustomPlaylistsStore {
  static const _key = 'bins_tape_custom_playlists';

  static Future<Map<String, List<String>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (name, keys) => MapEntry(name, List<String>.from(keys as List)),
    );
  }

  static Future<void> save(Map<String, List<String>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }
}

/// 사용자가 직접 편집/잠금한 곡별 정보(제목/아티스트/가사/잠금 여부)를
/// 앱을 껐다 켜도 유지되도록 저장한다. 곡 경로(audioAsset)가 키.
class ManualEditsStore {
  static const _key = 'bins_tape_manual_edits';

  static Future<Map<String, Map<String, dynamic>>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
    );
  }

  static Future<void> save(Map<String, Map<String, dynamic>> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }
}

/// LyricLine 리스트를 다시 LRC 텍스트로 되돌린다 (편집창에 채워넣거나 저장할 때 사용).
String lyricsToLrc(List<LyricLine> lyrics) {
  return lyrics.map((line) {
    final m = line.time.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = line.time.inSeconds.remainder(60).toString().padLeft(2, '0');
    final cs = (line.time.inMilliseconds.remainder(1000) ~/ 10)
        .toString()
        .padLeft(2, '0');
    return '[$m:$s.$cs] ${line.text}';
  }).join('\n');
}

/// LRC 포맷([mm:ss.xx] 가사) 문자열을 파싱해 LyricLine 리스트로 변환.
/// 파일명/외부 LRC 파일 로딩 시 이 파서를 재사용한다.
List<LyricLine> parseLrc(String raw) {
  final lineExp = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,2}))?\](.*)');
  final result = <LyricLine>[];
  for (final line in raw.split('\n')) {
    final match = lineExp.firstMatch(line.trim());
    if (match == null) continue;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final centis = int.parse((match.group(3) ?? '0').padRight(2, '0'));
    final text = match.group(4)!.trim();
    if (text.isEmpty) continue;
    result.add(LyricLine(
      Duration(minutes: minutes, seconds: seconds, milliseconds: centis * 10),
      text,
    ));
  }
  result.sort((a, b) => a.time.compareTo(b.time));
  return result;
}

/// 인터넷에서 싱크 가사(lrclib.net)와 앨범 아트(iTunes Search API)를
/// 자동으로 찾아오는 서비스. 파일명에서 뽑은 아티스트/제목으로 검색한다.
class LyricsService {
  /// 같은 곡이라도 인트로 길이가 다른 여러 버전(음원/유튜브 립 등)이 있어서,
  /// 무작정 첫 검색 결과를 쓰면 가사가 밀린다. search API로 후보를 모두 받아
  /// 실제 mp3 재생 길이(targetDuration)와 가장 가까운 버전을 골라야 안 밀린다.
  static Future<List<LyricLine>> fetchSyncedLyrics({
    required String artist,
    required String title,
    Duration? targetDuration,
  }) async {
    var candidates = (await searchCandidates(artist: artist, title: title))
        .where((r) => (r['syncedLyrics'] as String?)?.isNotEmpty == true)
        .toList();
    if (candidates.isEmpty) return [];

    // 검색어가 한글(아티스트/제목에 한글 별칭을 썼다는 뜻)인데, lrclib에는 같은 곡의
    // 로마자 표기 버전도 섞여있는 경우가 많다. 한글 검색이면 한글 가사가 있는
    // 후보를 우선하고, 하나도 없을 때만 로마자 버전으로 눈감아준다.
    final hangul = RegExp(r'[가-힣]');
    if (hangul.hasMatch(artist) || hangul.hasMatch(title)) {
      final hangulCandidates = candidates
          .where((r) => hangul.hasMatch(r['syncedLyrics'] as String))
          .toList();
      if (hangulCandidates.isNotEmpty) candidates = hangulCandidates;
    }

    Map<String, dynamic> best;
    if (targetDuration == null) {
      best = candidates.first;
    } else {
      final targetSeconds = targetDuration.inMilliseconds / 1000;
      best = candidates.reduce((a, b) {
        final da = ((a['duration'] as num?) ?? 0).toDouble();
        final db = ((b['duration'] as num?) ?? 0).toDouble();
        return (da - targetSeconds).abs() <= (db - targetSeconds).abs()
            ? a
            : b;
      });
    }

    return parseLrc(best['syncedLyrics'] as String);
  }

  /// 자동 매칭이 틀렸을 때 사용자가 직접 고를 수 있도록 원본 후보 목록을 그대로 반환한다.
  /// "가수+제목"으로 검색해서 결과가 없으면, 제목만으로, 그래도 없으면 제목에서
  /// 괄호 표기(예: "Episode (에피소드)")를 떼어내고 다시 시도한다.
  static Future<List<Map<String, dynamic>>> searchCandidates({
    required String artist,
    required String title,
  }) async {
    var results = await _lrclibSearch(
      'artist_name=${Uri.encodeComponent(artist)}'
      '&track_name=${Uri.encodeComponent(title)}',
    );
    if (results.isNotEmpty) return results;

    if (title.isNotEmpty) {
      results = await _lrclibSearch('q=${Uri.encodeComponent(title)}');
      if (results.isNotEmpty) return results;
    }

    final cleanedTitle = title.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();
    if (cleanedTitle.isNotEmpty && cleanedTitle != title) {
      results = await _lrclibSearch('q=${Uri.encodeComponent(cleanedTitle)}');
      if (results.isNotEmpty) return results;
    }

    return [];
  }

  static Future<List<Map<String, dynamic>>> _lrclibSearch(
      String queryString) async {
    try {
      final url = Uri.parse('https://lrclib.net/api/search?$queryString');
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final results = jsonDecode(response.body) as List<dynamic>;
      return results.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// 실패하면 null을 반환한다 (호출부에서 기존 이미지를 유지).
  static Future<String?> fetchAlbumArtUrl({
    required String artist,
    required String title,
  }) async {
    try {
      final query = Uri.encodeComponent('$artist $title');
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$query&media=music&limit=1',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if ((data['resultCount'] as int? ?? 0) == 0) return null;

      final rawArtwork = data['results'][0]['artworkUrl100'] as String?;
      return rawArtwork?.replaceAll('100x100bb', '600x600bb');
    } catch (_) {
      return null;
    }
  }

  /// 자동 매칭이 틀렸거나 못 찾았을 때 사용자가 직접 고를 수 있도록 iTunes 검색
  /// 결과 여러 개를 그대로 돌려준다 (제목+아티스트로 검색, 없으면 제목만으로).
  static Future<List<Map<String, dynamic>>> searchAlbumArtCandidates({
    required String artist,
    required String title,
  }) async {
    final combined = await _itunesSearch('$artist $title');
    if (combined.isNotEmpty) return combined;
    if (title.isEmpty) return [];
    return _itunesSearch(title);
  }

  static Future<List<Map<String, dynamic>>> _itunesSearch(
      String term) async {
    try {
      final query = Uri.encodeComponent(term);
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$query&media=music&limit=8',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (data['results'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
      return [
        for (final r in results)
          if (r['artworkUrl100'] != null)
            {
              'trackName': r['trackName'],
              'artistName': r['artistName'],
              'artworkUrl': (r['artworkUrl100'] as String)
                  .replaceAll('100x100bb', '600x600bb'),
            },
      ];
    } catch (_) {
      return [];
    }
  }
}

// 데모용 재생목록 (실제로는 파일 스캔 + LRC 로더로 대체될 자리)
final demoPlaylist = <Track>[
  Track(
    title: 'RINGA LINGA',
    artist: 'TAEYANG',
    albumArtAsset: 'assets/images/sample_cover.jpg',
    audioAsset: 'audio/TAEYANG - RINGA LINGA.mp3',
    // '무제' 데모 가사는 assets/lyrics/무제.lrc 로 따로 보관해둠 — 이 곡 실제 가사 아님.
    lyrics: parseLrc(''),
  ),
  Track(
    title: '겁도 없이',
    artist: 'B.I (feat. BIG Naughty)',
    albumArtAsset: 'assets/images/sample_cover.jpg',
    audioAsset: 'audio/B.I - 겁도 없이 (feat.BIG Naughty).mp3',
    lyrics: parseLrc(''),
    // "feat." 표기가 붙으면 검색이 잘 안 맞아서 아티스트명만 따로 지정.
    lyricsSearchArtist: 'B.I',
    lyricsSearchTitle: '겁도 없이',
  ),
  Track(
    title: 'If You',
    artist: 'BIGBANG',
    albumArtAsset: 'assets/images/sample_cover.jpg',
    audioAsset: 'audio/BIGBANG - If You.mp3',
    lyrics: parseLrc(''),
    // 영어 아티스트명 그대로 검색하면 로마자 표기 가사가 잡혀서 한글로 보정.
    lyricsSearchArtist: '빅뱅',
    lyricsSearchTitle: 'If You',
  ),
  Track(
    title: 'TONIGHT',
    artist: 'BIGBANG',
    albumArtAsset: 'assets/images/sample_cover.jpg',
    audioAsset: 'audio/BIGBANG - TONIGHT.mp3',
    lyrics: parseLrc(''),
    lyricsSearchArtist: '빅뱅',
    lyricsSearchTitle: 'TONIGHT',
  ),
  Track(
    title: 'Heartbreaker',
    artist: 'G-Dragon',
    albumArtAsset: 'assets/images/sample_cover.jpg',
    audioAsset: 'audio/G-Dragon - 02 Heartbreaker.mp3',
    lyrics: parseLrc(''),
    lyricsSearchArtist: 'G-DRAGON',
    lyricsSearchTitle: 'Heartbreaker',
  ),
  Track(
    title: '가시',
    artist: '버즈 (Buzz)',
    albumArtAsset: 'assets/images/sample_cover.jpg',
    audioAsset: 'audio/버즈(Buzz) - 가시.mp3',
    lyrics: parseLrc(''),
  ),
  Track(
    title: '에피소드',
    artist: '이무진',
    albumArtAsset: 'assets/images/sample_cover.jpg',
    audioAsset: 'audio/이무진 - 에피소드.mp3',
    lyrics: parseLrc(''),
  ),
];

// ---------------------------------------------------------------------------
// 🖥️ MusicPlayerScreen (에이전트 1: UI/UX + 플레이어 코어)
// ---------------------------------------------------------------------------
class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  late final AnimationController _reelController;

  int _currentIndex = 0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isShuffle = false;
  RepeatMode _repeatMode = RepeatMode.off;
  double _volume = 1.0;

  /// 기기에서 사용자가 직접 추가한 곡의 파일 경로 목록 (앱 재시작 후에도 유지됨).
  List<String> _devicePaths = [];

  /// 파일 경로 -> MediaStore id. 파일에 박혀있는 앨범아트를 꺼내올 때 필요하다.
  final Map<String, int> _deviceSongIds = {};

  // 파일명만으로는 실제 가사/앨범아트를 알 수 없어서, 인터넷에서 찾아온 결과를
  // audioAsset(경로)을 키로 캐싱해둔다. device 트랙은 getter가 호출될 때마다
  // 새 Track 인스턴스를 만들기 때문에, 이 캐시가 없으면 fetch 결과가 매번 사라진다.
  final Map<String, List<LyricLine>> _lyricsCache = {};
  final Map<String, String> _albumArtCache = {};
  final Set<String> _fetchingKeys = {};

  /// 사용자가 편집 모달에서 직접 고친 제목/아티스트 (곡 경로가 키).
  final Map<String, String> _titleOverrides = {};
  final Map<String, String> _artistOverrides = {};

  /// 직접 저장한 가사인지 표시 (자동으로 찾아온 가사와 구분해서 영구 저장하기 위함).
  final Set<String> _manualLyricsKeys = {};

  /// 사용자가 직접 고른 앨범아트 URL (곡 경로가 키). 있으면 자동 검색보다 우선한다.
  final Map<String, String> _albumArtOverrides = {};

  /// 잠긴 곡은 '인터넷에서 다시 검색'으로도 덮어쓸 수 없다.
  final Set<String> _lockedKeys = {};
  bool get _isCurrentTrackLocked => _lockedKeys.contains(_track.audioAsset);

  /// 곡마다 따로 기억하는 가사 싱크 보정값(초). 음수면 가사가 더 늦게 뜨도록 당김.
  Map<String, double> _syncOffsets = {};
  double get _currentSyncOffset => _syncOffsets[_track.audioAsset] ?? 0.0;

  /// 이름 붙여 만든 재생목록 (이름 → 곡 키 목록). null인 활성 목록은 '전체 곡'.
  Map<String, List<String>> _playlists = {};
  String? _activePlaylist;

  /// 전체 곡 = 기기에서 추가한 곡. 하나도 없을 때 데모 곡은 웹 미리보기에서만 보여준다
  /// (폰 앱에는 음원을 넣어 배포하지 않는다).
  List<String> get _libraryKeys => _devicePaths.isEmpty
      ? (kIsWeb ? demoPlaylist.map((t) => t.audioAsset).toList() : <String>[])
      : _devicePaths;

  List<String> get _activeKeys => _activePlaylist == null
      ? _libraryKeys
      : (_playlists[_activePlaylist] ?? const []);

  Track _trackForKey(String key) {
    for (final t in demoPlaylist) {
      if (t.audioAsset == key) return t;
    }
    return Track.fromDeviceFile(key);
  }

  List<Track> get _tracks =>
      _activeKeys.map(_trackForKey).map(_applyFetchedMetadata).toList();

  Track _applyFetchedMetadata(Track base) {
    final cachedLyrics = _lyricsCache[base.audioAsset];
    final cachedArt = _albumArtCache[base.audioAsset];
    final overrideTitle = _titleOverrides[base.audioAsset];
    final overrideArtist = _artistOverrides[base.audioAsset];
    if (cachedLyrics == null &&
        cachedArt == null &&
        overrideTitle == null &&
        overrideArtist == null) {
      return base;
    }
    return Track(
      title: overrideTitle ?? base.title,
      artist: overrideArtist ?? base.artist,
      albumArtAsset: cachedArt ?? base.albumArtAsset,
      audioAsset: base.audioAsset,
      lyrics: cachedLyrics ?? base.lyrics,
      isDeviceFile: base.isDeviceFile,
      isNetworkArt: cachedArt != null,
      lyricsSearchArtist: base.lyricsSearchArtist,
      lyricsSearchTitle: base.lyricsSearchTitle,
    );
  }

  static const _emptyTrack = Track(
    title: '곡을 추가해주세요',
    artist: '재생목록 버튼 안의 + 로 폰의 MP3를 골라보세요',
    albumArtAsset: '',
    audioAsset: '',
    lyrics: [],
  );

  Track get _track {
    final tracks = _tracks;
    if (tracks.isEmpty) return _emptyTrack;
    return tracks[_currentIndex.clamp(0, tracks.length - 1)];
  }

  /// 현재 트랙의 가사/앨범아트를 아직 못 찾아왔다면 lrclib.net / iTunes에서 가져온다.
  /// 가사는 버전(인트로 길이)에 따라 밀릴 수 있어서, 실제 mp3 재생 길이를 알기
  /// 전까지는(즉 _duration이 준비되기 전까지는) 가사 fetch를 미룬다.
  /// 앨범아트를 구한다. 파일에 이미 박혀있는 이미지(임베드 아트워크)가 있으면
  /// 그걸 꺼내 쓰고, 없을 때만 인터넷(iTunes)에서 찾아본다.
  Future<String?> _resolveAlbumArt(Track track) async {
    final songId = _deviceSongIds[track.audioAsset];
    if (songId != null) {
      final embedded = await fetchEmbeddedArtworkPath(songId);
      if (embedded != null) return embedded;
    }
    return LyricsService.fetchAlbumArtUrl(
      artist: searchableArtist(track.lyricsSearchArtist ?? track.artist),
      title: track.lyricsSearchTitle ?? track.title,
    );
  }

  Future<void> _ensureMetadata(Track track) async {
    final key = track.audioAsset;
    if (key.isEmpty) return; // 빈 재생목록 자리표시용 트랙.
    if (_lockedKeys.contains(key)) return; // 잠긴 곡은 자동 검색 대상에서 제외.
    final needsArt = !_albumArtCache.containsKey(key);
    final needsLyrics =
        !_lyricsCache.containsKey(key) && track.lyrics.isEmpty;
    final canFetchLyrics = needsLyrics && _duration > Duration.zero;
    if (!needsArt && !canFetchLyrics) return;
    if (_fetchingKeys.contains(key)) return;

    _fetchingKeys.add(key);
    try {
      final results = await Future.wait([
        canFetchLyrics
            ? LyricsService.fetchSyncedLyrics(
                artist: searchableArtist(track.lyricsSearchArtist ?? track.artist),
                title: track.lyricsSearchTitle ?? track.title,
                targetDuration: _duration,
              )
            : Future.value(<LyricLine>[]),
        needsArt ? _resolveAlbumArt(track) : Future.value(null),
      ]);

      if (!mounted) return;
      setState(() {
        if (canFetchLyrics && (results[0] as List<LyricLine>).isNotEmpty) {
          _lyricsCache[key] = results[0] as List<LyricLine>;
        }
        final artUrl = results[1] as String?;
        if (needsArt && artUrl != null) {
          _albumArtCache[key] = artUrl;
        }
      });
    } finally {
      _fetchingKeys.remove(key);
    }
  }

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _checkForAppUpdate();
    _syncShuffleRepeatFromWidget();
    _loadSavedPlaylist();
    _loadCustomPlaylists();
    _loadSyncOffsets();
    _loadManualEdits().then((_) => _ensureMetadata(_track));

    // 카세트 릴이 재생 중일 때만 천천히 회전하는 애니메이션.
    _reelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
      // 실제 재생 길이를 이제 알았으니, 정확한 버전의 가사를 다시 찾아본다.
      _ensureMetadata(_track);
      _publishMediaSession();
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _isPlaying = s == PlayerState.playing);
      if (_isPlaying) {
        _reelController.repeat();
      } else {
        _reelController.stop();
      }
      _publishMediaSession();
    });
    _completeSub = _player.onPlayerComplete.listen((_) => _onTrackFinished());

    // 잠금화면/알림의 재생·일시정지·다음·이전 버튼을 기존 재생 로직에 연결한다.
    audioHandler
      ?..onPlayPressed = () async {
        if (!_isPlaying) await _togglePlay();
      }
      ..onPausePressed = () async {
        if (_isPlaying) await _togglePlay();
      }
      ..onNextPressed = _playNext
      ..onPreviousPressed = _playPrevious
      ..onSeekPressed = _seekTo;
    _publishMediaSession();
  }

  /// 지금 재생 중인 곡/상태를 잠금화면·알림 미디어 세션에 반영한다.
  void _publishMediaSession() {
    final handler = audioHandler;
    if (handler == null) return;
    Uri? art;
    if (_track.isNetworkArt) {
      try {
        art = Uri.parse(_track.albumArtAsset);
      } catch (_) {
        art = null;
      }
    }
    handler.publishMediaItem(
      title: _track.title,
      artist: _track.artist,
      duration: _duration,
      artUri: art,
    );
    handler.publishPlaybackState(playing: _isPlaying, position: _position);
    _publishHomeWidget();
  }

  /// 홈 화면 위젯에도 같은 재생 상태를 반영한다. 위젯 자체가 없는 환경(웹 등)에서도
  /// 조용히 실패하도록 감싼다.
  Future<void> _publishHomeWidget() async {
    if (kIsWeb) return;
    try {
      await HomeWidget.saveWidgetData<String>('widget_title', _track.title);
      await HomeWidget.saveWidgetData<String>('widget_artist', _track.artist);
      await HomeWidget.saveWidgetData<bool>('widget_is_playing', _isPlaying);
      await HomeWidget.saveWidgetData<bool>('widget_is_shuffle', _isShuffle);
      await HomeWidget.saveWidgetData<String>('widget_repeat_mode', switch (_repeatMode) {
        RepeatMode.all => 'all',
        RepeatMode.one => 'one',
        RepeatMode.off => 'off',
      });
      await HomeWidget.updateWidget(
        qualifiedAndroidName: 'com.example.bins_tape.BinsTapeWidgetProvider',
      );
    } catch (_) {
      // 위젯이 없거나(미지원 플랫폼) 업데이트 실패해도 본 재생에는 영향 없다.
    }
  }

  /// 곡이 끝까지 재생됐을 때 반복 모드에 따라 다음 동작을 결정한다.
  Future<void> _onTrackFinished() async {
    if (!mounted) return;
    switch (_repeatMode) {
      case RepeatMode.one:
        await _seekTo(Duration.zero);
        await _player.resume();
        break;
      case RepeatMode.all:
        await _playNext();
        break;
      case RepeatMode.off:
        // 목록 끝이 아니면 계속 다음 곡으로, 끝이면 멈춘다 (일반적인 플레이어 동작).
        if (_currentIndex < _tracks.length - 1) {
          await _playNext();
        }
        break;
    }
  }

  void _toggleShuffle() {
    setState(() => _isShuffle = !_isShuffle);
    _publishHomeWidget();
  }

  void _cycleRepeatMode() {
    setState(() {
      _repeatMode = switch (_repeatMode) {
        RepeatMode.off => RepeatMode.all,
        RepeatMode.all => RepeatMode.one,
        RepeatMode.one => RepeatMode.off,
      };
    });
    _publishHomeWidget();
  }

  Future<void> _playNext() async {
    final tracks = _tracks;
    if (tracks.length <= 1) return;
    int next;
    if (_isShuffle) {
      final random = math.Random();
      do {
        next = random.nextInt(tracks.length);
      } while (next == _currentIndex);
    } else {
      next = (_currentIndex + 1) % tracks.length;
    }
    await _selectTrack(next);
  }

  Future<void> _playPrevious() async {
    final tracks = _tracks;
    if (tracks.length <= 1) return;
    // 재생한 지 3초가 넘었으면 '이전 곡'이 아니라 현재 곡 처음으로 되돌린다 (일반적인 플레이어 동작).
    if (_position > const Duration(seconds: 3)) {
      await _seekTo(Duration.zero);
      return;
    }
    int prev;
    if (_isShuffle) {
      final random = math.Random();
      do {
        prev = random.nextInt(tracks.length);
      } while (prev == _currentIndex);
    } else {
      prev = (_currentIndex - 1 + tracks.length) % tracks.length;
    }
    await _selectTrack(prev);
  }

  Future<void> _togglePlay() async {
    if (_track.audioAsset.isEmpty) return;
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.resume();
      // 최초 재생 시 소스가 없다면 지정.
      if (_duration == Duration.zero) {
        await _player.play(buildAudioSource(_track));
        await _player.setVolume(_volume);
      }
    }
  }

  Future<void> _seekTo(Duration target) async {
    await _player.seek(target);
  }

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value);
    await _player.setVolume(value);
  }

  Future<void> _selectTrack(int index) async {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await _player.stop();
    await _player.play(buildAudioSource(_track));
    await _player.setVolume(_volume);
    _ensureMetadata(_track);
    _publishMediaSession();
  }

  Future<void> _loadSavedPlaylist() async {
    final paths = await PlaylistStore.load();
    if (!mounted || paths.isEmpty) return;
    setState(() {
      _devicePaths = paths;
      _currentIndex = 0;
    });
    _ensureMetadata(_track);
    _reloadDeviceSongIds();
  }

  /// 앱을 재시작하면 MediaStore id가 기억 안 나 있으니(파일 경로만 저장해뒀음),
  /// 기기 라이브러리를 다시 훑어서 경로 기준으로 id를 다시 매칭해둔다.
  /// 임베드 앨범아트를 꺼내올 때 이 id가 필요하다.
  Future<void> _reloadDeviceSongIds() async {
    if (kIsWeb || !deviceLibrarySupported) return;
    try {
      final songs = await queryDeviceSongs();
      if (!mounted) return;
      for (final s in songs) {
        _deviceSongIds[s.path] = s.id;
      }
    } catch (_) {
      // 권한이 없거나 조회 실패해도 인터넷 검색으로 넘어가면 되니 조용히 넘어간다.
    }
  }

  DateTime? _lastUpdateCheck;
  bool _checkingForUpdate = false;

  /// 새 버전이 있는지 확인하고, 있으면 안내창을 띄운다 (폰 앱에서만 동작).
  /// 앱을 켤 때, 백그라운드에서 돌아올 때, 그리고 설정에서 수동으로 눌렀을 때 부른다.
  /// [manual]이면 새 버전이 없어도 "최신 버전이에요" 안내를 보여준다.
  Future<void> _checkForAppUpdate({bool manual = false}) async {
    if (_checkingForUpdate) return;
    // 자동 확인은 너무 자주 하지 않는다 (앱을 여러 번 왔다갔다 할 때마다 부르지 않도록).
    final now = DateTime.now();
    if (!manual &&
        _lastUpdateCheck != null &&
        now.difference(_lastUpdateCheck!) < const Duration(hours: 1)) {
      return;
    }
    _checkingForUpdate = true;
    _lastUpdateCheck = now;

    final info = await checkForUpdate();
    _checkingForUpdate = false;
    if (!mounted) return;

    if (info == null) {
      if (manual) {
        showBinsTapeSnackBar(context, '최신 버전이에요.', icon: Icons.check_circle_outline);
      }
      return;
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BinsTapeColors.navyCard,
        title: Text('새 버전이 있어요 (${info.version})',
            style: const TextStyle(color: BinsTapeColors.tapeCream)),
        content: Text(
          info.notes.isEmpty ? '지금 업데이트할까요?' : info.notes,
          style: const TextStyle(color: BinsTapeColors.dimText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('나중에',
                style: TextStyle(color: BinsTapeColors.dimText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('업데이트',
                style: TextStyle(color: BinsTapeColors.tapeAmber)),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;

    final progress = ValueNotifier<UpdateProgress>(
        const UpdateProgress(UpdateStage.downloading, percent: 0));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ValueListenableBuilder<UpdateProgress>(
        valueListenable: progress,
        builder: (context, p, _) {
          final waitingForInstallTap = p.stage == UpdateStage.installing;
          return AlertDialog(
            backgroundColor: BinsTapeColors.navyCard,
            title: Text(
              waitingForInstallTap ? '설치 확인창을 확인해주세요' : '업데이트 내려받는 중...',
              style: const TextStyle(color: BinsTapeColors.tapeCream),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: waitingForInstallTap ? null : (p.percent ?? 0) / 100,
                  color: BinsTapeColors.tapeAmber,
                  backgroundColor: BinsTapeColors.magneticBrown,
                ),
                const SizedBox(height: 10),
                Text(
                  waitingForInstallTap
                      ? '안드로이드 설치 확인창에서 "설치"를 눌러주세요.\n'
                          '완료되면 이 창이 저절로 닫혀요.'
                      : '${p.percent ?? 0}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: BinsTapeColors.dimText),
                ),
              ],
            ),
          );
        },
      ),
    );

    String? error;
    var done = false;
    await for (final p in installUpdate(info)) {
      progress.value = p;
      if (p.stage == UpdateStage.error) {
        error = p.message;
        break;
      }
      if (p.stage == UpdateStage.done) {
        done = true;
        break;
      }
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // 진행 창 닫기
    if (error != null) {
      showBinsTapeSnackBar(context, error, icon: Icons.error_outline);
    } else if (done) {
      showBinsTapeSnackBar(context, '설치 완료! 다음에 앱을 열면 새 버전이에요.',
          icon: Icons.check_circle_outline);
    } else {
      // ACTION_INSTALL_PACKAGE 방식은 설치 화면만 띄우고 결과를 알려주지 않는다.
      showBinsTapeSnackBar(context, '설치 화면이 열렸어요. 설치를 마치면 앱을 다시 켜주세요.',
          icon: Icons.open_in_new);
    }
  }

  Future<void> _loadCustomPlaylists() async {
    final saved = await CustomPlaylistsStore.load();
    if (!mounted || saved.isEmpty) return;
    setState(() => _playlists = saved);
  }

  Future<void> _persistPlaylists() => CustomPlaylistsStore.save(_playlists);

  /// 재생목록을 바꾸면 재생 중이던 곡은 멈추고 새 목록의 첫 곡을 가리킨다.
  Future<void> _switchPlaylist(String? name) async {
    if (name == _activePlaylist) return;
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _activePlaylist = name;
      _currentIndex = 0;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _ensureMetadata(_track);
  }

  Future<void> _createPlaylist() async {
    final name = await _askText(title: '새 재생목록 이름', hint: '예: 연습곡, BIGBANG 모음, 발라드');
    if (name == null || name.isEmpty) return;
    if (_playlists.containsKey(name)) {
      if (mounted) showBinsTapeSnackBar(context, '이미 있는 이름이에요.', icon: Icons.info_outline);
      return;
    }
    setState(() => _playlists = {..._playlists, name: []});
    await _persistPlaylists();
  }

  Future<void> _deletePlaylist(String name) async {
    final ok = await _confirm('"$name" 재생목록을 삭제할까요?\n(곡 파일은 지워지지 않아요)');
    if (ok != true) return;
    final wasActive = _activePlaylist == name;
    setState(() {
      _playlists = {..._playlists}..remove(name);
    });
    await _persistPlaylists();
    if (wasActive) await _switchPlaylist(null);
  }

  Future<void> _addKeyToPlaylist(String name, String key) async {
    final list = _playlists[name] ?? [];
    if (list.contains(key)) return;
    setState(() => _playlists = {..._playlists, name: [...list, key]});
    await _persistPlaylists();
  }

  /// 현재 보고 있는 목록에서만 곡을 뺀다 (곡 파일이나 다른 목록에는 영향 없음).
  Future<void> _removeFromActivePlaylist(String key) async {
    final name = _activePlaylist;
    if (name == null) return;
    setState(() {
      _playlists = {
        ..._playlists,
        name: (_playlists[name] ?? []).where((k) => k != key).toList(),
      };
      _currentIndex = math.max(0, math.min(_currentIndex, _activeKeys.length - 1));
    });
    await _persistPlaylists();
  }

  /// 내 곡 목록(전체)에서 곡을 빼고 모든 재생목록에서도 지운다. 파일 자체는 삭제하지 않는다.
  Future<void> _removeFromLibrary(String key) async {
    if (!_devicePaths.contains(key)) return; // 데모 곡은 지울 수 없다.
    final removingCurrent = _track.audioAsset == key;
    if (removingCurrent) await _player.stop();
    setState(() {
      _devicePaths = _devicePaths.where((k) => k != key).toList();
      _playlists = _playlists.map(
        (n, keys) => MapEntry(n, keys.where((k) => k != key).toList()),
      );
      _currentIndex = 0;
      if (removingCurrent) {
        _position = Duration.zero;
        _duration = Duration.zero;
      }
    });
    await PlaylistStore.save(_devicePaths);
    await _persistPlaylists();
  }

  /// 현재 재생 중인 곡을 계속 가리키도록 인덱스를 다시 맞춘다.
  void _keepCurrentTrackIndex(String? currentKey) {
    if (currentKey == null || currentKey.isEmpty) return;
    final i = _activeKeys.indexOf(currentKey);
    if (i >= 0) _currentIndex = i;
  }

  Future<void> _reorderActive(int oldIndex, int newIndex) async {
    final name = _activePlaylist;
    if (name == null) return;
    final currentKey = _track.audioAsset;
    final list = <String>[...(_playlists[name] ?? <String>[])];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() {
      _playlists = {..._playlists, name: list};
      _keepCurrentTrackIndex(currentKey);
    });
    await _persistPlaylists();
  }

  /// 곡을 목록 칩 위에 놓았을 때: 전체 곡에서는 '추가', 내 목록에서는 '이동'.
  Future<void> _dropTrackOnPlaylist(String targetName, int trackIndex) async {
    final keys = _activeKeys;
    if (trackIndex < 0 || trackIndex >= keys.length) return;
    final key = keys[trackIndex];
    await _addKeyToPlaylist(targetName, key);
    if (_activePlaylist != null) await _moveOutOfActive(key);
  }

  /// 현재 목록에서 곡을 빼고, 재생 중이던 곡이면 멈춘다 (이동 처리용).
  Future<void> _moveOutOfActive(String key) async {
    final wasCurrent = _track.audioAsset == key;
    if (wasCurrent) await _player.stop();
    await _removeFromActivePlaylist(key);
    if (wasCurrent && mounted) {
      setState(() {
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
  }

  /// 곡의 ⋮ 메뉴: 다른 목록에 추가 / 다른 목록으로 이동 / 이 목록에서 빼기 / 곡 지우기.
  Future<void> _showTrackActions(int index) async {
    final keys = _activeKeys;
    if (index < 0 || index >= keys.length) return;
    final key = keys[index];
    final track = _trackForKey(key);
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        backgroundColor: BinsTapeColors.navyCard,
        title: Text(track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BinsTapeColors.tapeCream)),
        children: [
          for (final name in _playlists.keys)
            if (name != _activePlaylist)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'add:$name'),
                child: Text('"$name"에 추가',
                    style: const TextStyle(color: BinsTapeColors.tapeCream)),
              ),
          if (_activePlaylist != null)
            for (final name in _playlists.keys)
              if (name != _activePlaylist)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, 'move:$name'),
                  child: Text('"$name"(으)로 이동',
                      style: const TextStyle(color: BinsTapeColors.tapeCream)),
                ),
          if (_playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text('위쪽 "+ 새 목록"으로 재생목록을 먼저 만들어주세요.',
                  style: TextStyle(color: BinsTapeColors.dimText, fontSize: 13)),
            ),
          if (_activePlaylist != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('이 목록에서 빼기',
                  style: TextStyle(color: BinsTapeColors.tapeAmber)),
            ),
          if (_activePlaylist == null && _devicePaths.contains(key))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('내 곡 목록에서 지우기',
                  style: TextStyle(color: BinsTapeColors.tapeAmber)),
            ),
        ],
      ),
    );
    if (action == null) return;
    if (action.startsWith('add:')) {
      await _addKeyToPlaylist(action.substring(4), key);
    } else if (action.startsWith('move:')) {
      await _addKeyToPlaylist(action.substring(5), key);
      await _moveOutOfActive(key);
    } else if (action == 'remove') {
      await _removeFromActivePlaylist(key);
    } else if (action == 'delete') {
      await _removeFromLibrary(key);
    }
  }

  Future<String?> _askText({required String title, String? hint}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BinsTapeColors.navyCard,
        title: Text(title, style: const TextStyle(color: BinsTapeColors.tapeCream)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: BinsTapeColors.tapeCream),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: BinsTapeColors.dimText),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소', style: TextStyle(color: BinsTapeColors.dimText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('만들기', style: TextStyle(color: BinsTapeColors.tapeAmber)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirm(String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BinsTapeColors.navyCard,
        content: Text(message, style: const TextStyle(color: BinsTapeColors.tapeCream)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: BinsTapeColors.dimText)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: BinsTapeColors.tapeAmber)),
          ),
        ],
      ),
    );
  }

  static const _syncOffsetsKey = 'bins_tape_sync_offsets';

  Future<void> _loadSyncOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_syncOffsetsKey);
    if (raw == null || !mounted) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      _syncOffsets = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    });
  }

  Future<void> _saveSyncOffsets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncOffsetsKey, jsonEncode(_syncOffsets));
  }

  /// 현재 곡의 가사 싱크를 delta초만큼 보정하고, 곡별로 영구 저장한다.
  void _adjustSync(double delta) {
    final key = _track.audioAsset;
    setState(() {
      _syncOffsets = {
        ..._syncOffsets,
        key: (_syncOffsets[key] ?? 0.0) + delta,
      };
    });
    _saveSyncOffsets();
  }

  Future<void> _loadManualEdits() async {
    final data = await ManualEditsStore.load();
    if (!mounted || data.isEmpty) return;
    setState(() {
      data.forEach((key, val) {
        final title = val['title'] as String?;
        final artist = val['artist'] as String?;
        final lrc = val['lrc'] as String?;
        final locked = val['locked'] as bool? ?? false;
        if (title != null) _titleOverrides[key] = title;
        if (artist != null) _artistOverrides[key] = artist;
        if (lrc != null && lrc.isNotEmpty) {
          _lyricsCache[key] = parseLrc(lrc);
          _manualLyricsKeys.add(key);
        }
        final art = val['art'] as String?;
        if (art != null && art.isNotEmpty) {
          _albumArtOverrides[key] = art;
          _albumArtCache[key] = art;
        }
        if (locked) _lockedKeys.add(key);
      });
    });
  }

  Future<void> _persistManualEdits() async {
    final keys = {
      ..._titleOverrides.keys,
      ..._artistOverrides.keys,
      ..._manualLyricsKeys,
      ..._lockedKeys,
      ..._albumArtOverrides.keys,
    };
    final data = <String, Map<String, dynamic>>{};
    for (final key in keys) {
      data[key] = {
        if (_titleOverrides.containsKey(key)) 'title': _titleOverrides[key],
        if (_artistOverrides.containsKey(key)) 'artist': _artistOverrides[key],
        if (_manualLyricsKeys.contains(key))
          'lrc': lyricsToLrc(_lyricsCache[key] ?? const []),
        if (_albumArtOverrides.containsKey(key))
          'art': _albumArtOverrides[key],
        'locked': _lockedKeys.contains(key),
      };
    }
    await ManualEditsStore.save(data);
  }

  /// 사용자가 직접 입력한 제목/아티스트/LRC 가사를 그대로 저장한다.
  /// 이후 자동 검색으로 덮어써지지 않고(캐시에 값이 있으므로), 기기에도 영구 저장된다.
  void _saveManualEdit({
    required String title,
    required String artist,
    required String lrcText,
  }) {
    final key = _track.audioAsset;
    setState(() {
      _titleOverrides[key] = title;
      _artistOverrides[key] = artist;
      _lyricsCache[key] = parseLrc(lrcText);
      _manualLyricsKeys.add(key);
    });
    _persistManualEdits();
  }

  /// 사용자가 검색 후보 중에서 직접 고른 앨범아트를 저장한다. 이후 자동 검색으로
  /// 덮어써지지 않는다.
  void _saveAlbumArtOverride(String url) {
    final key = _track.audioAsset;
    setState(() {
      _albumArtOverrides[key] = url;
      _albumArtCache[key] = url;
    });
    _persistManualEdits();
  }

  /// 수정한 제목/아티스트로 lrclib.net / iTunes를 다시 검색한다. 잠긴 곡은 호출되지 않는다.
  /// 재검색한 가사를 돌려준다 (편집창에서 텍스트박스를 바로 갱신하기 위함).
  Future<List<LyricLine>> _refetchMetadata({
    required String title,
    required String artist,
  }) async {
    final key = _track.audioAsset;
    setState(() {
      _titleOverrides[key] = title;
      _artistOverrides[key] = artist;
    });

    final results = await Future.wait([
      LyricsService.fetchSyncedLyrics(
        artist: artist,
        title: title,
        targetDuration: _duration,
      ),
      LyricsService.fetchAlbumArtUrl(artist: artist, title: title),
    ]);

    final lyrics = results[0] as List<LyricLine>;
    if (!mounted) return lyrics;
    setState(() {
      if (lyrics.isNotEmpty) {
        _lyricsCache[key] = lyrics;
        _manualLyricsKeys.add(key);
      }
      final art = results[1] as String?;
      if (art != null) _albumArtCache[key] = art;
    });
    _persistManualEdits();
    return lyrics;
  }

  void _toggleLock() {
    final key = _track.audioAsset;
    setState(() {
      if (_lockedKeys.contains(key)) {
        _lockedKeys.remove(key);
      } else {
        // 잠그는 순간의 상태(현재 제목/아티스트/가사)를 그대로 고정해서 보호한다.
        _lockedKeys.add(key);
        _titleOverrides[key] = _track.title;
        _artistOverrides[key] = _track.artist;
        _lyricsCache[key] = _track.lyrics;
        _manualLyricsKeys.add(key);
      }
    });
    _persistManualEdits();
  }

  void _openEditModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _SongEditSheet(
        track: _track,
        onSave: _saveManualEdit,
        onRefetch: _refetchMetadata,
        onSearchCandidates: LyricsService.searchCandidates,
        onSearchAlbumArt: LyricsService.searchAlbumArtCandidates,
        onPickAlbumArt: _saveAlbumArtOverride,
        isLocked: _isCurrentTrackLocked,
        onToggleLock: _toggleLock,
      ),
    );
  }

  /// 휴대폰 저장소에서 mp3 파일을 골라 재생목록에 추가하고 기기에 저장한다.
  Future<void> _addTracksFromDevice() async {
    if (kIsWeb) {
      showBinsTapeSnackBar(
        context,
        '휴대폰 앱에서만 기기 파일을 추가할 수 있어요.',
        icon: Icons.smartphone,
      );
      return;
    }

    if (deviceLibrarySupported) {
      final granted = await requestDeviceLibraryPermission();
      if (granted) {
        final picked = await Navigator.of(context).push<List<DeviceSong>>(
          MaterialPageRoute(
            builder: (context) => _DeviceLibraryPickerScreen(
              alreadyAdded: _devicePaths.toSet(),
            ),
          ),
        );
        if (picked != null && picked.isNotEmpty) await _addDeviceSongs(picked);
        return;
      }
      if (mounted) {
        showBinsTapeSnackBar(
          context,
          '음악 접근 권한이 없어서 파일 선택창으로 열게요.',
          icon: Icons.folder_open,
        );
      }
    }
    await _addTracksViaFilePicker();
  }

  Future<void> _addDeviceSongs(List<DeviceSong> songs) async {
    final added = songs
        .map((s) => s.path)
        .where((p) => !_devicePaths.contains(p))
        .toList();
    if (added.isEmpty) return;

    setState(() {
      _devicePaths = [..._devicePaths, ...added];
      for (final s in songs) {
        if (!added.contains(s.path)) continue;
        _titleOverrides[s.path] = s.title;
        _artistOverrides[s.path] = s.artist;
        _deviceSongIds[s.path] = s.id;
      }
      final active = _activePlaylist;
      if (active != null) {
        _playlists = {
          ..._playlists,
          active: [...(_playlists[active] ?? []), ...added],
        };
      }
      _currentIndex = _activeKeys.indexOf(added.first).clamp(0, _activeKeys.length);
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await PlaylistStore.save(_devicePaths);
    await _persistPlaylists();
    await _persistManualEdits();
    await _player.stop();
    await _player.play(buildAudioSource(_track));
    await _player.setVolume(_volume);
    _ensureMetadata(_track);
  }

  /// on_audio_query를 못 쓰거나 권한이 없을 때의 예전 방식(시스템 파일 선택창).
  Future<void> _addTracksViaFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    final newPaths =
        result?.files.map((f) => f.path).whereType<String>().toList() ?? [];
    // 이미 있는 곡은 다시 넣지 않는다.
    final added = newPaths.where((p) => !_devicePaths.contains(p)).toList();
    if (added.isEmpty) return;

    setState(() {
      _devicePaths = [..._devicePaths, ...added];
      // 특정 재생목록을 보는 중에 추가했다면 그 목록에도 함께 넣어준다.
      final active = _activePlaylist;
      if (active != null) {
        _playlists = {
          ..._playlists,
          active: [...(_playlists[active] ?? []), ...added],
        };
      }
      _currentIndex = _activeKeys.indexOf(added.first).clamp(0, _activeKeys.length);
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    await PlaylistStore.save(_devicePaths);
    await _persistPlaylists();
    await _player.stop();
    await _player.play(buildAudioSource(_track));
    await _player.setVolume(_volume);
    _ensureMetadata(_track);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _reelController.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드에 있다가 앱으로 돌아올 때도 새 버전이 있는지 확인한다.
    if (state == AppLifecycleState.resumed) {
      _checkForAppUpdate();
      _syncShuffleRepeatFromWidget();
    }
  }

  /// 앱이 꺼져있는 동안 홈 화면 위젯에서 반복/셔플을 바꿨을 수 있으니, 앱이 다시 열릴 때
  /// 그 값을 읽어와 실제 재생에 반영한다 (위젯은 Dart 없이도 직접 상태값만 바꿔둔다).
  Future<void> _syncShuffleRepeatFromWidget() async {
    if (kIsWeb) return;
    try {
      final shuffle = await HomeWidget.getWidgetData<bool>('widget_is_shuffle');
      final repeat = await HomeWidget.getWidgetData<String>('widget_repeat_mode');
      if (!mounted) return;
      setState(() {
        if (shuffle != null) _isShuffle = shuffle;
        if (repeat != null) {
          _repeatMode = switch (repeat) {
            'all' => RepeatMode.all,
            'one' => RepeatMode.one,
            _ => RepeatMode.off,
          };
        }
      });
    } catch (_) {
      // 위젯을 안 쓰는 환경이면 조용히 넘어간다.
    }
  }

  @override
  Widget build(BuildContext context) {
    // 실제 타겟은 폰(APK) 하나뿐이라 폭에 따른 데스크톱 사이드바 분기는 두지 않는다.
    // 웹은 어디까지나 기능 확인용이라, 항상 폰 비율로 가운데 정렬해서 보여준다.
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: _buildPlayerStack(),
        ),
      ),
    );
  }

  void _openPlaylistSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.75,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: StatefulBuilder(
              builder: (context, setSheetState) {
                return _PlaylistSidebar(
                  tracks: _tracks,
                  currentIndex: _currentIndex,
                  fullWidth: true,
                  playlistNames: _playlists.keys.toList(),
                  activePlaylist: _activePlaylist,
                  onSwitchPlaylist: (name) async {
                    await _switchPlaylist(name);
                    setSheetState(() {});
                  },
                  onCreatePlaylist: () async {
                    await _createPlaylist();
                    setSheetState(() {});
                  },
                  onDeletePlaylist: (name) async {
                    await _deletePlaylist(name);
                    setSheetState(() {});
                  },
                  onTrackLongPress: (index) async {
                    await _showTrackActions(index);
                    setSheetState(() {});
                  },
                  onDropOnPlaylist: (name, index) async {
                    await _dropTrackOnPlaylist(name, index);
                    setSheetState(() {});
                  },
                  onReorder: (oldIndex, newIndex) async {
                    await _reorderActive(oldIndex, newIndex);
                    setSheetState(() {});
                  },
                  onSelect: (index) {
                    Navigator.of(context).pop();
                    _selectTrack(index);
                  },
                  onAddTracks: () async {
                    await _addTracksFromDevice();
                    setSheetState(() {});
                  },
                  onCheckUpdate: () => _checkForAppUpdate(manual: true),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerStack() {
    final track = _track;
    return Stack(
      fit: StackFit.expand,
      children: [
        // ---- 배경: 앨범 자켓 블러 처리 ----
        _BlurredAlbumBackground(
          assetPath: track.albumArtAsset,
          isNetworkArt: track.isNetworkArt,
        ),

        // ---- 전경 콘텐츠 ----
        SafeArea(
          child: Column(
            children: [
              _TopBar(
                title: '지금 재생 중',
                onOpenPlaylist: _openPlaylistSheet,
              ),
              const SizedBox(height: 12),

              // 카세트 릴 + 라벨(현재 재생 곡 정보)
              _CassetteArt(
                reelController: _reelController,
                title: track.title,
                artist: track.artist,
              ),

              const SizedBox(height: 20),

              // 브랜드 워드마크 — 여기가 원래 곡 제목/가수 자리였음
              const _BrandWordmark(),

              const SizedBox(height: 16),

              // ---- 에이전트 2의 싱크 가사 뷰 결합 지점 ----
              Expanded(
                child: SyncLyricsView(
                  lyrics: track.lyrics,
                  currentPosition: _position +
                      Duration(
                        milliseconds:
                            (_currentSyncOffset * 1000).round(),
                      ),
                  onLyricTap: (lyricTime) => _seekTo(
                    lyricTime -
                        Duration(
                          milliseconds:
                              (_currentSyncOffset * 1000).round(),
                        ),
                  ),
                ),
              ),

              _SyncOffsetControl(
                  offsetSeconds: _currentSyncOffset,
                  onAdjust: _adjustSync,
                  isLocked: _isCurrentTrackLocked,
                  onOpenEdit: _openEditModal,
                ),
              const SizedBox(height: 6),

              _SeekBar(
                position: _position,
                duration: _duration,
                onSeek: _seekTo,
              ),
              _PlaybackControls(
                isPlaying: _isPlaying,
                onTogglePlay: _togglePlay,
                isShuffle: _isShuffle,
                onToggleShuffle: _toggleShuffle,
                repeatMode: _repeatMode,
                onCycleRepeat: _cycleRepeatMode,
                onPrevious: _playPrevious,
                onNext: _playNext,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),

        // 우측 하단에 고정된 볼륨 버튼 — 다른 콘텐츠 흐름과 무관하게 항상 같은 자리.
        Positioned(
          right: 8,
          bottom: 110,
          child: _VolumeControl(volume: _volume, onChanged: _setVolume),
        ),
      ],
    );
  }
}

/// 재생목록 패널 — 웹/데스크톱에서는 좌측 사이드바, 모바일에서는 하단 시트로 쓰인다.
/// 폰에 있는 모든 음악 파일을 제목·가수 순으로 보여주고 여러 곡을 골라 추가하는 화면.
/// 카카오톡 다운로드 폴더처럼 어디에 저장돼 있든, 폰이 "음악"으로 인식만 하면 나온다.
class _DeviceLibraryPickerScreen extends StatefulWidget {
  final Set<String> alreadyAdded;
  const _DeviceLibraryPickerScreen({required this.alreadyAdded});

  @override
  State<_DeviceLibraryPickerScreen> createState() =>
      _DeviceLibraryPickerScreenState();
}

class _DeviceLibraryPickerScreenState
    extends State<_DeviceLibraryPickerScreen> {
  List<DeviceSong>? _songs;
  String _query = '';
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final songs = await queryDeviceSongs();
    // 이미 재생목록(전체 곡)에 있는 곡은 목록에서 아예 빼서, 다시 골라도
    // 중복으로 추가될 일이 없게 한다.
    final filtered =
        songs.where((s) => !widget.alreadyAdded.contains(s.path)).toList();
    if (mounted) setState(() => _songs = filtered);
  }

  List<DeviceSong> _filtered(List<DeviceSong> songs) {
    if (_query.trim().isEmpty) return songs;
    final q = _query.trim().toLowerCase();
    return songs
        .where((s) =>
            s.title.toLowerCase().contains(q) ||
            s.artist.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final songs = _songs;
    return Scaffold(
      backgroundColor: BinsTapeColors.deepNavy,
      appBar: AppBar(
        backgroundColor: BinsTapeColors.navyCard,
        foregroundColor: BinsTapeColors.tapeCream,
        title: const Text('폰에서 곡 고르기'),
      ),
      body: songs == null
          ? const Center(
              child: CircularProgressIndicator(color: BinsTapeColors.tapeAmber),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    style: const TextStyle(color: BinsTapeColors.tapeCream),
                    decoration: InputDecoration(
                      hintText: '제목이나 가수로 찾기',
                      hintStyle: const TextStyle(color: BinsTapeColors.dimText),
                      prefixIcon: const Icon(Icons.search,
                          color: BinsTapeColors.dimText),
                      filled: true,
                      fillColor: BinsTapeColors.navyCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                if (songs.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '폰에서 음악 파일을 찾지 못했어요.\n카카오톡 등으로 받은 곡이 있다면 한 번 다운로드 폴더를 열어봐 주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: BinsTapeColors.dimText),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Builder(builder: (context) {
                      final list = _filtered(songs);
                      return ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final s = list[index];
                          final isSelected = _selected.contains(s.path);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (_) => setState(() {
                              if (isSelected) {
                                _selected.remove(s.path);
                              } else {
                                _selected.add(s.path);
                              }
                            }),
                            activeColor: BinsTapeColors.tapeAmber,
                            checkColor: BinsTapeColors.deepNavy,
                            title: Text(
                              s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: BinsTapeColors.tapeCream),
                            ),
                            subtitle: Text(
                              s.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: BinsTapeColors.dimText),
                            ),
                          );
                        },
                      );
                    }),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: BinsTapeColors.tapeAmber,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _selected.isEmpty
                  ? null
                  : () {
                      final picked = (songs ?? [])
                          .where((s) => _selected.contains(s.path))
                          .toList();
                      Navigator.of(context).pop(picked);
                    },
              child: Text(
                _selected.isEmpty ? '곡을 골라주세요' : '${_selected.length}곡 추가',
                style: const TextStyle(
                  color: BinsTapeColors.deepNavy,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistSidebar extends StatelessWidget {
  final List<Track> tracks;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAddTracks;
  final VoidCallback onCheckUpdate;
  final bool fullWidth;
  final List<String> playlistNames;
  final String? activePlaylist;
  final ValueChanged<String?> onSwitchPlaylist;
  final VoidCallback onCreatePlaylist;
  final ValueChanged<String> onDeletePlaylist;
  final ValueChanged<int> onTrackLongPress;
  final void Function(String playlistName, int trackIndex) onDropOnPlaylist;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _PlaylistSidebar({
    required this.tracks,
    required this.currentIndex,
    required this.onSelect,
    required this.onAddTracks,
    required this.onCheckUpdate,
    required this.playlistNames,
    required this.activePlaylist,
    required this.onSwitchPlaylist,
    required this.onCreatePlaylist,
    required this.onDeletePlaylist,
    required this.onTrackLongPress,
    required this.onDropOnPlaylist,
    required this.onReorder,
    this.fullWidth = false,
  });

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    // 곡을 끌어다 놓을 수 있는 칩이면 놓았을 때 호출된다.
    ValueChanged<int>? onDrop,
  }) {
    Widget buildChip(bool hovering) => GestureDetector(
          onLongPress: onLongPress,
          child: ChoiceChip(
            label: Text(label),
            selected: selected || hovering,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            backgroundColor: BinsTapeColors.navyCard,
            selectedColor: hovering
                ? BinsTapeColors.tapeAmber.withValues(alpha: 0.6)
                : BinsTapeColors.tapeAmber,
            labelStyle: TextStyle(
              color: (selected || hovering)
                  ? Colors.white
                  : BinsTapeColors.tapeCream,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            side: BorderSide(
              color: BinsTapeColors.tapeAmber
                  .withValues(alpha: hovering ? 1 : 0.4),
              width: hovering ? 2 : 1,
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: onDrop == null
          ? buildChip(false)
          : DragTarget<int>(
              onAcceptWithDetails: (details) => onDrop(details.data),
              builder: (context, candidates, _) =>
                  buildChip(candidates.isNotEmpty),
            ),
    );
  }

  /// 곡 한 줄. 길게 눌러서 위쪽 재생목록 칩으로 끌어다 놓으면 추가/이동된다.
  Widget _buildTile(int index, {Key? key, Widget? trailing}) {
    final t = tracks[index];
    final isActive = index == currentIndex;
    final tile = ListTile(
      onTap: () => onSelect(index),
      selected: isActive,
      selectedTileColor: BinsTapeColors.tapeAmber.withValues(alpha: 0.12),
      leading: Icon(
        isActive ? Icons.graphic_eq : Icons.music_note,
        color: isActive ? BinsTapeColors.tapeAmber : BinsTapeColors.dimText,
      ),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isActive ? BinsTapeColors.tapeAmber : BinsTapeColors.tapeCream,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        t.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: BinsTapeColors.dimText),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => onTrackLongPress(index),
            icon: const Icon(Icons.more_vert,
                color: BinsTapeColors.dimText, size: 20),
            tooltip: '메뉴 (추가/이동/삭제)',
          ),
          if (trailing != null) trailing,
        ],
      ),
    );

    return KeyedSubtree(
      key: key,
      child: LongPressDraggable<int>(
        data: index,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: BinsTapeColors.tapeAmber,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              t.title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: tile),
        child: tile,
      ),
    );
  }

  Widget _buildTrackList() {
    // 내가 만든 목록에서는 오른쪽 손잡이로 순서를 바꿀 수 있다.
    if (activePlaylist != null) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        buildDefaultDragHandles: false,
        itemCount: tracks.length,
        onReorder: onReorder,
        itemBuilder: (context, index) => _buildTile(
          index,
          key: ValueKey(tracks[index].audioAsset),
          trailing: ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle,
                  color: BinsTapeColors.dimText, size: 20),
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: tracks.length,
      itemBuilder: (context, index) => _buildTile(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : 300,
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: fullWidth
            ? null
            : const Border(right: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: _BrandWordmark(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Row(
                children: [
                  const Icon(Icons.queue_music,
                      size: 16, color: BinsTapeColors.tapeAmber),
                  const SizedBox(width: 6),
                  const Text(
                    '재생목록',
                    style: TextStyle(
                      color: BinsTapeColors.tapeCream,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onCheckUpdate,
                    icon: const Icon(Icons.system_update_alt,
                        color: BinsTapeColors.dimText, size: 20),
                    tooltip: '업데이트 확인',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: onAddTracks,
                    icon: const Icon(Icons.add_circle_outline,
                        color: BinsTapeColors.tapeAmber, size: 20),
                    tooltip: '휴대폰에서 곡 추가',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            // 재생목록 선택 칩: 전체 / 내가 만든 목록들 / + 새 목록 (목록 칩을 길게 누르면 삭제)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _chip(
                    label: '전체 곡',
                    selected: activePlaylist == null,
                    onTap: () => onSwitchPlaylist(null),
                  ),
                  for (final name in playlistNames)
                    _chip(
                      label: name,
                      selected: activePlaylist == name,
                      onTap: () => onSwitchPlaylist(name),
                      onLongPress: () => onDeletePlaylist(name),
                      onDrop: name == activePlaylist
                          ? null
                          : (trackIndex) => onDropOnPlaylist(name, trackIndex),
                    ),
                  ActionChip(
                    label: const Text('+ 새 목록'),
                    onPressed: onCreatePlaylist,
                    backgroundColor: BinsTapeColors.deepNavy,
                    labelStyle: const TextStyle(
                      color: BinsTapeColors.tapeAmber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    side: BorderSide(
                      color: BinsTapeColors.tapeAmber.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(color: BinsTapeColors.magneticBrown, height: 1),
            Expanded(
              child: tracks.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '이 목록은 비어 있어요.\n"전체 곡"에서 곡을 길게 눌러 이 칩으로 끌어다 놓거나, 곡의 ⋮ 메뉴로 추가해보세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: BinsTapeColors.dimText),
                        ),
                      ),
                    )
                  : _buildTrackList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onOpenPlaylist;
  const _TopBar({
    required this.title,
    required this.onOpenPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 뒤로 갈 화면이 없는 단일 화면 앱이라, 우측 버튼과 균형만 맞추는 빈 자리.
          const SizedBox(width: 48),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: BinsTapeColors.tapeAmber,
                  boxShadow: [
                    BoxShadow(
                      color: BinsTapeColors.tapeAmber.withValues(alpha: 0.7),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: BinsTapeColors.tapeCream,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: onOpenPlaylist,
            icon: const Icon(Icons.queue_music,
                color: BinsTapeColors.tapeCream),
            tooltip: '재생목록',
          ),
        ],
      ),
    );
  }
}

/// 배경: 카본 블랙 그라데이션 + 은은한 REC 레드 비네트.
/// (실물 앨범 커버가 없는 데모 트랙에서는 사진 대신 브랜드 톤 그라데이션을 사용)
class _BlurredAlbumBackground extends StatelessWidget {
  final String assetPath;
  final bool isNetworkArt;
  const _BlurredAlbumBackground({
    required this.assetPath,
    this.isNetworkArt = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.4),
              radius: 1.2,
              colors: [
                BinsTapeColors.navyCard,
                BinsTapeColors.deepNavy,
              ],
            ),
          ),
        ),
        // 실제 앨범아트(파일에 박혀있던 것 또는 인터넷에서 찾아온 것)가 있으면 흐리게 깔아준다.
        if (isNetworkArt)
          Image(
            image: artImageProvider(assetPath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        if (isNetworkArt)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
            child: Container(
              color: BinsTapeColors.deepNavy.withValues(alpha: 0.65),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.2),
              radius: 0.9,
              colors: [
                BinsTapeColors.tapeAmber.withValues(alpha: 0.14),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 곡 정보(제목/아티스트)와 LRC 가사를 직접 편집하는 바텀시트.
/// 자동 검색이 실패했거나 틀렸을 때, 오타를 고쳐 재검색하거나
/// 가사를 통째로 붙여넣어 저장할 수 있다.
class _SongEditSheet extends StatefulWidget {
  final Track track;
  final void Function({
    required String title,
    required String artist,
    required String lrcText,
  }) onSave;
  final Future<List<LyricLine>> Function(
      {required String title, required String artist}) onRefetch;
  final Future<List<Map<String, dynamic>>> Function(
      {required String title, required String artist}) onSearchCandidates;
  final Future<List<Map<String, dynamic>>> Function(
      {required String title, required String artist}) onSearchAlbumArt;
  final void Function(String url) onPickAlbumArt;
  final bool isLocked;
  final VoidCallback onToggleLock;

  const _SongEditSheet({
    required this.track,
    required this.onSave,
    required this.onRefetch,
    required this.onSearchCandidates,
    required this.onSearchAlbumArt,
    required this.onPickAlbumArt,
    required this.isLocked,
    required this.onToggleLock,
  });

  @override
  State<_SongEditSheet> createState() => _SongEditSheetState();
}

class _SongEditSheetState extends State<_SongEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _lrcController;
  bool _isRefetching = false;

  // 바텀시트는 부모(MusicPlayerScreen)와 별도 오버레이라서, 부모 쪽 setState만으로는
  // 여기가 다시 그려지지 않는다. 그래서 잠금 상태를 로컬로 복제해두고 즉시 반영한다.
  late bool _isLocked = widget.isLocked;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.track.title);
    _artistController = TextEditingController(text: widget.track.artist);
    _lrcController =
        TextEditingController(text: lyricsToLrc(widget.track.lyrics));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _lrcController.dispose();
    super.dispose();
  }

  Future<({OcrRegion region, Duration step})?> _askOcrOptions(
      BuildContext context) {
    var region = ocrRegions[1]; // 자막은 보통 화면 아래쪽에 있다.
    var stepMs = 500;
    return showDialog<({OcrRegion region, Duration step})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: BinsTapeColors.navyCard,
          title: const Text('영상에서 가사 읽기',
              style: TextStyle(color: BinsTapeColors.tapeCream)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '가사가 화면에 자막처럼 나오는 영상(가사 영상, 노래방 영상 등)이어야 해요. '
                  '영상은 이 브라우저 안에서만 처리되고 밖으로 올라가지 않아요. '
                  '읽은 결과는 아래 칸에 채워지니 확인하고 고친 뒤 저장하세요.',
                  style: TextStyle(color: BinsTapeColors.dimText, fontSize: 12),
                ),
                const SizedBox(height: 14),
                const Text('가사가 나오는 위치',
                    style: TextStyle(color: BinsTapeColors.tapeCream)),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final r in ocrRegions)
                      ChoiceChip(
                        label: Text(r.label),
                        selected: region == r,
                        showCheckmark: false,
                        onSelected: (_) => setDialogState(() => region = r),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('읽는 간격',
                    style: TextStyle(color: BinsTapeColors.tapeCream)),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('0.5초 (정확, 느림)'),
                      selected: stepMs == 500,
                      showCheckmark: false,
                      onSelected: (_) => setDialogState(() => stepMs = 500),
                    ),
                    ChoiceChip(
                      label: const Text('1초 (빠름)'),
                      selected: stepMs == 1000,
                      showCheckmark: false,
                      onSelected: (_) => setDialogState(() => stepMs = 1000),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소',
                  style: TextStyle(color: BinsTapeColors.dimText)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                  context, (region: region, step: Duration(milliseconds: stepMs))),
              child: const Text('영상 고르기',
                  style: TextStyle(color: BinsTapeColors.tapeAmber)),
            ),
          ],
        ),
      ),
    );
  }

  /// 영상을 골라 프레임마다 OCR로 글자를 읽고, 가사(LRC)로 정리해서 아래 칸에 채운다.
  Future<void> _extractLyricsFromVideo(BuildContext context) async {
    if (!videoOcrSupported) {
      showBinsTapeSnackBar(context, '영상 OCR은 PC 웹 버전에서만 쓸 수 있어요.',
          icon: Icons.computer);
      return;
    }

    final options = await _askOcrOptions(context);
    if (options == null || !mounted) return;

    final video = await pickVideoForOcr();
    if (video == null || !mounted) return;

    final progress = ValueNotifier<double>(0);
    final preview = ValueNotifier<String>('');
    var cancelled = false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: BinsTapeColors.navyCard,
        title: const Text('영상에서 가사 읽는 중...',
            style: TextStyle(color: BinsTapeColors.tapeCream)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                children: [
                  LinearProgressIndicator(
                    value: value,
                    color: BinsTapeColors.tapeAmber,
                    backgroundColor: BinsTapeColors.magneticBrown,
                  ),
                  const SizedBox(height: 6),
                  Text('${(value * 100).round()}%',
                      style: const TextStyle(
                          color: BinsTapeColors.dimText, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: preview,
              builder: (context, text, _) => Text(
                text.isEmpty ? '...' : text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: BinsTapeColors.tapeCream),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => cancelled = true,
            child: const Text('그만두기',
                style: TextStyle(color: BinsTapeColors.tapeAmber)),
          ),
        ],
      ),
    );

    var frames = <FrameText>[];
    String? error;
    try {
      frames = await extractFrameTexts(
        video: video,
        region: options.region,
        step: options.step,
        onProgress: (value, text) {
          progress.value = value;
          preview.value = text;
        },
        isCancelled: () => cancelled,
      );
    } catch (e) {
      error = '$e';
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // 진행 창 닫기

    if (error != null) {
      showBinsTapeSnackBar(context, '읽는 중 문제가 생겼어요: $error',
          icon: Icons.error_outline);
      return;
    }
    if (cancelled) {
      showBinsTapeSnackBar(context, '중단했어요.', icon: Icons.stop_circle_outlined);
      return;
    }

    final lines = buildLyricsFromFrames(frames);
    if (lines.isEmpty) {
      showBinsTapeSnackBar(
        context,
        '가사로 보이는 글자를 못 찾았어요. 가사 위치를 바꿔서 다시 해보세요.',
        icon: Icons.search_off,
      );
      return;
    }
    setState(() {
      _lrcController.text =
          lyricsToLrc([for (final l in lines) LyricLine(l.time, l.text)]);
    });
    showBinsTapeSnackBar(
      context,
      '${lines.length}줄을 읽었어요. 확인하고 고친 뒤 저장하기를 눌러주세요.',
    );
  }

  Future<void> _showCandidatePicker(BuildContext context) async {
    showBinsTapeSnackBar(context, '후보를 찾는 중...', icon: Icons.search);
    final candidates = await widget.onSearchCandidates(
      title: _titleController.text.trim(),
      artist: searchableArtist(_artistController.text.trim()),
    );
    if (!mounted) return;

    if (candidates.isEmpty) {
      showBinsTapeSnackBar(context, '검색된 후보가 없어요.', icon: Icons.search_off);
      return;
    }

    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BinsTapeColors.navyCard,
        title: const Text('가사 후보 선택',
            style: TextStyle(color: BinsTapeColors.tapeCream)),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView.builder(
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final item = candidates[index];
              final hasSynced =
                  (item['syncedLyrics'] as String?)?.isNotEmpty == true;
              final durationSec = (item['duration'] as num?)?.toInt() ?? 0;
              final durationLabel =
                  '${durationSec ~/ 60}:${(durationSec % 60).toString().padLeft(2, '0')}';
              return ListTile(
                enabled: hasSynced,
                title: Text(
                  '${item['trackName'] ?? '제목 없음'} · $durationLabel',
                  style: TextStyle(
                    color: hasSynced
                        ? BinsTapeColors.tapeCream
                        : BinsTapeColors.dimText,
                  ),
                ),
                subtitle: Text(
                  '${item['artistName'] ?? ''} ${hasSynced ? '(싱크 가사 있음)' : '(싱크 가사 없음)'}',
                  style: const TextStyle(
                      color: BinsTapeColors.dimText, fontSize: 12),
                ),
                onTap: hasSynced ? () => Navigator.pop(context, item) : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: BinsTapeColors.dimText)),
          ),
        ],
      ),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _lrcController.text = lyricsToLrc(parseLrc(picked['syncedLyrics'] as String));
    });
    showBinsTapeSnackBar(context, '선택한 가사를 반영했어요. 저장하기를 눌러 확정하세요.');
  }

  Future<void> _showAlbumArtPicker(BuildContext context) async {
    showBinsTapeSnackBar(context, '앨범아트를 찾는 중...', icon: Icons.image_search);
    final candidates = await widget.onSearchAlbumArt(
      title: _titleController.text.trim(),
      artist: searchableArtist(_artistController.text.trim()),
    );
    if (!mounted) return;

    if (candidates.isEmpty) {
      showBinsTapeSnackBar(context, '검색된 이미지가 없어요.', icon: Icons.search_off);
      return;
    }

    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: BinsTapeColors.navyCard,
        title: const Text('앨범아트 선택',
            style: TextStyle(color: BinsTapeColors.tapeCream)),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final item = candidates[index];
              final url = item['artworkUrl'] as String;
              return InkWell(
                onTap: () => Navigator.pop(context, item),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: BinsTapeColors.magneticBrown,
                      child: const Icon(Icons.broken_image,
                          color: BinsTapeColors.dimText),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소',
                style: TextStyle(color: BinsTapeColors.dimText)),
          ),
        ],
      ),
    );

    if (picked == null || !mounted) return;
    widget.onPickAlbumArt(picked['artworkUrl'] as String);
    showBinsTapeSnackBar(context, '앨범아트를 바꿨어요.', icon: Icons.image);
  }

  @override
  Widget build(BuildContext context) {
    // 이 시트는 별도 모달 라우트라서, 바깥 화면의 ScaffoldMessenger로 스낵바를 띄우면
    // 시트 뒤쪽 오버레이에 가려져 안 보인다. 시트 전용 ScaffoldMessenger로 감싸서
    // 이 안에서 뜨는 스낵바가 시트 위에 바로 보이게 한다.
    // ScaffoldMessenger는 스낵바를 직접 그리지 못하고, 안에 있는 Scaffold가 그려준다.
    // 그래서 투명한 Scaffold를 함께 둔다.
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Builder(builder: (context) => _buildContent(context)),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: const BoxDecoration(
            color: BinsTapeColors.navyCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '곡 정보 · 가사 수동 편집',
                      style: TextStyle(
                        color: BinsTapeColors.tapeCream,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      widget.onToggleLock();
                      setState(() => _isLocked = !_isLocked);
                    },
                    tooltip: _isLocked
                        ? '잠금 해제 (자동/재검색으로부터 보호 중)'
                        : '잠그기 (실수로 덮어쓰는 것 방지)',
                    icon: Icon(
                      _isLocked ? Icons.lock : Icons.lock_open_outlined,
                      color: _isLocked
                          ? BinsTapeColors.tapeAmber
                          : BinsTapeColors.dimText,
                    ),
                  ),
                ],
              ),
              if (_isLocked)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    '🔒 잠긴 곡이에요. 자동 검색이 건드리지 않아요. 재검색하려면 먼저 잠금을 풀어주세요.',
                    style: TextStyle(
                        color: BinsTapeColors.tapeAmber, fontSize: 11),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _artistController,
                      style: const TextStyle(color: BinsTapeColors.tapeCream),
                      decoration: _fieldDecoration('아티스트'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      style: const TextStyle(color: BinsTapeColors.tapeCream),
                      decoration: _fieldDecoration('곡 제목'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _lrcController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    color: BinsTapeColors.tapeCream,
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                  decoration: _fieldDecoration(
                    'LRC 가사 ([00:12.34] 가사 형식으로 붙여넣기)',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  TextButton.icon(
                    onPressed: _isLocked || _isRefetching
                        ? null
                        : () => _showCandidatePicker(context),
                    icon: const Icon(Icons.list_alt,
                        size: 16, color: BinsTapeColors.dimText),
                    label: const Text(
                      '가사 후보 선택',
                      style: TextStyle(color: BinsTapeColors.dimText),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isLocked || _isRefetching
                        ? null
                        : () => _extractLyricsFromVideo(context),
                    icon: const Icon(Icons.movie_filter_outlined,
                        size: 16, color: BinsTapeColors.dimText),
                    label: const Text(
                      '영상에서 가사 추출',
                      style: TextStyle(color: BinsTapeColors.dimText),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isLocked || _isRefetching
                        ? null
                        : () => _showAlbumArtPicker(context),
                    icon: const Icon(Icons.image_search,
                        size: 16, color: BinsTapeColors.dimText),
                    label: const Text(
                      '앨범아트 검색',
                      style: TextStyle(color: BinsTapeColors.dimText),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                children: [
                  TextButton(
                    onPressed: _isRefetching
                        ? null
                        : () async {
                            if (_isLocked) {
                              showBinsTapeSnackBar(
                                context,
                                '잠긴 곡입니다. 재검색하려면 자물쇠를 먼저 풀어주세요.',
                                icon: Icons.lock,
                              );
                              return;
                            }

                            setState(() => _isRefetching = true);
                            showBinsTapeSnackBar(
                              context,
                              '인터넷에서 정보를 찾는 중...',
                              icon: Icons.search,
                            );

                            final lyrics = await widget.onRefetch(
                              title: _titleController.text.trim(),
                              artist: _artistController.text.trim(),
                            );

                            if (!mounted) return;
                            setState(() {
                              _isRefetching = false;
                              if (lyrics.isNotEmpty) {
                                _lrcController.text = lyricsToLrc(lyrics);
                              }
                            });
                            showBinsTapeSnackBar(
                              context,
                              lyrics.isNotEmpty
                                  ? '검색 완료! 가사가 갱신됐어요.'
                                  : '가사를 찾지 못했어요. 앨범아트만 갱신됐을 수 있어요.',
                              icon: lyrics.isNotEmpty
                                  ? Icons.auto_awesome
                                  : Icons.search_off,
                            );
                            // 결과를 바로 확인할 수 있도록 창은 자동으로 닫지 않는다.
                          },
                    child: Text(
                      _isRefetching ? '검색 중...' : '인터넷에서 다시 검색',
                      style: const TextStyle(
                        color: BinsTapeColors.tapeAmber,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BinsTapeColors.tapeAmber,
                    ),
                    onPressed: () {
                      widget.onSave(
                        title: _titleController.text.trim(),
                        artist: _artistController.text.trim(),
                        lrcText: _lrcController.text,
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('저장하기',
                        style: TextStyle(color: BinsTapeColors.deepNavy)),
                  ),
                ],
              ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: BinsTapeColors.dimText),
      alignLabelWithHint: true,
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: BinsTapeColors.magneticBrown),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: BinsTapeColors.tapeAmber),
      ),
    );
  }
}

/// 브랜드 워드마크 — REC 글로우 도트 + 로고 배지. 프로필 로고 컨셉의 축소판.
class _BrandWordmark extends StatelessWidget {
  const _BrandWordmark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF17181A),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: BinsTapeColors.tapeAmber.withValues(alpha: 0.8),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: BinsTapeColors.tapeAmber.withValues(alpha: 0.25),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BinsTapeColors.tapeAmber,
              boxShadow: [
                BoxShadow(
                  color: BinsTapeColors.tapeAmber.withValues(alpha: 0.8),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: "Bin's",
                  style: TextStyle(
                    color: BinsTapeColors.tapeCream,
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: '  '),
                TextSpan(
                  text: 'TAPE',
                  style: TextStyle(
                    color: BinsTapeColors.tapeCream,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 실제 카세트 테이프 형태 — 'A'면 라벨, 감긴 테이프 릴, 나사 구멍까지.
class _CassetteArt extends StatelessWidget {
  final AnimationController reelController;
  final String title;
  final String artist;

  const _CassetteArt({
    required this.reelController,
    required this.title,
    required this.artist,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 190,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF17181A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BinsTapeColors.tapeAmber, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          // ---- 상단: A면 배지 + 브랜드 배너 ----
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BinsTapeColors.tapeCream,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'A',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 26,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: BinsTapeColors.tapeCream,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: const TextStyle(
                            color: Color(0xFF1A1A1A),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0.6,
                          ),
                        ),
                        TextSpan(
                          text: '  · $artist',
                          style: const TextStyle(
                            color: Color(0xFF5A5A5A),
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- 중앙: 테이프 창(윈도우) 안의 회전 릴 ----
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF0B0B0C),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  RotationTransition(
                    turns: reelController,
                    child: const _ReelHub(),
                  ),
                  RotationTransition(
                    turns: reelController,
                    child: const _ReelHub(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ---- 하단: 나사 구멍 4개 ----
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              4,
              (_) => Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF3A3A3D),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카세트 릴 하나 — 감긴 테이프 + 회전하는 허브.
class _ReelHub extends StatelessWidget {
  const _ReelHub();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: CustomPaint(painter: _ReelPainter()),
    );
  }
}

class _ReelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    // 감긴 테이프 (바깥쪽 갈색 스풀)
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF4A3527),
    );
    // 테이프 결 표현 (동심원 레이어)
    final layerPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (double r = radius * 0.55; r < radius; r += radius * 0.12) {
      canvas.drawCircle(center, r, layerPaint);
    }

    // 릴 허브 (검정)
    canvas.drawCircle(
      center,
      radius * 0.5,
      Paint()..color = const Color(0xFF161616),
    );

    // 스포크
    final spokePaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = radius * 0.16;
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * math.pi;
      final p1 = Offset(
        center.dx + (radius * 0.18) * math.cos(angle),
        center.dy + (radius * 0.18) * math.sin(angle),
      );
      final p2 = Offset(
        center.dx + radius * 0.48 * math.cos(angle),
        center.dy + radius * 0.48 * math.sin(angle),
      );
      canvas.drawLine(p1, p2, spokePaint);
    }

    // 중심 허브: REC 레드
    canvas.drawCircle(
      center,
      radius * 0.2,
      Paint()..color = BinsTapeColors.tapeAmber,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 곡별로 저장되는 가사 싱크 보정 컨트롤. -로 당기면 가사가 더 빨리,
/// +로 밀면 가사가 더 늦게 뜨도록 조절한다.
/// 짧게 탭하면 0.5초씩, 길게 누르고 있으면 0.1초씩 정밀 조정된다.
class _SyncOffsetControl extends StatelessWidget {
  final double offsetSeconds;
  final ValueChanged<double> onAdjust;
  final bool isLocked;
  final VoidCallback onOpenEdit;

  const _SyncOffsetControl({
    required this.offsetSeconds,
    required this.onAdjust,
    required this.isLocked,
    required this.onOpenEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // "가사 싱크" 라벨을 누르면 곡 정보·가사 수동 편집창이 열린다.
          GestureDetector(
            onTap: onOpenEdit,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLocked ? Icons.lock : Icons.lyrics_outlined,
                  size: 14,
                  color: isLocked
                      ? BinsTapeColors.tapeAmber
                      : BinsTapeColors.dimText,
                ),
                const SizedBox(width: 6),
                const Text(
                  '가사 싱크',
                  style:
                      TextStyle(color: BinsTapeColors.dimText, fontSize: 12),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.edit,
                    size: 11, color: BinsTapeColors.dimText),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _SyncStepButton(
            icon: Icons.remove,
            tapDelta: -0.1,
            holdDelta: -0.5,
            onAdjust: onAdjust,
            tooltip: '가사를 느리게 (길게 누르면 0.5초씩)',
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${offsetSeconds >= 0 ? '+' : ''}${offsetSeconds.toStringAsFixed(1)}s',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: BinsTapeColors.tapeAmber,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _SyncStepButton(
            icon: Icons.add,
            tapDelta: 0.1,
            holdDelta: 0.5,
            onAdjust: onAdjust,
            tooltip: '가사를 빠르게 (길게 누르면 0.5초씩)',
          ),
        ],
      ),
    );
  }
}

/// 탭하면 tapDelta만큼, 누르고 있으면 holdDelta만큼 반복 적용되는 버튼.
class _SyncStepButton extends StatefulWidget {
  final IconData icon;
  final double tapDelta;
  final double holdDelta;
  final ValueChanged<double> onAdjust;
  final String tooltip;

  const _SyncStepButton({
    required this.icon,
    required this.tapDelta,
    required this.holdDelta,
    required this.onAdjust,
    required this.tooltip,
  });

  @override
  State<_SyncStepButton> createState() => _SyncStepButtonState();
}

class _SyncStepButtonState extends State<_SyncStepButton> {
  Timer? _repeatTimer;
  bool _isHolding = false;

  void _startHolding() {
    _isHolding = true;
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      widget.onAdjust(widget.holdDelta);
    });
  }

  void _stopHolding() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    if (!_isHolding) return;
    _isHolding = false;
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTap: () => widget.onAdjust(widget.tapDelta),
        onLongPressStart: (_) => _startHolding(),
        onLongPressEnd: (_) => _stopHolding(),
        onLongPressCancel: _stopHolding,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.4),
          ),
          child: Icon(widget.icon, size: 15, color: BinsTapeColors.tapeCream),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 🎚️ SeekBar & Playback Controls (에이전트 1)
// ---------------------------------------------------------------------------
class _SeekBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  const _SeekBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds.toDouble();
    final curMs = position.inMilliseconds
        .toDouble()
        .clamp(0, maxMs <= 0 ? 1 : maxMs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: BinsTapeColors.tapeAmber,
              inactiveTrackColor: BinsTapeColors.dimText.withValues(alpha: 0.3),
              thumbColor: BinsTapeColors.tapeAmber,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              min: 0,
              max: maxMs <= 0 ? 1 : maxMs,
              value: curMs.toDouble(),
              onChanged: maxMs <= 0
                  ? null
                  : (v) => onSeek(Duration(milliseconds: v.round())),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(position),
                  style: const TextStyle(
                      color: BinsTapeColors.dimText, fontSize: 12)),
              Text(_fmt(duration),
                  style: const TextStyle(
                      color: BinsTapeColors.dimText, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 볼륨 조절 슬라이더.
class _VolumeControl extends StatefulWidget {
  final double volume;
  final ValueChanged<double> onChanged;

  const _VolumeControl({required this.volume, required this.onChanged});

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _overlayEntry;

  void _togglePopup() {
    if (_overlayEntry != null) {
      _closePopup();
    } else {
      _openPopup();
    }
  }

  void _openPopup() {
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closePopup,
        child: Stack(
          children: [
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: const Offset(0, -8),
              child: GestureDetector(
                onTap: () {}, // 팝업 자체를 눌렀을 때는 안 닫히게.
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: BinsTapeColors.tapeAmber.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.volume_up,
                            color: BinsTapeColors.dimText, size: 16),
                        SizedBox(
                          width: 32,
                          height: 110,
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 2,
                                activeTrackColor: BinsTapeColors.tapeAmber,
                                inactiveTrackColor: BinsTapeColors.dimText
                                    .withValues(alpha: 0.3),
                                thumbColor: BinsTapeColors.tapeAmber,
                                thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: StatefulBuilder(
                                builder: (context, setPopupState) => Slider(
                                  value: widget.volume,
                                  min: 0.0,
                                  max: 1.0,
                                  onChanged: (v) {
                                    widget.onChanged(v);
                                    setPopupState(() {});
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Icon(Icons.volume_down,
                            color: BinsTapeColors.dimText, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _closePopup() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: GestureDetector(
        onTap: _togglePopup,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black87,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(
            widget.volume == 0 ? Icons.volume_off : Icons.volume_up,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _PlaybackControls extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onTogglePlay;
  final bool isShuffle;
  final VoidCallback onToggleShuffle;
  final RepeatMode repeatMode;
  final VoidCallback onCycleRepeat;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _PlaybackControls({
    required this.isPlaying,
    required this.onTogglePlay,
    required this.isShuffle,
    required this.onToggleShuffle,
    required this.repeatMode,
    required this.onCycleRepeat,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          onPressed: onToggleShuffle,
          tooltip: '셔플',
          icon: Icon(
            Icons.shuffle,
            color: isShuffle
                ? BinsTapeColors.tapeAmber
                : BinsTapeColors.dimText,
            size: 22,
          ),
        ),
        IconButton(
          onPressed: onPrevious,
          tooltip: '이전 곡',
          icon: const Icon(Icons.skip_previous,
              color: BinsTapeColors.tapeCream, size: 34),
        ),
        GestureDetector(
          onTap: onTogglePlay,
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: BinsTapeColors.tapeAmber,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: BinsTapeColors.deepNavy,
              size: 34,
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          tooltip: '다음 곡',
          icon: const Icon(Icons.skip_next,
              color: BinsTapeColors.tapeCream, size: 34),
        ),
        IconButton(
          onPressed: onCycleRepeat,
          tooltip: switch (repeatMode) {
            RepeatMode.off => '반복 꺼짐',
            RepeatMode.all => '전체 반복',
            RepeatMode.one => '한 곡 반복',
          },
          icon: Icon(
            repeatMode == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
            color: repeatMode == RepeatMode.off
                ? BinsTapeColors.dimText
                : BinsTapeColors.tapeAmber,
            size: 22,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 🎤 SyncLyricsView (에이전트 2: 싱크 가사 담당)
// ---------------------------------------------------------------------------
class SyncLyricsView extends StatefulWidget {
  final List<LyricLine> lyrics;
  final Duration currentPosition;
  final ValueChanged<Duration>? onLyricTap;

  const SyncLyricsView({
    super.key,
    required this.lyrics,
    required this.currentPosition,
    this.onLyricTap,
  });

  @override
  State<SyncLyricsView> createState() => _SyncLyricsViewState();
}

class _SyncLyricsViewState extends State<SyncLyricsView> {
  final ScrollController _scrollController = ScrollController();
  int _activeIndex = -1;

  static const double _lineHeight = 46;

  @override
  void didUpdateWidget(covariant SyncLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIndex = _indexForPosition(widget.currentPosition);
    if (newIndex != _activeIndex) {
      _activeIndex = newIndex;
      _scrollToActive();
    }
  }

  int _indexForPosition(Duration position) {
    int index = -1;
    for (int i = 0; i < widget.lyrics.length; i++) {
      if (widget.lyrics[i].time <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _scrollToActive() {
    if (!_scrollController.hasClients || _activeIndex < 0) return;
    final target = _activeIndex * _lineHeight;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return const Center(
        child: Text(
          '가사가 없어요.\n녹음할 준비가 될 때까지 조용히 기다릴게요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: BinsTapeColors.dimText),
        ),
      );
    }

    return ShaderMask(
      // 위/아래 페이드 아웃으로 중앙 포커스를 강조.
      shaderCallback: (rect) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: [0.0, 0.15, 0.85, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          vertical: (MediaQuery.of(context).size.height * 0.15),
          horizontal: 24,
        ),
        itemCount: widget.lyrics.length,
        itemBuilder: (context, index) {
          final line = widget.lyrics[index];
          final isActive = index == _activeIndex;

          return GestureDetector(
            onTap: () => widget.onLyricTap?.call(line.time),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              constraints: BoxConstraints(minHeight: _lineHeight),
              padding: const EdgeInsets.symmetric(vertical: 4),
              alignment: Alignment.centerLeft,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                style: TextStyle(
                  color: isActive
                      ? BinsTapeColors.tapeAmber
                      : BinsTapeColors.dimText.withValues(alpha: 0.6),
                  fontSize: isActive ? 20 : 16,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  shadows: isActive
                      ? [
                          Shadow(
                            color: BinsTapeColors.tapeAmber
                                .withValues(alpha: 0.4),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: Text(line.text),
              ),
            ),
          );
        },
      ),
    );
  }
}
