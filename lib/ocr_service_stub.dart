import 'lyrics_ocr.dart';

/// 웹이 아닌 빌드(APK 등)용: 영상 OCR은 PC 웹(브라우저)에서만 동작한다.
bool get videoOcrSupported => false;

Future<Object?> pickVideoForOcr() async => null;

Future<List<FrameText>> extractFrameTexts({
  required Object video,
  required OcrRegion region,
  required Duration step,
  required void Function(double progress, String preview) onProgress,
  required bool Function() isCancelled,
}) async {
  throw UnsupportedError('영상 OCR은 PC 웹에서만 사용할 수 있어요.');
}
