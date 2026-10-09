import 'package:flutter/widgets.dart';

/// 웹 빌드용: 로컬 파일 앨범아트는 없고 항상 네트워크 이미지로 취급한다.
ImageProvider artImageProvider(String path) => NetworkImage(path);
