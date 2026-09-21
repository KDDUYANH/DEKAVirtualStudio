# HƯỚNG DẪN XỬ LÝ SỰ CỐ & KHẮC PHỤC NHANH (TROUBLESHOOTING)

Tài liệu này hướng dẫn cách chẩn đoán và khắc phục nhanh chóng các vấn đề phát sinh trong quá trình vận hành 24/7 của Background Engine.

---

## 1. Vấn Đề Về Luồng NDI Output

### Triệu chứng 1: vMix hoặc OBS không nhìn thấy luồng `BackgroundEngine-PGM`
* **Nguyên nhân**:
  1. Máy tính chưa cài NDI Core Runtime (file `Processing.NDI.Lib.x64.dll`).
  2. Windows Firewall đang chặn cổng NDI (mạng được đặt là Public thay vì Private).
* **Cách khắc phục**:
  1. Tải và cài đặt [NDI 6 Core Runtime](https://ndi.video/tools/).
  2. Mở **Windows Defender Firewall** → Đảm bảo cho phép `NdiBridge.exe` và `BackgroundEngine.exe` giao tiếp trên Private Network.
  3. Kiểm tra đèn báo trên giao diện Preview: Phải hiển thị `● NDI READY`. Nếu hiển thị `NDI FALLBACK`, hãy cài NDI Runtime và khởi động lại ứng dụng.
  4. *Giải pháp tạm thời*: Nhập link `http://127.0.0.1:7800/output` vào mục **Web Browser Input** của vMix để phát sóng ngay lập tức.

### Triệu chứng 2: NDI bị giật lag hoặc rớt khung hình (Dropped Frames)
* **Nguyên nhân**: Băng thông mạng LAN bị quá tải hoặc kết nối qua Wifi thay vì dây mạng.
* **Cách khắc phục**:
  1. NDI High Bandwidth yêu cầu tối thiểu cáp mạng Cat5e/Cat6 Gigabit (1000 Mbps). Tuyệt đối không truyền NDI 1080p60 qua mạng Wifi.
  2. Tắt các ứng dụng tải file ngầm (Torrent, OneDrive sync tải nặng).

---

## 2. Vấn Đề Về Nguồn Game & Đăng Nhập

### Triệu chứng: Luồng Game hiển thị thẻ `"NGUỒN LIVE ĐANG KẾT NỐI LẠI"`
* **Nguyên nhân**: Mạng internet tới máy chủ Sunwin bị chập chờn, hoặc tài khoản bị đăng xuất/hết hạn phiên.
* **Cách khắc phục**:
  1. Kiểm tra mục **AUTH STATUS** trên thanh tiêu đề Preview. Nếu báo `LOGIN REQUIRED`, nhấn `[ OPEN LOGIN ]` để đăng nhập lại.
  2. Nếu tài khoản vẫn bình thường: Bấm nút **`Phục Hồi Game`** trên bảng điều khiển để kích hoạt lại luồng mà không làm gián đoạn chương trình.
  3. Hệ thống sẽ tự động thử lại 5 lần (1s, 2s, 5s, 10s, 20s). Nếu sau 5 lần vẫn lỗi, kiểm tra lại kết nối internet của máy tính.

---

## 3. Vấn Đề Về Bố Cục & Auto Move

### Triệu chứng: Auto Move bị đứng hoặc không chuyển vị trí
* **Cách khắc phục**:
  1. Kiểm tra trạng thái tại ô Auto Move: Nếu đang ở `PAUSED` hoặc `STOPPED`, bấm `▶ START`.
  2. Đảm bảo ô `LOOP (P1 → P2 → P3 → P1)` đã được tích chọn.
  3. Có thể bấm `⏭ NEXT` để ép chuyển sang vị trí tiếp theo ngay lập tức.

---

## 4. Vị Trí Lưu Trữ Log & Khôi Phục File Cấu Hình

Nếu cần gửi log chẩn đoán cho đội ngũ kỹ thuật:
* Thư mục cấu hình & log: `%LOCALAPPDATA%\BackgroundEngine\`
  - `logs/`: Chứa file nhật ký hoạt động.
  - `config/settings.json`: Cấu hình hiện tại.
  - `backups/`: Các bản sao lưu cấu hình tự động (`.bak.json`). Nếu cấu hình bị lỗi, chỉ cần đổi tên file `.bak` mới nhất thành `settings.json`.
