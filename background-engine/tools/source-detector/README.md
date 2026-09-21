# DEKA SOURCE DETECTOR — STANDALONE COMPANION TOOL

## Giới thiệu
Công cụ hỗ trợ kỹ thuật viên mổ xẻ, phân tích cấu trúc DOM, phát hiện WebSocket và đánh giá đề xuất tích hợp nguồn trực tiếp mà **hoàn toàn độc lập với Background Engine**.

Điều này giúp **Background Engine chính tập trung 100% tài nguyên vào phát sóng 1080p60 NDI mượt mà**, cho phép người vận hành thao tác trực tiếp trên trình duyệt thay vì phải trải qua các bước quét phức tạp.

## Cách sử dụng
```bash
# Quét bất kỳ website nào
npm run detect https://play.example.com/
```
Output sẽ hiển thị:
- Phân loại `<video>`, `<canvas>`, `WebGL`.
- Danh sách endpoint `WebSocket` mang dữ liệu Game State hoặc Chat.
- Khuyến nghị chiến lược: `KEEP_BROWSER` hay `EXTRACT_DATA`.
