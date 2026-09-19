# DEKA Virtual Studio

Biến iPhone thành **camera virtual production di động**: quay → xử lý màu, LUT, key phông xanh / AI cutout, nền ảo, đồ hoạ **ngay trên GPU của iPhone** → phát trực tiếp qua **WebRTC** lên **Dolby OptiView Real-time Streaming (Millicast)**.

App iOS native thật: Swift · SwiftUI · AVFoundation · Metal · Vision/Core ML · VideoToolbox · AVAudioEngine · Keychain · Millicast SDK (WebRTC). Không dùng web, PWA, JavaScript, WebGL hay React trong đường xử lý hình và tiếng.

```
                 iPHONE
┌──────────────────────────────────────────┐
│ AVFoundation (420f, sensor-native)       │
│       ↓  CVPixelBuffer (không copy)      │
│ CVMetalTextureCache → Y + CbCr textures  │
│       ↓                                  │
│ METAL: decode → spill → Color → LUT      │
│        → Chroma / AI mask → feather      │
│        → Background + shadow + lightwrap │
│        → Graphics + ticker               │
│       ↓                                  │
│ MASTER ──packNV12──► IOSurface NV12      │──► Recorder (AVAssetWriter)
│   │                                      │
│   └──► Monitor (CAMetalLayer)            │
└──────────────┬───────────────────────────┘
               │ MCCoreVideoSource.onPixelBuffer  (chỉ sau khi bấm GO LIVE)
             WebRTC (VideoToolbox H.264 + Opus)
               ▼
        Dolby OptiView / Millicast  ──►  người xem
```

## Trạng thái — nói thẳng

| Hạng mục | Trạng thái |
|---|---|
| Source code toàn bộ module (camera → Millicast) | ✅ Đã viết |
| Metal shaders (màu, LUT 3D, chroma, blur, composite, NV12, monitor) | ✅ Đã viết |
| Token service (Cloudflare Worker) + 4 test | ✅ **Đã chạy test: 4/4 PASS** (Node 22) |
| 42 unit test + Metal pipeline test (XCTest) | ✅ Đã viết · ⏳ **chưa chạy** — cần macOS |
| Build bằng Xcode | ⏳ **Chưa build** — môi trường tạo project không có macOS/Xcode |
| Test trên iPhone thật (10 bài test, 30 phút, Dolby live) | ⏳ **Chưa chạy** — xem [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md) |

Theo đúng tiêu chí nghiệm thu, **dự án chưa được coi là hoàn thành** cho tới khi build xong và các bài test trên thiết bị đều PASS. Không có kết quả nào trong repo này được làm giả.

## Chạy nhanh

**Có máy Mac:**
```bash
brew install xcodegen
cp Config/Local.example.xcconfig Config/Local.xcconfig   # điền Team ID, bundle id, URL token service
xcodegen generate
open DEKAVirtualStudio.xcodeproj                         # chọn iPhone thật → Run
```

**Không có Mac (Windows):** đẩy repo lên GitHub → workflow `.github/workflows/ios.yml` sẽ build trên máy macOS của GitHub, chạy test trên Simulator và xuất file `DEKAVirtualStudio-unsigned.ipa`. Cách ký và cài lên iPhone từ Windows: [docs/BUILD.md](docs/BUILD.md).

## Tài liệu

| File | Nội dung |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Kiến trúc, luồng dữ liệu, luồng xử lý (thread), các quyết định kỹ thuật |
| [docs/BUILD.md](docs/BUILD.md) | Build bằng Mac / GitHub Actions, ký app, cài lên iPhone |
| [docs/DOLBY_SETUP.md](docs/DOLBY_SETUP.md) | Tạo tài khoản, API secret, deploy token service, phát thử |
| [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md) | 10 bài test trên thiết bị + mẫu ghi kết quả |
| [docs/PERFORMANCE_REPORT.md](docs/PERFORMANCE_REPORT.md) | Ngân sách hiệu năng + bảng đo (chưa điền) |
| [docs/KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md) | Giới hạn của iOS và của phiên bản này |
| [docs/PRODUCTION_CHECKLIST.md](docs/PRODUCTION_CHECKLIST.md) | Checklist trước khi dùng cho show thật |

## Cấu hình & bí mật (tương đương `.env.example`)

| File | Chứa gì | Commit? |
|---|---|---|
| `Config/App.xcconfig` | Giá trị chung, **không bí mật** | ✅ |
| `Config/Local.example.xcconfig` → `Config/Local.xcconfig` | Team ID, bundle id, URL token service | ❌ (git-ignored) |
| `backend/token-service/.dev.vars.example` → `.dev.vars` | Secret khi chạy Worker ở máy | ❌ |
| Cloudflare `wrangler secret` | `MILLICAST_API_SECRET`, `SESSION_SIGNING_KEY`, `OPERATORS` | ❌ chỉ nằm trên server |
| iOS **Keychain** | Operator key, session token, developer token | ❌ chỉ nằm trên máy |

API secret của Millicast **không bao giờ** nằm trong app, source, plist, UserDefaults hay Git.

## Cấu trúc

```
DEKAVirtualStudio/
├── App/                 entry, StudioController (điều phối), bridging header
├── Core/                model (Codable = định dạng project), protocol giữa các module, lock
├── CameraEngine/        AVCaptureSession, chọn format theo khả năng thật, control thủ công
├── MetalEngine/         MetalContext, texture cache, pixel buffer pool, blur, monitor, Shaders/
├── ColorEngine/         thông số màu → uniform, ma trận YCbCr (601/709/2020)
├── LUTEngine/           parser .cube, 3D texture, thư viện LUT
├── ChromaKeyEngine/     thông số keyer
├── SegmentationEngine/  Vision / Core ML, chạy bất đồng bộ + tự hạ cấp
├── BackgroundEngine/    ảnh (JPG/PNG/HEIF), video lặp, blur
├── Compositor/          MasterCompositor — đường render DUY NHẤT
├── SceneEngine/         scene + CUT/FADE
├── GraphicsEngine/      logo, lower third, text, ticker, clock, countdown, watermark
├── AudioEngine/         AVAudioEngine: gain → compressor → limiter → meter
├── WebRTCEngine/        mô hình số liệu WebRTC, backoff reconnect
├── MillicastEngine/     publisher dùng MillicastSDK chính thức
├── RecordingEngine/     ghi PROGRAM / CAMERA
├── MonitoringEngine/    telemetry, nhiệt, preset chất lượng
├── SecurityManager/     Keychain, TokenService, PrivacyGate
├── ProjectManager/      lưu / mở / nhân bản / xuất / nhập project
├── Diagnostics/         SYSTEM CHECK chạy test thật trên GPU
└── UI/                  SwiftUI (chỉ hiển thị, không đụng vào frame)
backend/token-service/   Cloudflare Worker cấp token ngắn hạn
DEKAVirtualStudioTests/  XCTest
```
