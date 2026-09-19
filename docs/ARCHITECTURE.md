# Kiến trúc — DEKA Virtual Studio

## 1. Nguyên tắc

1. **Chỉ một đường render.** `MasterCompositor` tạo frame MASTER. Màn hình monitor, stream và file ghi đều lấy từ frame này. Không có đường render thứ hai.
2. **Không copy qua CPU.** Camera `CVPixelBuffer` → `CVMetalTextureCache` → texture. Output được GPU ghi thẳng vào `CVPixelBuffer` NV12 dùng IOSurface. Encoder (VideoToolbox, qua WebRTC) và `AVAssetWriter` dùng lại đúng buffer đó.
3. **Không bao giờ chặn luồng camera.** AI, nạp LUT, giải mã ảnh nền và vẽ chữ đều chạy trên queue riêng. Luồng render chỉ đọc kết quả mới nhất đã có sẵn.
4. **Bỏ frame chứ không xếp hàng.** Nếu GPU còn bận 3 frame thì frame mới bị bỏ. Frame bị bỏ được đếm và hiển thị. Nhờ vậy độ trễ luôn ổn định.
5. **Quyền riêng tư nằm trong kiến trúc.** Publisher chỉ được gắn vào output sau khi người vận hành bấm GO LIVE (`PrivacyGate`).

## 2. Luồng dữ liệu của một frame

```
capture queue (deka.camera.video, userInteractive)
│
├─ AVCaptureVideoDataOutput → CMSampleBuffer → CVPixelBuffer (420f, sensor-native)
├─ MasterCompositor.camera(didOutput:)
│   ├─ inFlight.wait(timeout: now)       → bận thì bỏ frame (droppedGPUBusy)
│   ├─ Y  = r8Unorm  texture (cache)     ┐
│   ├─ CbCr = rg8Unorm texture (cache)   ┘ không copy
│   ├─ SceneEngine.renderState(t)        → cảnh đang vào (+ cảnh đang ra nếu đang FADE)
│   ├─ SegmentationEngine.submit(frame)  → không chặn, bỏ qua nếu AI đang bận
│   ├─ PixelBufferPool.makeBuffer()      → NV12 video-range BT.709 (hết buffer thì bỏ frame)
│   └─ một MTLCommandBuffer:
│        [chỉ khi dùng midtone detail] resample Y ¼ → gaussian
│        lane A: prepareForeground → gaussianBlur(matte) → compositeProgram
│        lane B: (chỉ khi FADE) như lane A → mixPrograms → MASTER
│        packNV12 (MASTER → output pixel buffer)
│        monitor draw (CAMetalLayer drawable; tự bỏ qua nếu màn hình chậm)
│        commit
│
└─ completion (Metal thread) → deliveryQueue → sinks
        ├─ MillicastEngine  (chỉ khi được gắn, và PrivacyGate đang mở)
        └─ RecordingEngine  (chỉ khi đang ghi)
```

### Thứ tự trong shader (`prepareForeground`)

```
YCbCr ──ma trận (601/709/2020, full/video range lấy từ attachment của buffer)──► RGB
   │
   ├─ matte: chroma (khoảng cách CbCr, trên tín hiệu CHƯA grade) hoặc mask AI
   ├─ spill suppression (chỉ khi dùng chroma)
   ├─ grade: exposure+WB (linear) → blacks/whites → shadows/highlights → contrast
   │         → midtone detail → lift/gamma/gain/offset → hue → saturation/vibrance
   └─ LUT 3D (trilinear phần cứng, map nửa texel, có intensity)
```

Key được tính trên tín hiệu **chưa grade**. Vì vậy khi đổi màu hay đổi LUT giữa show, key không bị hỏng.

## 3. Luồng xử lý (thread)

| Queue / thread | Công việc | Có được chặn không? |
|---|---|---|
| main | SwiftUI, cập nhật telemetry 2 lần/giây | không bao giờ nhận frame |
| `deka.camera.session` | cấu hình AVCaptureSession / thiết bị | có (tách khỏi render) |
| `deka.camera.video` | encode GPU cho mỗi frame | **không** (khoảng 1 ms CPU) |
| `deka.master.delivery` | giao frame cho stream / recorder | không |
| `deka.ai.segmentation` | Vision / Core ML | có (tách riêng) |
| `deka.lut.load`, `deka.background.load`, `deka.graphics` | parse / decode / vẽ chữ | có (tách riêng) |
| `deka.audio.control`, audio tap | xử lý tiếng, meter, chia chunk 10 ms | không |
| `deka.millicast.audio` | đóng frame Opus 10 ms | không |
| `deka.recording` | ghi bằng AVAssetWriter | không |

Dữ liệu dùng chung giữa các thread đi qua `Locked<T>` (`OSAllocatedUnfairLock`). Mỗi lần khoá chỉ để copy một struct nhỏ.

## 4. Các module

| Module | Vai trò | API chính |
|---|---|---|
| CameraEngine | Tìm camera, chọn format theo khả năng thật (`CameraFormatSelector`), AUTO/LOCK/MANUAL, xoay bằng `RotationCoordinator` (xoay trong shader nên không tốn thêm) | `CameraManager` |
| MetalEngine | Pipeline state biên dịch một lần, texture cache, pool, blur, monitor | `MetalContext`, `GPUBlur`, `MetalRenderer` |
| ColorEngine | Settings → uniforms, chọn ma trận YCbCr | `ColorEngine.apply/decode` |
| LUTEngine | Parser `.cube`, texture 3D (`rgba16Float`), thư viện, yêu thích | `CubeLUTParser`, `LUTLibrary` |
| ChromaKeyEngine | Màu key → CbCr, thông số | `ChromaKeyEngine.apply` |
| SegmentationEngine | Vision `VNGeneratePersonSegmentationRequest` (có `VNSequenceRequestHandler` để mask ổn định qua các frame) hoặc Core ML đóng gói kèm; tự hạ cấp theo thứ tự | `SegmentationEngine` |
| BackgroundEngine | Ảnh (tối đa 4K, blur một lần ở ¼ độ phân giải), video lặp (`AVPlayerLooper` + `AVPlayerItemVideoOutput`) | `frame(for:commandBuffer:)` |
| GraphicsEngine | Vẽ bằng Core Text vào IOSurface khi có thay đổi (hoặc 1 lần/giây nếu có đồng hồ). Ticker được vẽ một lần, GPU cuộn | `layer(for:)`, `ticker(for:)` |
| SceneEngine | Scene + CUT/FADE (smoothstep), sửa scene đang chạy trực tiếp | `take`, `renderState(at:)` |
| Compositor | Đường render duy nhất, danh sách sinks | `MasterCompositor` |
| AudioEngine | Gain → AUDynamicsProcessor → AUPeakLimiter → ceiling → tap (meter vDSP, Int16 48 kHz) | `AudioEngine` |
| WebRTCEngine | Mô hình số liệu, tính bitrate từ bộ đếm, backoff | `StreamStats`, `ReconnectPolicy` |
| MillicastEngine | `MCPublisher` + `MCCoreVideoSource` + `MCCustomAudioSource`, số liệu thật từ `MCStatsReport` | `start`, `stop` |
| RecordingEngine | PROGRAM (NV12 MASTER) / CAMERA (tín hiệu sạch), HEVC, bảo vệ khi sắp hết bộ nhớ | `start`, `stop` |
| MonitoringEngine | Telemetry, bộ nhớ (`phys_footprint`), pin, chính sách nhiệt, preset | `ThermalPolicy`, `QualityPreset` |
| SecurityManager | Keychain (`ThisDeviceOnly`), `TokenService`, `PrivacyGate` | |
| ProjectManager | JSON + thư mục assets. Khi mở, JSON được trộn lên giá trị mặc định nên file cũ vẫn mở được | |
| Diagnostics | `GPUTestHarness` chạy kernel thật trên frame tổng hợp. `SystemCheck` dùng chung | |

## 5. Quyết định kỹ thuật (và lý do)

**Millicast SDK chính thức, không tự viết WebRTC.** MillicastSDK 2.6.0 (SPM `millicast-sdk-swift-package`) đã đóng gói Google WebRTC. `MCCoreVideoSource.onPixelBuffer(_:withTimestamp:)` nhận thẳng `CVPixelBuffer` NV12 của MASTER. Nếu thêm một gói WebRTC thứ hai, hai bản sẽ trùng symbol khi link. Module `WebRTCEngine` vì vậy chỉ chứa phần không phụ thuộc cách truyền: số liệu, backoff và giao diện `StreamPublisher`. Cần đổi CDN/SFU khác thì chỉ viết một implementation `StreamPublisher` mới.

**Output NV12 ghi thẳng từ GPU.** H.264 phần cứng dùng 4:2:0. Nếu gửi BGRA, WebRTC phải chuyển đổi bằng libyuv trên CPU, tốn khoảng 5–8 ms CPU mỗi frame 1080p. `packNV12` làm việc này trên GPU trong vài phần mười ms.

**CAMetalLayer thay vì MTKView.** MTKView chỉ là lớp bọc quanh CAMetalLayer. Dùng layer trực tiếp thì bước vẽ monitor nằm chung command buffer với MASTER, chạy trên luồng camera, không cần nhảy sang main thread. Monitor tự bỏ frame (tối đa 2 lần present đang chờ) nên không bao giờ làm chậm program.

**FADE render hai lane.** Khi chuyển cảnh, cả hai cảnh được render từ camera đang chạy rồi trộn lại, không dùng ảnh đứng yên. Việc này chỉ tốn gấp đôi trong khoảng 0,5 giây chuyển cảnh.

**Không bao giờ chờ AI.** Nếu chưa có mask, cảnh AI tạm hiển thị camera không key trong vài frame đầu. Khi AI chậm, engine hạ theo thứ tự: giảm fps → dùng lại mask cũ → giảm chất lượng → đề xuất chuyển sang chroma (tuỳ cấu hình).

**Xử lý nhiệt: cảnh báo trước, hạ cấp sau.** Mức `fair` chỉ cảnh báo. `serious` áp dụng đúng một bước tiếp theo. `critical` áp dụng tất cả các bước còn lại. Thứ tự các bước cấu hình được. Chính sách là hàm thuần nên có unit test. Khi máy đã nguội, việc khôi phục chất lượng do người vận hành quyết định, để tránh chất lượng dao động lên xuống.

## 6. Bảo mật

```
iPhone ──(operator key trong Keychain)──► POST /v1/session ──► session JWT 12 h (Keychain, xoay vòng)
iPhone ──(Bearer session)──► POST /v1/publish-token ──► Worker ──(API secret)──► api.millicast.com
                                                    ◄── token publish sống 4 h (chỉ trong RAM)
iPhone ──► director.millicast.com ──► WebRTC
STOP ──► DELETE /v1/publish-token/:id (thu hồi)
```

* Secret chỉ nằm trong Cloudflare Worker secrets.
* HTTPS bắt buộc (kiểm tra trong code và ATS), TLS ≥ 1.2, `URLSession` ephemeral (không cache/cookie).
* Stream name được kiểm tra trên server theo regex (`ALLOWED_STREAM_PATTERN`).
* JWT HS256, từ chối `alg:none`, so sánh hằng thời gian (constant-time) cho operator key.
* Token publish mới cho mỗi lần reconnect. Token hết hạn không làm dừng show.
* Chế độ "Developer token" (lưu Keychain) chỉ dùng để thử khi chưa có backend. UI ghi nhãn rõ ràng.
