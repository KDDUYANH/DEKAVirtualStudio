# Báo cáo hiệu năng

> **Trạng thái: CHƯA ĐO.** Project được viết trong môi trường không có macOS/Xcode/iPhone, nên chưa có số đo nào trên thiết bị. Các bảng dưới đây để trống có chủ ý. Chỉ điền số liệu thật đo theo [DEVICE_TESTING.md](DEVICE_TESTING.md).

## 1. Ngân sách thiết kế (mục tiêu, không phải số đo)

| Hạng mục | 1080p30 | 1080p60 |
|---|---|---|
| Thời gian mỗi frame | 33.3 ms | 16.7 ms |
| GPU (Prepare + Composite + Pack + Preview) | < 6 ms | < 6 ms |
| CPU encode trên luồng camera | < 1.5 ms | < 1.5 ms |
| Frame đang xử lý tối đa | 3 | 3 |
| Bộ nhớ app | < 350 MB | < 400 MB |
| Mask AI (Vision balanced) | chạy bất đồng bộ, mục tiêu 15–30 fps | |

Dung lượng dữ liệu GPU phải đọc/ghi cho mỗi frame 1080p (ước tính từ định dạng texture): Y + CbCr đọc 3 MB · fg rgba16F ghi/đọc 16.6 MB · matte r16F ×3 khoảng 12 MB · program rgba8 8.3 MB · NV12 ghi 3 MB. **Tổng khoảng 45 MB/frame → khoảng 2.7 GB/s ở 60 fps**, nằm trong khả năng của GPU A15 trở lên. Các tối ưu có thể làm tiếp nếu số đo cho thấy cần: gộp prepare+composite khi không feather, và dùng matte `r8Unorm`.

## 2. Kết quả đo

| Thiết bị | iOS | Test | FPS tb/min | DROP | GPU ms | Thermal max | Mem MB | Pin/30 phút | Bitrate | RTT | Loss |
|---|---|---|---|---|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — | — | — | — | — | — |

## 3. Kết quả test tự động

| Bộ test | Môi trường | Kết quả |
|---|---|---|
| token-service (`npm test`) | Node 22, Linux | **4/4 PASS** (đã chạy) |
| XCTest (42 test: parser, màu, scene, nhiệt, preset, stats, project, keychain, audio, Metal pipeline) | iOS Simulator / iPhone | **chưa chạy** — chạy bằng GitHub Actions hoặc `⌘U` |
| SYSTEM CHECK trên máy | iPhone | **chưa chạy** |
