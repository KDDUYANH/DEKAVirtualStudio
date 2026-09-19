# Checklist triển khai production

## Build & phát hành
- [ ] CI xanh: `backend` + `ios` (test Simulator) + device build **không có warning trong source của app**
- [ ] 10 bài test trong DEVICE_TESTING.md đều PASS trên **ít nhất 2 đời iPhone** (ví dụ A15 và A17 Pro/A18)
- [ ] PERFORMANCE_REPORT.md đã điền số đo thật
- [ ] Ký bằng Apple Developer Program, phát qua TestFlight (hoặc Enterprise/ABM nếu nội bộ)
- [ ] Tăng `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, gắn tag Git

## Bảo mật
- [ ] `MILLICAST_API_SECRET` chỉ nằm trong Worker secrets. Chạy `git log -p | grep -i secret` không ra kết quả
- [ ] `SESSION_SIGNING_KEY` ≥ 32 byte ngẫu nhiên, mỗi môi trường một key
- [ ] Mỗi iPhone / người vận hành có operator key riêng. Thu hồi bằng cách xoá khỏi `OPERATORS`
- [ ] `ALLOWED_STREAM_PATTERN` chặt nhất có thể (không dùng `.*`)
- [ ] `PUBLISH_TOKEN_TTL_SECONDS` vừa đủ cho một show
- [ ] Bật rate limiting / WAF của Cloudflare cho `/v1/session`
- [ ] Không dùng developer token cho show thật (SYSTEM CHECK không báo WARN ở dòng Dolby)
- [ ] Dashboard Dolby: bật giới hạn domain/geo cho viewer nếu cần, và secure viewer (subscribe token) cho nội dung trả phí

## Vận hành
- [ ] SYSTEM CHECK toàn PASS trước mỗi show
- [ ] Nguồn: sạc qua cổng USB-C có pass-through, hoặc pin dự phòng
- [ ] Tản nhiệt: tháo ốp, dùng quạt hoặc tản nhiệt kẹp máy nếu chạy 1080p60 + AI
- [ ] Mạng: Wi-Fi 5 GHz riêng, hoặc Ethernet qua adapter USB-C. Upload ≥ 2× bitrate
- [ ] Bật chế độ Không làm phiền / Focus (cuộc gọi đến sẽ làm dừng camera)
- [ ] Ghi PROGRAM song song làm bản lưu dự phòng
- [ ] Mở link viewer trên một thiết bị khác để giám sát
- [ ] Sau show: STOP (token bị thu hồi), kiểm tra file ghi, xuất project làm bản lưu

## Giám sát
- [ ] Lấy log Worker (`wrangler tail`) cho các lỗi 401/502
- [ ] Theo dõi usage và billing trên dashboard Dolby
