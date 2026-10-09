import 'dart:io';

import 'package:flutter/widgets.dart';

/// http(s) URL이면 네트워크 이미지, 아니면(임베드 아트워크를 캐시 파일로 꺼내둔 경로)
/// 로컬 파일 이미지로 보여준다.
ImageProvider artImageProvider(String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(path);
  }
  return FileImage(File(path));
}
