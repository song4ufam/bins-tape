package com.example.bins_tape

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service(잠금화면/알림 재생 컨트롤)가 미디어 버튼을 제대로 받으려면
// 기본 FlutterActivity 대신 이 서브클래스를 써야 한다.
class MainActivity : AudioServiceActivity()
