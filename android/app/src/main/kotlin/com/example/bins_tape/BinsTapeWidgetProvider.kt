package com.example.bins_tape

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.graphics.Color
import android.view.KeyEvent
import android.widget.RemoteViews
import java.io.File
import com.ryanheise.audioservice.MediaButtonReceiver
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// 홈 화면 위젯. 재생/일시정지/다음/이전은 잠금화면 컨트롤과 같은 경로(미디어 버튼 방송
/// -> audio_service의 MediaSession)로 처리한다 - 안드로이드가 이 신호는 앱이 꺼져있어도
/// 책임지고 전달해주기 때문에 항상 믿을 수 있다.
///
/// 반복/셔플은 그런 표준 신호가 없어서, 대신 상태값 자체(켜짐/꺼짐)를 이 위젯이 직접
/// SharedPreferences에 쓰고 아이콘도 그 자리에서 바로 바꾼다 - Dart 엔진이 하나도 안 깨어있어도
/// 항상 즉시 반영된다. 앱은 다음에 열릴 때 이 값을 읽어서 실제 재생에 반영한다.
class BinsTapeWidgetProvider : HomeWidgetProvider() {

    companion object {
        private const val ACTION_TOGGLE_SHUFFLE = "com.example.bins_tape.widget.TOGGLE_SHUFFLE"
        private const val ACTION_CYCLE_REPEAT = "com.example.bins_tape.widget.CYCLE_REPEAT"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TOGGLE_SHUFFLE -> {
                val prefs = homeWidgetPrefs(context)
                val next = !prefs.getBoolean("widget_is_shuffle", false)
                prefs.edit().putBoolean("widget_is_shuffle", next).apply()
                refreshAllWidgets(context)
            }
            ACTION_CYCLE_REPEAT -> {
                val prefs = homeWidgetPrefs(context)
                val current = prefs.getString("widget_repeat_mode", "off") ?: "off"
                val next = when (current) {
                    "off" -> "all"
                    "all" -> "one"
                    else -> "off"
                }
                prefs.edit().putString("widget_repeat_mode", next).apply()
                refreshAllWidgets(context)
            }
            else -> super.onReceive(context, intent)
        }
    }

    private fun homeWidgetPrefs(context: Context): SharedPreferences =
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

    private fun refreshAllWidgets(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, BinsTapeWidgetProvider::class.java))
        onUpdate(context, manager, ids, homeWidgetPrefs(context))
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("widget_title", null) ?: "재생 중인 곡 없음"
        val artist = widgetData.getString("widget_artist", null) ?: "Bin's TAPE를 열어 곡을 재생해보세요"
        val isPlaying = widgetData.getBoolean("widget_is_playing", false)
        val isShuffle = widgetData.getBoolean("widget_is_shuffle", false)
        val repeatMode = widgetData.getString("widget_repeat_mode", "off") ?: "off"
        val artPath = widgetData.getString("widget_art_path", null)

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.bins_tape_widget).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_artist, artist)
                setImageViewResource(
                    R.id.widget_play_pause,
                    if (isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                )

                val recRed = Color.parseColor("#E0332F")
                val dimCream = Color.parseColor("#8A8A8E")
                setImageViewResource(
                    R.id.widget_repeat,
                    if (repeatMode == "one") R.drawable.ic_widget_repeat_one else R.drawable.ic_widget_repeat,
                )
                setInt(R.id.widget_repeat, "setColorFilter", if (repeatMode == "off") dimCream else recRed)
                setInt(R.id.widget_shuffle, "setColorFilter", if (isShuffle) recRed else dimCream)

                val artBitmap = if (!artPath.isNullOrEmpty() && File(artPath).exists()) {
                    BitmapFactory.decodeFile(artPath)
                } else null
                if (artBitmap != null) {
                    setImageViewBitmap(R.id.widget_album_art, artBitmap)
                    setViewVisibility(R.id.widget_album_art, android.view.View.VISIBLE)
                } else {
                    setViewVisibility(R.id.widget_album_art, android.view.View.GONE)
                }

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
                setOnClickPendingIntent(R.id.widget_repeat, selfActionPendingIntent(context, ACTION_CYCLE_REPEAT, 4))
                setOnClickPendingIntent(R.id.widget_shuffle, selfActionPendingIntent(context, ACTION_TOGGLE_SHUFFLE, 5))
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

    private fun selfActionPendingIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, BinsTapeWidgetProvider::class.java).apply { this.action = action }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
