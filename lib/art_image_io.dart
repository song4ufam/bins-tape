import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// http(s) URL이면 네트워크 이미지, 아니면(임베드 아트워크를 캐시 파일로 꺼내둔 경로)
/// 로컬 파일 이미지로 보여준다.
ImageProvider artImageProvider(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(path);
  }
  return FileImage(File(path));
}

/// 네트워크 이미지를 받아서 임시 파일로 저장하고 그 경로를 돌려준다. 안드로이드
/// 홈 화면 위젯은 네이티브 코드라서 URL을 직접 못 읽기 때문에 필요하다.
Future<String?> downloadToCacheFile(String url) async {
  try {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final dir = await Directory.systemTemp.createTemp('bins_tape_widget_art_');
    final file = File('${dir.path}/art.jpg');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
