# HƯỚNG DẪN CÀI ĐẶT & YÊU CẦU HỆ THỐNG (README-INSTALL)

## 1. Yêu Cầu Phần Cứng & Hệ Điều Hành

* **Hệ điều hành**: Windows 10 (64-bit) hoặc Windows 11 (64-bit).
* **CPU**: Intel Core i5 / AMD Ryzen 5 thế hệ 8 trở lên (khuyến nghị 4 cores trở lên).
* **RAM**: Tối thiểu 8 GB (khuyến nghị 16 GB).
* **GPU**: Hỗ trợ DirectX 11 / OpenGL 3.3+ (NVIDIA GeForce GTX 1050 trở lên hoặc Intel Iris Xe).
* **Mạng**: Cổng mạng Gigabit LAN (1000 Mbps) để truyền luồng NDI High Bandwidth không trễ.

---

## 2. Các Runtime Bắt Buộc (Prerequisites)

1. **Microsoft .NET 9 Desktop Runtime (x64)**:
   - Thường đã có sẵn trên Windows 11 hoặc cài qua link chính thức của Microsoft:
   - [Tải .NET 9 Runtime (x64)](https://dotnet.microsoft.com/en-us/download/dotnet/9.0)
2. **NDI 6 Runtime hoặc NDI Tools**:
   - Để vMix và OBS nhận luồng NDI chất lượng cao:
   - [Tải NDI 6 Core Runtime](https://ndi.video/tools/)
   - *Lưu ý: Nếu chưa cài NDI Runtime, phần mềm tự động kích hoạt chế độ Fallback qua cổng HTTP `http://127.0.0.1:7800/output` để vMix vẫn nhận được qua Browser Input.*
3. **Microsoft Edge WebView2 Runtime**:
   - Đã được tích hợp sẵn trên tất cả các bản Windows 10/11 cập nhật mới.

---

## 3. Các Cách Cài Đặt Ứng Dụng

### Cách 1: Sử Dụng Bộ Cài Đặt (Khuyến nghị cho Studio)
1. Tải về file **`BackgroundEngine-Setup.exe`**.
2. Nhấp đúp chuột để chạy file cài đặt.
3. Chọn thư mục cài đặt mong muốn (mặc định: `%LOCALAPPDATA%\Programs\BackgroundEngine`).
4. Chọn tạo biểu tượng Desktop và Start Menu.
5. Bấm **Install** và hoàn tất.

### Cách 2: Chạy Bản Di Động (Portable Version)
1. Tải về file **`BackgroundEngine-Portable.zip`**.
2. Giải nén vào bất kỳ thư mục nào (VD: `D:\DEKA\BackgroundEngine`).
3. Chạy file **`BackgroundEngine.exe`** để sử dụng ngay mà không cần cài đặt. Toàn bộ cấu hình sẽ được lưu an toàn tại `%LOCALAPPDATA%\BackgroundEngine`.

---

## 4. Kiểm Tra Tương Thích vMix & OBS

### vMix
* Hỗ trợ tất cả các phiên bản vMix 24, 25, 26, 27 có kích hoạt tính năng NDI.
* Vào **Settings** → **Performance** → Đảm bảo đã bật tăng tốc phần cứng GPU.

### OBS Studio
* OBS Studio 30+ hoặc 31+.
* Cài đặt plugin **DistroAV (OBS-NDI)**: [Tải DistroAV cho OBS](https://obsproject.com/forum/resources/distroav-network-audio-video-in-obs-studio-using-ndi%C2%AE-technology.528/).
