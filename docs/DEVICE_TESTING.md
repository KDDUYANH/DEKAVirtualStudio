# Kiểm thử trên iPhone thật

Tất cả số liệu cần ghi lại đều hiện sẵn trên **telemetry strip** của app (FPS, GPU ms, DROP, BITRATE, RTT, LOSS, JITTER, audio L/R, THERMAL, BATT, MEM, AI) và trên **SYS → SYSTEM CHECK**. Nên quay màn hình (Control Center → Screen Recording) trong suốt bài test làm bằng chứng.

## 0. Chuẩn bị

* iPhone đã sạc đầy, tháo ốp, đặt trên chân máy, **Low Power Mode tắt**.
* Nhiệt độ phòng ghi lại (°C). Wi-Fi 5 GHz (ghi lại tốc độ upload).
* **SYS → RUN SYSTEM CHECK**: mọi dòng phải là PASS (Dolby có thể là WARN nếu dùng developer token).
* Một máy tính mở link viewer (xem DOLBY_SETUP.md).

## 1. Các bài test

| # | Bài test | Cách làm | Đạt khi |
|---|---|---|---|
| 1 | 1080p30 · 30 phút | CAM → 1080p30, BG gradient, LUT 33³ bật, GO LIVE 30 phút | FPS ≥ 29.5 liên tục, DROP tăng < 0.1 %, không crash, THERMAL ≤ WARM |
| 2 | 1080p60 · 30 phút | Như bài 1 với 1080p60 (preset BROADCAST) | FPS ≥ 59, DROP < 0.2 %. Nếu thiết bị bị hạ về 30 fps do nhiệt thì ghi lại thời điểm |
| 3 | Green screen | KEY → CHROMA trước phông xanh; xem MONITOR → MATTE | Matte đen/trắng sạch, tóc giữ được chi tiết, spill không ám xanh da |
| 4 | AI cutout | KEY → AI, BALANCED 30 FPS, người đứng trước nền thường | Mask bám người, AI fps ≥ 15, program FPS không giảm |
| 5 | Đổi LUT khi đang live | Chạm qua lại 3 LUT (17³/33³/65³) mỗi 2 giây trong 2 phút | Không giật, DROP không tăng, viewer thấy đổi ngay |
| 6 | Đổi scene khi đang live | Bấm SCENE 01↔04, FADE 0.5 s và CUT, 50 lần | Stream không gián đoạn, bitrate ổn định, không frame đen |
| 7 | Mất mạng | Đang live, tắt Wi-Fi 10 giây rồi bật lại | App hiện `RECONNECTING n`, không crash, program vẫn chạy |
| 8 | Tự reconnect | Tiếp bài 7, rồi thử tắt mạng 60 giây | Trở lại `LIVE` không cần thao tác; viewer tự hồi (reload nếu cần) |
| 9 | Stress nhiệt | 1080p60 + AI + BG video + ticker, sạc pin, 30 phút | Có cảnh báo trước. Hạ cấp theo thứ tự AI 15 fps → 30 fps → chroma. Stream không bị ngắt |
| 10 | Dolby live output | Viewer ở mạng khác (4G) xem 10 phút | Hình = program (màu, key, logo đúng), tiếng đồng bộ, trễ < 1 giây |

Nghiệm thu bổ sung: âm thanh (meter chạy, không clip khi hét gần mic nhờ limiter), ghi PROGRAM và CAMERA (file mở được trong Photos/Files, có tiếng), và token (sau STOP, token đã bị xoá trên dashboard).

## 2. Mẫu ghi kết quả

Chép bảng này vào `docs/PERFORMANCE_REPORT.md` sau mỗi lần chạy.

```
Thiết bị: iPhone __ (chip A__), iOS __._  · App build: ____ · Ngày: ____ · Phòng: __°C · Upload: __ Mbps

| Test | Thời lượng | FPS tb/min | DROP | GPU ms | Thermal max | Mem MB max | Pin đầu→cuối | Bitrate tb | RTT tb | Loss tb | Kết quả |
|------|-----------|-----------|------|--------|-------------|-----------|--------------|-----------|--------|---------|---------|
| 1    |           |           |      |        |             |           |              |           |        |         |         |
```

## 3. Công cụ hỗ trợ (có Mac)

* **Instruments → Metal System Trace**: thời gian từng pass (Prepare, Composite, Pack NV12, Preview).
* **Instruments → Thermal State + Energy Log**: chạy cùng lúc với bài 9.
* **Console.app**, lọc subsystem `com.dtek.studio`: log của camera, pipeline, ai, stream, security.
