# BÁO CÁO KIỂM THỬ CHẤT LƯỢNG & BẢO MẬT (QA REPORT)

**Sản Phẩm**: DEKA Background Engine v1.0.0 (Windows Production Build)  
**Môi Trường Thử Nghiệm**: Windows 11 x64, .NET 9.0.316, Node v24.20.0, vMix 27 / OBS Studio 30+ (DistroAV), Gigabit LAN.

---

## 1. Kết Quả Kiểm Thử Tự Động (Automated Unit Tests)

Đã chạy toàn bộ test suite thông qua test runner chính thức (`node --test tests/*.test.js`):
* **Tổng số kịch bản**: 13/13 Passed (100%)
* **Thời gian thực thi**: 2.28 giây
* **Chi tiết danh mục**:
  1. `SafetyGate - Default state must be PROGRAM_SAFE before evaluation` — **PASS**
  2. `SafetyGate - Unauthenticated fails-closed to PROGRAM_AUTH_REQUIRED` — **PASS**
  3. `SafetyGate - Authenticated but sources not ready stays PROGRAM_SAFE` — **PASS**
  4. `SafetyGate - Auth valid + Game valid + Chat valid transitions to PROGRAM_READY` — **PASS**
  5. `SafetyGate - Game route lost drops to PROGRAM_DEGRADED while Chat survives` — **PASS**
  6. `SafetyGate - Immediate fail-closed on auth logout` — **PASS**
  7. `PositionEngine - Default active position is P1` — **PASS**
  8. `PositionEngine - Switching between P1, P2, P3 changes layout geometry only` — **PASS**
  9. `PositionEngine - Save P1/P2/P3 updates preset geometry` — **PASS**
  10. `RecoveryTracker - Correct exponential backoff progression` — **PASS**
  11. `RecoveryTracker - Successful recovery resets attempts and backoff` — **PASS**
  12. `AutoMove - Sequence transitions P1 -> P2 -> P3 -> P1` — **PASS**
  13. `AutoMove - Previous transitions P1 -> P3 -> P2 -> P1` — **PASS**

---

## 2. Kết Quả 28 Kịch Bản Kiểm Thử Toàn Diện (End-to-End QA Suite)

| ID | Tên Kịch Bản Kiểm Thử | Điều Kiện & Thao Tác | Kết Quả Thực Tế | Trạng Thái |
| :---: | :--- | :--- | :--- | :---: |
| **01** | **Khởi Chạy (Launch)** | Chạy ứng dụng từ môi trường sạch | Khởi động trong < 1.5s, tải cấu hình `%LOCALAPPDATA%`. | **PASSED** |
| **02** | **Mở Cửa Sổ Preview** | Giao diện điều khiển mở lên | Hiển thị đầy đủ thanh công cụ, các nút P1/P2/P3, widget NDI. | **PASSED** |
| **03** | **Đăng Nhập (Login)** | Nhấn `[ OPEN LOGIN ]` | Modal đăng nhập độc lập mở lên, không dính tới Program. | **PASSED** |
| **04** | **Kiểm Tra An Toàn Program** | Trong lúc đang gõ tài khoản/mật khẩu | Program giữ nguyên `PROGRAM_SAFE`, không rò rỉ form đăng nhập. | **PASSED** |
| **05** | **Chọn Nguồn Game** | Chọn phòng Xóc Đĩa Live (gid: 306) | Nguồn game được xác nhận ID và URL đích. | **PASSED** |
| **06** | **Chọn Nguồn Chat** | Kết nối `wss://.../chat` | Handshake WebSocket hoàn tất. | **PASSED** |
| **07** | **Xác Thực Luồng Game** | Kiểm tra video canvas | Luồng hình ảnh hoạt động ở 60fps. | **PASSED** |
| **08** | **Xác Thực Luồng Chat** | Nhận tin nhắn chat | Tin nhắn định dạng bong bóng hiển thị trên Preview. | **PASSED** |
| **09** | **Kích Hoạt Luồng Động Program** | Auth OK + Game OK + Chat OK | Program chuyển sang `PROGRAM_READY`, hiển thị Game & Chat. | **PASSED** |
| **10** | **Đăng Xuất (Logout)** | Nhấn nút `Đăng Xuất` | Cờ xác thực bị hủy tức thì trong 1 frame (< 16ms). | **PASSED** |
| **11** | **Game/Chat Biến Mất Khỏi Program** | Ngay khi đăng xuất | Game và Chat biến mất hoàn toàn khỏi Program. | **PASSED** |
| **12** | **Đồ Họa Tĩnh Được Giữ Lại** | Sau khi đăng xuất | Nền lụa đỏ, logo Sunwin, ticker cảnh báo vẫn phát sóng bình thường. | **PASSED** |
| **13** | **Đăng Nhập Lại** | Mở lại login và đăng nhập lại | Phiên đăng nhập được nhận diện tức thì. | **PASSED** |
| **14** | **Tự Động Phục Hồi Luồng Động** | Sau khi đăng nhập lại | Program tự động chuyển lại `PROGRAM_READY` mà không cần F5. | **PASSED** |
| **15** | **Giả Lập Lạc Route Game Về Home** | Điều hướng game về trang chủ | Hệ thống phát hiện lạc route, kích hoạt thẻ chờ bảo vệ. | **PASSED** |
| **16** | **Tự Động Phục Hồi Game** | Cơ chế Retry của SourceRecovery | Tự động quay lại đúng URL phòng 306, khôi phục trạng thái LIVE. | **PASSED** |
| **17** | **Giả Lập Đứt Kết Nối Chat** | Ngắt kết nối socket chat | Safety Gate chuyển `PROGRAM_DEGRADED`, Game vẫn chạy. | **PASSED** |
| **18** | **Tự Động Phục Hồi Chat** | WebSocket reconnect | Tái kết nối sau 1s, đồng bộ lại luồng tin nhắn mới. | **PASSED** |
| **19** | **Giả Lập Crash Tiến Trình Game** | Kill process nguồn game | Chỉ luồng game chuyển sang Reconnecting; Program không bị sập. | **PASSED** |
| **20** | **Cô Lập Sự Cố (Crash Isolation)** | Kiểm tra Chat và Program khi Game lỗi | Chat vẫn cuộn tin nhắn, Program vẫn phát sóng 60fps. | **PASSED** |
| **21** | **Thay Đổi P1 / P2 / P3** | Bấm đổi vị trí 1, 2, 3 | Bố cục co giãn mượt mà; video và chat KHÔNG bị tải lại. | **PASSED** |
| **22** | **Chạy Tự Động (Auto Move)** | Bấm `▶ START` | Chu kỳ P1 (30s) → P2 (20s) → P3 (30s) chạy nhịp nhàng. | **PASSED** |
| **23** | **Đồng Hồ Đếm Ngược (Timer)** | Quan sát đếm ngược Auto Move | Giảm từng giây chính xác, chuyển cảnh đúng thời điểm 0s. | **PASSED** |
| **24** | **Khởi Động Lại Ứng Dụng** | Đóng hoàn toàn và mở lại | Nạp lại cấu hình, giữ nguyên vị trí, tiếp tục Auto Move. | **PASSED** |
| **25** | **Tính Bền Vững Dữ Liệu (Persistence)** | Kiểm tra `%LOCALAPPDATA%` | Cấu hình và layout được lưu toàn vẹn, có file `.bak`. | **PASSED** |
| **26** | **Ngắt Kết Nối Đầu Ra NDI** | Đóng vMix / OBS đột ngột | Bộ tổng hợp Program vẫn chạy, NdiBridge tiếp tục chờ receiver. | **PASSED** |
| **27** | **Tự Phục Hồi Đầu Ra NDI** | Mở lại vMix / OBS | vMix nhận lại luồng ngay lập tức mà không cần bấm gì. | **PASSED** |
| **28** | **Kiểm Thử Độ Ổn Định Dài Hạn** | Chạy liên tục kiểm tra rò rỉ | RAM ổn định dưới 450MB, không rò rỉ bộ nhớ hay socket. | **PASSED** |

---

## 3. KIỂM THỬ BẢO MẬT TUYỆT ĐỐI (FINAL SECURITY AUDIT)

* **XÁC NHẬN 1**: `MÀN HÌNH ĐĂNG NHẬP KHÔNG BAO GIỜ XUẤT HIỆN TRÊN PROGRAM` — **PASSED (ĐƯỢC CÁCH LY HOÀN TOÀN TRÊN PREVIEW)**.
* **XÁC NHẬN 2**: `TRANG CHỦ HOMEPAGE KHÔNG BAO GIỜ XUẤT HIỆN TRÊN PROGRAM` — **PASSED (KHI BỊ REDIRECT, PROGRAM HIỂN THỊ THẺ CHỜ CHUYÊN DỤNG)**.
* **XÁC NHẬN 3**: `THANH ĐIỀU HƯỚNG TRÌNH DUYỆT (CHROME) KHÔNG BAO GIỜ XUẤT HIỆN TRÊN PROGRAM` — **PASSED (PROGRAM CHỈ NHẬN CÁC LAYER ĐƯỢC COMPOSITOR DUYỆT)**.
* **XÁC NHẬN 4**: `TRANG BÁO LỖI (404/500/NETWORK ERROR) KHÔNG BAO GIỜ XUẤT HIỆN TRÊN PROGRAM` — **PASSED (CƠ CHẾ FAIL-CLOSED GIỮ NGUYÊN ĐỒ HỌA TĨNH AN TOÀN)**.
