# 화면 녹화 기능 코드 정리 — Record 버튼 & "그리는 과정" 캡처 수정

`CODE_WALKTHROUGH.md`(전체 코드 설명)에서 화면 녹화 관련 부분만 뽑아 정리한 문서입니다.
관련 파일은 3개입니다.

- `app/src/main/res/layout/activity_main.xml` — Record 토글 버튼 배치
- `app/src/main/java/com/example/robotdrawing/MainActivity.kt` — 버튼 클릭 시 녹화 시작/정지
- `app/src/main/java/com/example/robotdrawing/DrawingVideoRecorder.kt` — 실제 프레임을 캡처해서 mp4로 인코딩
- `app/src/main/java/com/example/robotdrawing/DrawingView.kt` — 캡처 대상이 되는 비트맵을 만들어주는 `exportBitmap()`

---

## 1. Record 버튼 — 레이아웃

왼쪽 툴바 안에 있는 토글 버튼입니다. 클릭할 때마다 "녹화 시작 ↔ 녹화 중지"를 오가고,
배경색으로 지금 녹화 중인지 아닌지를 표시합니다.

```xml
<com.google.android.material.button.MaterialButton
    android:id="@+id/btnRecord"
    android:layout_width="match_parent"
    android:layout_height="0dp"
    android:layout_weight="1"
    android:text="@string/record"
    android:textSize="15sp"
    android:textAllCaps="false"
    android:textColor="@color/ink"
    android:background="@drawable/bg_metal_normal"
    app:backgroundTint="@null" />
```

`app:backgroundTint="@null"`이 빠지면 `MaterialButton`이 테마 색으로 배경을 덧칠해버려서
`bg_metal_normal` / `bg_metal_recording` 그라디언트가 안 보이게 됩니다 (v1.2.0 때 겪었던
버튼 색상 버그와 같은 원인이라 여기도 항상 같이 붙여야 합니다).

## 2. Record 버튼 — 클릭 로직 (`MainActivity.kt`)

```kotlin
private fun toggleRecording() {
    if (videoRecorder.isRecording) {
        val finished = videoRecorder.stop()
        lastRecordedVideo = finished
        btnRecord.setBackgroundResource(R.drawable.bg_metal_normal)
        btnRecord.setTextColor(ContextCompat.getColor(this, R.color.ink))
        btnRecord.text = getString(R.string.record)
        if (finished == null) {
            Toast.makeText(this, R.string.recording_failed, Toast.LENGTH_SHORT).show()
        }
    } else {
        val tempFile = File(cacheDir, "recording_${timestamp()}.mp4")
        val started = videoRecorder.start(tempFile)
        if (started) {
            btnRecord.setBackgroundResource(R.drawable.bg_metal_recording)
            btnRecord.setTextColor(ContextCompat.getColor(this, android.R.color.white))
            btnRecord.text = getString(R.string.stop_recording)
            Toast.makeText(this, R.string.recording_started, Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, R.string.recording_failed, Toast.LENGTH_SHORT).show()
        }
    }
}
```

- 버튼을 누르는 시점에 `videoRecorder.isRecording`을 보고 지금이 녹화 중인지 판단합니다.
- 녹화를 멈추면 결과 파일(`finished`)을 `lastRecordedVideo`에 저장해뒀다가, 나중에 "비디오 저장" 버튼을
  누르면 그 파일을 `Movies/RobotDrawing`으로 복사합니다 (`saveVideo()`, 이 문서 범위 밖).
- 녹화 중엔 `cacheDir`(앱 내부 캐시)에 임시 mp4로 씁니다. 실제 갤러리/파일 저장은 별도 버튼입니다.

## 3. `DrawingVideoRecorder.kt` — 프레임을 직접 밀어넣는 방식의 녹화

화면 전체를 캡처하는 게 아니라, `DrawingView`가 그린 내용만 `MediaRecorder`의 입력
Surface에 100ms마다 직접 그려 넣는 방식입니다. 카메라/마이크 권한이 필요 없습니다.

```kotlin
class DrawingVideoRecorder(private val drawingView: DrawingView) {

    private var mediaRecorder: MediaRecorder? = null
    private var inputSurface: Surface? = null
    private var handler: Handler? = null
    private var frameRunnable: Runnable? = null

    var outputFile: File? = null
        private set
    var isRecording = false
        private set

    private val frameIntervalMs = 100L // ~10 fps is plenty for a slow-moving drawing

    fun start(targetFile: File): Boolean {
        if (isRecording) return false
        val width = evenDimension(drawingView.width)
        val height = evenDimension(drawingView.height)
        if (width <= 0 || height <= 0) return false

        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(drawingView.context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        return try {
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recorder.setVideoSize(width, height)
            recorder.setVideoFrameRate(10)
            recorder.setVideoEncodingBitRate(4_000_000)
            recorder.setOutputFile(targetFile.absolutePath)
            recorder.prepare()
            val surface = recorder.surface
            recorder.start()

            mediaRecorder = recorder
            inputSurface = surface
            outputFile = targetFile
            isRecording = true

            val mainHandler = Handler(Looper.getMainLooper())
            handler = mainHandler
            val runnable = object : Runnable {
                override fun run() {
                    if (!isRecording) return
                    pushFrame(surface)
                    mainHandler.postDelayed(this, frameIntervalMs)
                }
            }
            frameRunnable = runnable
            mainHandler.post(runnable)
            true
        } catch (e: Exception) {
            try {
                recorder.release()
            } catch (_: Exception) {
            }
            mediaRecorder = null
            inputSurface = null
            isRecording = false
            false
        }
    }

    private fun pushFrame(surface: Surface) {
        try {
            val bitmap = drawingView.exportBitmap(includeActiveStroke = true)
            val canvas = surface.lockCanvas(null)
            canvas.drawColor(Color.WHITE)
            canvas.drawBitmap(bitmap, 0f, 0f, null)
            surface.unlockCanvasAndPost(canvas)
        } catch (_: Exception) {
            // Drop a bad frame rather than kill the whole recording over it.
        }
    }

    /** Stops recording and returns the finished file, or null if nothing was recorded/it failed. */
    fun stop(): File? {
        if (!isRecording) return null
        isRecording = false
        frameRunnable?.let { handler?.removeCallbacks(it) }
        frameRunnable = null
        handler = null

        val finished = try {
            mediaRecorder?.stop()
            outputFile
        } catch (e: Exception) {
            null
        } finally {
            try {
                mediaRecorder?.release()
            } catch (_: Exception) {
            }
            mediaRecorder = null
            inputSurface = null
        }
        return finished
    }

    private fun evenDimension(value: Int): Int = if (value % 2 == 0) value else value - 1
}
```

핵심 흐름:

1. `start()` — `MediaRecorder`를 `VideoSource.SURFACE` 모드로 준비하고, 인코더가 그림을
   받아갈 입력 `Surface`를 얻습니다. 그리고 `Handler.postDelayed`로 100ms마다 자기 자신을
   다시 스케줄하는 `Runnable`(`frameRunnable`)을 등록합니다 — 이게 "10fps로 프레임을 계속
   밀어넣는" 루프입니다.
2. `pushFrame()` — 매 100ms마다 호출되며, `DrawingView.exportBitmap(...)`으로 현재 그림
   상태를 비트맵으로 뽑아서 `surface.lockCanvas()`로 얻은 캔버스에 그린 뒤
   `unlockCanvasAndPost()`로 인코더에 넘깁니다. 즉 **한 프레임 = exportBitmap 결과 하나**입니다.
3. `stop()` — 루프를 멈추고 `MediaRecorder`를 정지/해제한 뒤 완성된 파일을 돌려줍니다.

## 4. 버그였던 부분 — `DrawingView.exportBitmap()`의 `includeActiveStroke` 옵션

`pushFrame()`이 넘겨받는 비트맵은 결국 `DrawingView.exportBitmap()`이 만드는데, 이 함수는
원래(v1.4.0까지) **완성된 획(`strokes`)만** 그리고 **지금 그리고 있는 중인 획
(`activeStroke`)은 그리지 않았습니다.** 정지 이미지를 PNG로 저장할 때는 이게 맞는
동작입니다 (다 그리지도 않은 획이 저장 이미지에 어중간하게 남으면 안 되니까요). 문제는
영상 녹화도 똑같은 함수를 그대로 재사용했다는 점 — 그래서 손가락/펜을 떼기 전까지는
매 프레임이 "빈 캔버스"였고, 손을 떼는 순간(`ACTION_UP`)에야 완성된 획이 강제로
`strokes`에 편입되면서 그제서야 다음 프레임에 획이 "뿅" 하고 나타났습니다. 즉 실제로는
그리는 과정이 전혀 안 보이고, 획이 끝나는 순간의 결과만 팝업처럼 나타났던 것입니다.

**수정 (v1.4.1)**: `exportBitmap`에 `includeActiveStroke` 파라미터를 추가하고, 기본값은
계속 `false`(이미지 저장용 기존 동작 유지)로 두되, 영상 녹화의 `pushFrame()`만 명시적으로
`true`를 넘기도록 했습니다.

```kotlin
fun exportBitmap(includeActiveStroke: Boolean = false): Bitmap {
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(Color.WHITE)
    for (stroke in strokes) {
        drawStroke(canvas, stroke)
    }
    if (includeActiveStroke) {
        activeStroke?.let { drawStroke(canvas, it) }
    }
    return bitmap
}
```

호출하는 쪽 두 곳의 차이:

| 호출부 | 인자 | 이유 |
|---|---|---|
| `MainActivity.savePng()` — `drawingView.exportBitmap()` | 기본값 `false` | 완성된 획만 PNG로 저장 (그리는 중인 획이 이미지에 섞이면 안 됨) |
| `DrawingVideoRecorder.pushFrame()` — `drawingView.exportBitmap(includeActiveStroke = true)` | `true` | 매 프레임에 지금 그리는 중인 획까지 보여야 "그리는 과정"이 영상에 담김 |

**교훈**: `exportBitmap()`을 새로 호출하는 곳이 생기면, "완성된 결과만 필요한지" vs.
"지금 진행 중인 상태까지 실시간으로 보여야 하는지"를 먼저 구분해서 플래그를 명시적으로
넘겨야 합니다. 기본값 `false`를 그냥 믿고 쓰면 이번처럼 진행 상황이 안 보이는 버그가
재발할 수 있습니다.
