package com.example.bins_tape

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.KeyEvent
import android.widget.RemoteViews
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 홈 화면 위젯. 실제 재생 상태는 main.dart가 HomeWidget.saveWidgetData로 저장해둔 값을
/// 그대로 보여주기만 한다. 버튼을 누르면 잠금화면 컨트롤과 똑같은 경로(미디어 버튼
/// 방송 -> audio_service의 MediaSession)로 재생을 제어한다 - 이렇게 하면 실제 재생
/// 로직을 위젯 쪽에 따로 만들 필요가 없다.
class BinsTapeWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("widget_title", null) ?: "재생 중인 곡 없음"
        val artist = widgetData.getString("widget_artist", null) ?: "Bin's TAPE를 열어 곡을 재생해보세요"
        val isPlaying = widgetData.getBoolean("widget_is_playing", false)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.bins_tape_widget).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_artist, artist)
                setImageViewResource(
                    R.id.widget_play_pause,
                    if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                )

                // 배경 전체가 아니라 아이콘/곡 정보 영역에서만 앱이 열리도록 해서,
                // 재생 버튼을 살짝 빗나가 눌러도 실수로 앱이 열리지 않게 한다.
                val openAppIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_open_app, openAppIntent)
                setOnClickPendingIntent(R.id.widget_track_info, openAppIntent)
                setOnClickPendingIntent(
                    R.id.widget_prev,
                    mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, 1),
                )
                setOnClickPendingIntent(
                    R.id.widget_play_pause,
                    mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, 2),
                )
                setOnClickPendingIntent(
                    R.id.widget_next,
                    mediaButtonPendingIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, 3),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun mediaButtonPendingIntent(context: Context, keyCode: Int, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON, null, context, MediaButtonReceiver::class.java)
        intent.putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
