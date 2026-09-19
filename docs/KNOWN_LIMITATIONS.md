# Giới hạn đã biết

## Giới hạn của iOS

* **Chạy nền:** iOS dừng camera khi app vào nền hoặc khi có cuộc gọi đến. Stream sẽ reconnect khi app quay lại. Hãy bật Focus / Do Not Disturb khi làm show.
* **Nhiệt:** iPhone không có quạt. Chạy 1080p60 + AI + nền video trong thời gian dài sẽ làm máy nóng. Đó là lý do có hệ thống hạ cấp theo thứ tự. Tháo ốp, dùng quạt hoặc tản nhiệt kẹp máy sẽ kéo dài thời gian chạy ở chất lượng cao.
* **Chế độ camera phụ thuộc máy:** 4K60, 1080p60 trên camera trước, hay các ống kính khác nhau không có trên mọi iPhone. App chỉ hiện những chế độ mà máy thật sự hỗ trợ.
* **Bluetooth mic:** dùng profile HFP (16 kHz, băng hẹp). Nên dùng mic USB-C hoặc Lightning để có tiếng tốt.
* **Vision person segmentation:** là model tổng quát, viền tóc kém hơn phông xanh thật. Model này không đảm bảo 60 fps trên mọi chip.
* **Không kiểm soát được kênh thông tin phụ của H.264:** WebRTC tự quản lý keyframe interval, profile và level.

## Giới hạn của phiên bản này (0.9.0)

* **Chưa build, chưa test trên thiết bị** (xem README). Có thể còn lỗi biên dịch nhỏ do không có Xcode khi viết. Workflow CI sẽ chỉ ra chính xác từng lỗi.
* **Audio tuỳ chỉnh (`MCCustomAudioSource`):** trong issue #22 của `millicast-native-sdk` từng có người báo không có tiếng khi dùng custom audio với SDK cũ. Code đã theo đúng API 2.6 (frame Int16 10 ms), nhưng cần xác nhận ở bài test 10. Nếu vẫn lỗi, phương án dự phòng là dùng `MCMedia.getAudioSources()` (mic do SDK quản lý). Khi đó chuỗi gain/compressor/limiter của app sẽ không áp dụng lên tiếng stream.
* **Bitrate Opus** không đặt được qua MillicastSDK 2.6. Bitrate audio do SDK tự quản lý.
* **Xoay:** chỉ hỗ trợ ngang (landscape). Cầm dọc thì hướng xoay cuối cùng được giữ nguyên.
* **Chế độ ghi CAMERA:** ghi buffer gốc của sensor. Khi cầm ngang trái, file dùng cờ transform thay vì render lại.
* **Mask AI khi mới bật:** vài frame đầu hiện camera không key (không bao giờ hiện hình rác) cho tới khi có mask đầu tiên.
* **Đổi độ phân giải hoặc fps khi đang live** (kể cả khi hệ thống nhiệt tự hạ 60→30) làm camera cấu hình lại, gây gián đoạn khoảng vài trăm ms. Stream vẫn giữ kết nối.
* **Core ML model riêng** (`PersonSegmentation.mlmodelc`) không được đóng gói sẵn. Nếu thêm vào bundle, app sẽ tự dùng model đó thay cho Vision.
* **Import/Export project** dùng một file JSON có nhúng asset (base64). Project nhiều video nền sẽ cho ra file lớn.
* **Deprecation:** một số API AVAudioSession có thể được đổi tên trong SDK iOS mới hơn (ví dụ `.allowBluetooth`). Nếu Xcode báo warning, đổi sang tên mới mà Xcode gợi ý.
