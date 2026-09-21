# HƯỚNG DẪN DÀNH CHO KỸ THUẬT VIÊN VẬN HÀNH (README-OPERATOR)

Chào mừng bạn đến với **DEKA Background Engine** — Hệ thống điều khiển đồ họa và tổng hợp nguồn phát trực tiếp chuẩn truyền hình 24/7 cho vMix và OBS Studio.

---

## 1. Giao Diện Điều Khiển (PREVIEW WORKSPACE)

Khi mở phần mềm, bạn sẽ thấy cửa sổ **PREVIEW WORKSPACE** bao gồm:

### A. Thanh Trạng Thái (Header)
* **AUTH STATUS**: Báo hiệu trạng thái đăng nhập (`AUTHENTICATED` hoặc `LOGIN REQUIRED`).
* **GAME STATUS**: Trạng thái luồng cược (`LIVE`, `RECONNECTING`, hoặc `STANDBY`).
* **CHAT STATUS**: Trạng thái luồng bình luận (`CONNECTED`, `RECONNECTING`, hoặc `STANDBY`).
* **SAFETY GATE BADGE**:
  - `PROGRAM READY` (Màu xanh): Tất cả nguồn đã sẵn sàng, luồng động hiển thị đầy đủ trên sóng.
  - `PROGRAM SAFE` (Màu xanh dương): Chỉ hiển thị đồ họa an toàn, ẩn Game và Chat để bảo vệ sóng.
  - `PROGRAM DEGRADED` (Màu cam): Một trong hai nguồn đang kết nối lại, nguồn còn lại vẫn phát bình thường.
  - `PROGRAM AUTH REQUIRED` (Màu đỏ): Yêu cầu đăng nhập tài khoản trước khi đưa luồng lên sóng.

---

## 2. Quy Trình Vận Hành Chuẩn (Step-by-Step)

### Bước 1: Đăng Nhập Tài Khoản
1. Tại khung **AUTHENTICATION GATE**, nhấn nút **`[ OPEN LOGIN ]`**.
2. Cửa sổ đăng nhập bảo mật Sunwin sẽ hiện ra. Bạn đăng nhập tài khoản đại lý / người chơi bình thường.
3. Sau khi đăng nhập thành công, đóng cửa sổ đăng nhập.
4. Trạng thái sẽ chuyển thành **`AUTH: AUTHENTICATED`**.

### Bước 2: Kiểm Tra Nguồn Phát (PROGRAM MONITOR)
1. Quan sát màn hình xem trước **PROGRAM OUTPUT MONITOR** ở góc trái.
2. Kiểm tra xem Game và Chat đã hiển thị mượt mà trên nền đồ họa hay chưa.
3. **Tuyệt đối an tâm**: Màn hình đăng nhập, thanh công cụ duyệt web và thông báo lỗi kỹ thuật **không bao giờ** xuất hiện trên luồng phát sóng này.

### Bước 3: Điều Khiển Bố Cục (THREE POSITIONS)
Bạn có thể bấm trực tiếp các nút bố cục để chuyển cảnh mượt mà:
* **POSITION 1**: Chia đôi màn hình — Game lớn bên trái (1280x720) + Chat trực tiếp bên phải.
* **POSITION 2**: Tiêu điểm cảnh báo thương hiệu — Game thu gọn (1100x620) + Bảng cảnh báo mở rộng.
* **POSITION 3**: Hành động toàn cảnh — Game lớn (1360x765) + Thanh nạp rút tự động.

> **Lưu ý**: Chuyển đổi giữa các Position hoàn toàn không làm gián đoạn hoặc tải lại video/chat!

### Bước 4: Chạy Tự Động (AUTO MOVE)
* Nhấn nút **`▶ START`** để kích hoạt chuỗi chuyển cảnh tự động `P1 → P2 → P3 → P1`.
* Theo dõi đồng hồ đếm ngược **TIME REMAINING** và vị trí kế tiếp **NEXT POSITION**.
* Có thể nhấn **`⏸ PAUSE`**, **`⏹ STOP`**, hoặc bật/tắt **`LOOP`** bất cứ lúc nào.

### Bước 5: Kết Nối Vào vMix / OBS
* Tại khung **OUTPUT**, kiểm tra đèn báo **`● NDI READY`**.
* Tên luồng phát: **`BackgroundEngine-PGM`** (Độ phân giải: 1920x1080 @ 60 FPS).
* **Trong vMix**:
  1. Bấm **Add Input** → chọn **NDI / Desktop Capture**.
  2. Chọn luồng **`BackgroundEngine-PGM`** → Bấm **OK**.
* **Trong OBS Studio**:
  1. Thêm nguồn **NDI™ Source** (Plugin DistroAV).
  2. Chọn Source name **`BackgroundEngine-PGM`** → Bấm **OK**.

---

## 3. Xử Lý Tình Huống Sự Cố (Self-Healing)

* **Nếu mất kết nối mạng Game**:
  Hệ thống tự động hiển thị thẻ chờ `"NGUỒN LIVE ĐANG KẾT NỐI LẠI"` trên luồng Game và thử kết nối lại tối đa 5 lần (1s, 2s, 5s, 10s, 20s). Luồng Chat và đồ họa nền vẫn hoạt động bình thường.
* **Nếu hết hạn phiên đăng nhập**:
  Hệ thống tự động kích hoạt chế độ **Fail-Closed** — ẩn hoàn toàn Game và Chat để chuyển về nền đồ họa tĩnh an toàn, bảo vệ luồng phát trực tiếp trước mắt khán giả. Nhấn `[ OPEN LOGIN ]` để đăng nhập lại.
