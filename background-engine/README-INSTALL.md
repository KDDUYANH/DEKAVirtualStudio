# HƯỚNG DẪN CÀI ĐẶT 1-CLICK & YÊU CẦU HỆ THỐNG (README-INSTALL)

## 1. Thông Tin File Cài Đặt 1-Click (Release Artifacts)

| Tên File | Dung Lượng | Kiểu Đóng Gói | Mô Tả |
| :--- | :--- | :--- | :--- |
| [**BackgroundEngine-Setup.exe**](file:///e:/OneDrive/DEKA/Th%C6%B0%20mu%CC%A3c%20m%C6%A1%CC%81i/release/BackgroundEngine-Setup.exe) | **~257 MB** | **NSIS 1-Click Installer** | Bộ cài đặt tự động 1-click đầy đủ: tự động tạo shortcut Desktop, Start Menu và chạy ngay không cần cấu hình phức tạp |
| [**Background Engine-1.0.0-win.zip**](file:///e:/OneDrive/DEKA/Th%C6%B0%20mu%CC%A3c%20m%C6%A1%CC%81i/release/Background%20Engine-1.0.0-win.zip) | **~306 MB** | **Portable Standalone** | Gói zip chạy trực tiếp, không cần quyền Admin, giải nén là chạy |
| [**SHA256SUMS.txt**](file:///e:/OneDrive/DEKA/Th%C6%B0%20mu%CC%A3c%20m%C6%A1%CC%81i/release/SHA256SUMS.txt) | **< 1 KB** | **Checksums** | Bảng mã băm SHA256 xác thực toàn vẹn gói cài đặt |

### Mã Kiểm Tra Toàn Vẹn SHA256
```text
2A2D9D163A9A0C4E0D8E723618650FD5BB5853F58AD803441A593A2359961EA3 *BackgroundEngine-Setup.exe
5A8D90D81B16C1ED466D6628AD4C79C01090FFA60CB3D8546CB0BC88FB987D06 *Background Engine-1.0.0-win.zip
```

---

## 2. Cách Cài Đặt 1-Click (Dành Cho Kỹ Thuật Viên / Vận Hành)

### Cách 1: Cài Đặt 1-Click Siêu Tốc (Khuyến nghị)
1. Nhấp đúp chuột vào file [**BackgroundEngine-Setup.exe**](file:///e:/OneDrive/DEKA/Th%C6%B0%20mu%CC%A3c%20m%C6%A1%CC%81i/release/BackgroundEngine-Setup.exe).
2. Trình cài đặt NSIS 1-Click sẽ tự động:
   - Giải nén mã nguồn Engine & Runtime vào thư mục chuẩn Windows (`%LOCALAPPDATA%\Programs\BackgroundEngine`).
   - Tích hợp sẵn `NdiBridge.exe` (.NET 9 x64) và Named Pipe Server cho NDI High Bandwidth.
   - Tạo biểu tượng lối tắt (Desktop Shortcut) có biểu tượng nhận diện.
   - Tự động thêm vào Start Menu.
   - Tự động khởi chạy ứng dụng ngay sau khi cài xong.

### Cách 2: Bản Portable Di Động
1. Giải nén [**Background Engine-1.0.0-win.zip**](file:///e:/OneDrive/DEKA/Th%C6%B0%20mu%CC%A3c%20m%C6%A1%CC%81i/release/Background%20Engine-1.0.0-win.zip) vào bất kỳ ổ đĩa nào (Ví dụ: `D:\DEKA\BackgroundEngine`).
2. Mở thư mục đã giải nén và nhấp đúp **`Background Engine.exe`** để chạy ngay lập tức mà không cần cài đặt.

---

## 3. Yêu Cầu Phần Cứng & Môi Trường Vận Hành

* **Hệ điều hành**: Windows 10 (64-bit) hoặc Windows 11 (64-bit).
* **CPU**: Intel Core i5 / AMD Ryzen 5 thế hệ 8 trở lên (khuyến nghị 4-8 cores).
* **RAM**: Tối thiểu 8 GB (khuyến nghị 16 GB).
* **GPU**: Hỗ trợ DirectX 11 / OpenGL 3.3+ (NVIDIA GeForce GTX 1050 trở lên hoặc Intel Iris Xe).
* **Mạng**: Cổng mạng Gigabit LAN (1000 Mbps) để truyền luồng NDI High Bandwidth độ trễ siêu thấp đến vMix / OBS.
* **NDI Runtime (Tùy chọn)**: Đã tích hợp sẵn NdiBridge, khuyến nghị cài thêm [NDI 6 Tools](https://ndi.video/tools/) nếu vMix/OBS nằm trên máy trạm khác qua mạng LAN.

---

## 4. Kết Nối Nhanh Với vMix & OBS

### Kết nối với vMix:
1. Mở **vMix** → Bấm **Add Input** (Góc dưới bên trái).
2. Chọn tab **NDI / Desktop Capture**.
3. Chọn nguồn **`BackgroundEngine-PGM`**.
4. Bấm **OK**. Màn hình Program 1080p60 sẽ hiển thị ngay lập tức với độ trễ cực thấp (< 5ms).

### Kết nối với OBS Studio:
1. Đảm bảo đã cài plugin **DistroAV (OBS-NDI)**.
2. Mở OBS → Trong hộp **Sources**, bấm dấu **+** → Chọn **NDI™ Source**.
3. Tại trường **Source name**, chọn **`BackgroundEngine-PGM`**.
4. Bấm **OK**.
