# Build & cài đặt

Apple chỉ cho build app iOS trên macOS (Xcode). Có ba cách, xếp theo chi phí từ thấp tới cao.

## A. GitHub Actions (không cần Mac, miễn phí với repo public)

1. Tạo repo trên GitHub rồi push code:
   ```bash
   git remote add origin https://github.com/<you>/DEKAVirtualStudio.git
   git push -u origin main
   ```
2. Workflow `iOS` tự chạy trên máy `macos-15` và làm các việc sau:
   * `npm test` cho token service
   * `xcodegen generate` → resolve MillicastSDK 2.6.0
   * `xcodebuild test` trên iOS Simulator (runner Apple silicon, Metal thật): 42 test
   * `xcodebuild build -sdk iphoneos` không ký → **`DEKAVirtualStudio-unsigned.ipa`**
3. Tải artifact về từ tab **Actions → run → Artifacts**. Kèm theo có `test.log`, `build.log` và `TestResults.xcresult`.

> Repo private: GitHub tính phút chạy macOS theo hệ số cao hơn Linux. Hãy xem hạn mức của gói tài khoản trước khi chạy thường xuyên.

### Cài IPA lên iPhone từ Windows

IPA chưa ký thì không cài được. Có hai cách để ký:

| Cách | Chi phí | Giới hạn |
|---|---|---|
| Công cụ sideload trên Windows (ví dụ Sideloadly) + Apple ID miễn phí | 0 đ | App hết hạn sau 7 ngày, phải ký lại. Cần bật **Developer Mode** trên iPhone (Settings → Privacy & Security) |
| Apple Developer Program + TestFlight | 99 USD/năm | Build 90 ngày, cài qua app TestFlight, không cần cắm cáp |

Với cách TestFlight, thêm vào workflow bước `xcodebuild archive` + `-exportArchive`, dùng certificate và profile đưa vào qua GitHub Secrets. Sau đó upload bằng App Store Connect API key. Toàn bộ chạy trên runner, anh không cần Mac.

> Bundle ID phải là duy nhất trên mỗi Apple ID. Đổi `DEKA_BUNDLE_ID` trong `Config/Local.xcconfig`. Với CI, truyền `DEKA_BUNDLE_ID=...` vào lệnh `xcodebuild`.

## B. Mac thuê theo giờ

Dịch vụ macOS cloud (thuê theo giờ hoặc theo ngày) phù hợp để debug trực tiếp bằng Xcode: breakpoint, Instruments. Làm theo mục C trên máy thuê. iPhone cắm vào máy local thì không dùng được với Mac cloud, nên chỉ dùng cách này để debug phần build và Simulator.

## C. Có máy Mac

Yêu cầu: macOS mới nhất, Xcode 16 trở lên (iOS 17 SDK trở lên), iPhone chạy iOS 17 trở lên (khuyến nghị A15 trở lên cho 1080p60 + AI).

```bash
brew install xcodegen
cp Config/Local.example.xcconfig Config/Local.xcconfig
#  DEKA_DEVELOPMENT_TEAM = <Team ID>
#  DEKA_BUNDLE_ID        = vn.<ten>.dekavirtualstudio
#  DEKA_TOKEN_SERVICE_URL = https:/$()/deka-token.<ten>.workers.dev
xcodegen generate
open DEKAVirtualStudio.xcodeproj
```

* Chọn scheme `DEKAVirtualStudio`, chọn iPhone thật rồi **Run**.
* Chạy test: `⌘U` (Simulator hoặc iPhone). Metal test chạy thật trên GPU.
* Profile: **Product → Profile → Metal System Trace / Time Profiler / Thermal State**.

Dòng lệnh:

```bash
xcodebuild test -project DEKAVirtualStudio.xcodeproj -scheme DEKAVirtualStudio \
  -destination 'platform=iOS,name=<Tên iPhone>'
```

## Dependency

| Package | Phiên bản | Ghi chú |
|---|---|---|
| MillicastSDK (`github.com/millicast/millicast-sdk-swift-package`) | **2.6.0** (ghim chính xác) | Binary xcframework, đã chứa WebRTC. Header đã được kiểm tra trực tiếp: `MCCoreVideoSource`, `MCCustomAudioSource`, `MCPublisher`, `MCStatsReport` |

Không có dependency nào khác. Mọi thứ còn lại là framework của Apple.

## Xử lý lỗi build thường gặp

| Triệu chứng | Nguyên nhân / cách sửa |
|---|---|
| `No such module 'MillicastSDK'` | File → Packages → Resolve Package Versions |
| `Signing requires a development team` | Điền `DEKA_DEVELOPMENT_TEAM` trong `Local.xcconfig` rồi chạy lại `xcodegen generate` |
| Lỗi trong file `.metal` | Xem Report Navigator: shader được biên dịch lúc build nên lỗi hiện ngay ở bước build |
| Warning deprecation (`.allowBluetooth`…) trên SDK mới | API bị đổi tên trong SDK mới hơn. Đổi sang tên mới mà Xcode gợi ý |
