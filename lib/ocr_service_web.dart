import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'lyrics_ocr.dart';

/// 웹 빌드용 구현: 브라우저에서 영상 프레임을 캔버스로 뽑고 Tesseract.js(한글+영어)로 글자를 읽는다.
/// Tesseract.js는 web/index.html에서 CDN으로 불러온다.
bool get videoOcrSupported => true;

/// 영상 파일을 고른다. 브라우저 안에서만 쓰는 임시 주소(blob URL)를 돌려준다.
Future<Object?> pickVideoForOcr() {
  final completer = Completer<Object?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'video/*';
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (!completer.isCompleted) {
      completer.complete(file == null ? null : web.URL.createObjectURL(file));
    }
  }).toJS;
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }).toJS,
  );
  input.click();
  return completer.future;
}

JSObject _tesseract() {
  final t = globalContext['Tesseract'];
  if (t == null || t.isUndefinedOrNull) {
    throw StateError('글자 인식 엔진(Tesseract.js)을 불러오지 못했어요. 인터넷 연결을 확인해주세요.');
  }
  return t as JSObject;
}

Future<web.HTMLVideoElement> _loadVideo(String url) async {
  final video = web.HTMLVideoElement()
    ..src = url
    ..muted = true
    ..preload = 'auto';
  final ready = Completer<void>();
  // metadata가 아니라 'loadeddata'를 기다려야 첫 화면이 실제로 그려질 수 있는 상태가 된다.
  video.onloadeddata = ((web.Event _) {
    if (!ready.isCompleted) ready.complete();
  }).toJS;
  video.onerror = ((web.Event _) {
    if (!ready.isCompleted) {
      ready.completeError(StateError('이 영상 형식은 브라우저에서 열 수 없어요. mp4로 시도해보세요.'));
    }
  }).toJS;
  await ready.future.timeout(const Duration(seconds: 20));
  return video;
}

Future<void> _seek(web.HTMLVideoElement video, double seconds) {
  // 이미 그 시간에 있으면 'seeked' 이벤트가 오지 않으므로 기다리지 않는다.
  if ((video.currentTime - seconds).abs() < 0.001) return Future.value();
  final done = Completer<void>();
  video.onseeked = ((web.Event _) {
    if (!done.isCompleted) done.complete();
  }).toJS;
  video.currentTime = seconds;
  return done.future.timeout(const Duration(seconds: 10));
}

/// 두 프레임이 사실상 같은 화면인지 (평균 밝기 차이가 작으면 같은 화면).
bool _sameFrame(Uint8List? a, Uint8List b) {
  if (a == null || a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i += 4) {
    diff += (a[i] - b[i]).abs();
  }
  return diff / (a.length / 4) < 3;
}

Future<List<FrameText>> extractFrameTexts({
  required Object video,
  required OcrRegion region,
  required Duration step,
  required void Function(double progress, String preview) onProgress,
  required bool Function() isCancelled,
}) async {
  final url = video as String;
  final videoEl = await _loadVideo(url);
  final totalSeconds = videoEl.duration;
  if (totalSeconds.isNaN || totalSeconds.isInfinite || totalSeconds <= 0) {
    throw StateError('영상 길이를 읽지 못했어요.');
  }

  onProgress(0, '글자 인식 준비 중... (처음엔 한글 데이터를 내려받느라 조금 걸려요)');
  final tess = _tesseract();
  final worker = await (tess.callMethod<JSPromise<JSObject>>(
    'createWorker'.toJS,
    'kor+eng'.toJS,
  )).toDart;
  await (worker.callMethod<JSPromise<JSAny?>>(
    'setParameters'.toJS,
    {'tessedit_pageseg_mode': '6'}.jsify(),
  )).toDart;

  // 가사 영역만 잘라 그리는 캔버스 (너비 960으로 맞춰서 속도와 정확도의 균형을 잡는다).
  final vw = videoEl.videoWidth;
  final vh = videoEl.videoHeight;
  final sy = vh * region.top;
  final sh = vh * (region.bottom - region.top);
  final outW = vw > 960 ? 960 : vw;
  final outH = (sh * outW / vw).round().clamp(1, 4000);
  final canvas = web.HTMLCanvasElement()
    ..width = outW
    ..height = outH;
  final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;

  // 화면이 안 바뀐 프레임은 다시 읽지 않고 이전 결과를 쓴다 (속도를 크게 줄여준다).
  final small = web.HTMLCanvasElement()
    ..width = 48
    ..height = 24;
  final smallCtx = small.getContext('2d') as web.CanvasRenderingContext2D;

  final frames = <FrameText>[];
  Uint8List? previousFingerprint;
  var previousText = '';

  try {
    for (var t = Duration.zero;
        t.inMilliseconds / 1000 < totalSeconds;
        t += step) {
      if (isCancelled()) break;

      await _seek(videoEl, t.inMilliseconds / 1000);
      ctx.drawImage(videoEl, 0, sy, vw, sh, 0, 0, outW, outH);

      smallCtx.drawImage(canvas, 0, 0, 48, 24);
      final fingerprint =
          smallCtx.getImageData(0, 0, 48, 24).data.toDart.buffer.asUint8List();

      var text = previousText;
      if (!_sameFrame(previousFingerprint, fingerprint)) {
        final result = await (worker.callMethod<JSPromise<JSObject>>(
          'recognize'.toJS,
          canvas,
        )).toDart;
        final data = result['data'] as JSObject;
        text = (data['text'] as JSString).toDart
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        previousFingerprint = fingerprint;
        previousText = text;
      }

      frames.add(FrameText(t, text));
      onProgress(t.inMilliseconds / 1000 / totalSeconds, text);
    }
  } finally {
    await (worker.callMethod<JSPromise<JSAny?>>('terminate'.toJS)).toDart;
    web.URL.revokeObjectURL(url);
  }
  return frames;
}
