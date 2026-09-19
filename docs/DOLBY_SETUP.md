# Thiết lập Dolby OptiView Real-time Streaming (Millicast)

> Millicast hiện nằm trong **Dolby OptiView**. Tài liệu chính thức: optiview.dolby.com/docs/millicast

## 1. Tài khoản & API secret

1. Đăng ký hoặc đăng nhập Dolby OptiView Streaming dashboard.
2. Vào **Settings → Security → API Secret**. Đây là secret dùng để tạo publish token. **Tuyệt đối không đưa secret này vào app.**
3. Ghi lại **Account ID**. ID này dùng cho link viewer.

## 2. Deploy token service (Cloudflare Worker, gói miễn phí)

```bash
cd backend/token-service
npm test                                  # 4 test (JWT, session, publish token, revoke)
npx wrangler login
npx wrangler secret put MILLICAST_API_SECRET        # dán API secret
openssl rand -base64 48 | npx wrangler secret put SESSION_SIGNING_KEY
```

Tạo operator key cho từng iPhone hoặc từng người vận hành:

```bash
KEY=$(openssl rand -base64 24); echo "Operator key (đưa cho người vận hành): $KEY"
HASH=$(printf %s "$KEY" | shasum -a 256 | cut -d' ' -f1)
echo "{\"cam1\":\"$HASH\"}" | npx wrangler secret put OPERATORS
npx wrangler deploy        # → https://deka-token.<ten>.workers.dev
```

Worker chỉ lưu **hash** của operator key. Stream name được phép publish do `ALLOWED_STREAM_PATTERN` trong `wrangler.toml` quy định (mặc định `deka-.*`).

Kiểm tra: `curl https://deka-token.<ten>.workers.dev/v1/health` → `{"ok":true}`

## 3. Cấu hình app

1. Trong `Config/Local.xcconfig`: `DEKA_TOKEN_SERVICE_URL = https:/$()/deka-token.<ten>.workers.dev`, sau đó build lại.
2. Trong app, mở **OUT → DOLBY MILLICAST**:
   * Stream name: ví dụ `deka-studio-a` (phải khớp với `ALLOWED_STREAM_PATTERN`)
   * Operator ID `cam1` + operator key → **SIGN IN**. Key được lưu trong Keychain, dùng để đổi lấy session 12 giờ.
3. **SYS → RUN SYSTEM CHECK**: dòng `Dolby` phải là `PASS — token service reachable · operator session valid`.

### Thử nhanh khi chưa có backend (chỉ để dev)

**OUT → DEVELOPER TOKEN**: dán một publishing token tạo trên dashboard cùng stream name. Token được lưu trong Keychain. App chỉ dùng token này khi **không** cấu hình token service. Không dùng cách này cho show thật, vì token trên dashboard thường sống lâu.

## 4. Phát & xem

1. Bấm **GO LIVE**. Trạng thái chuyển lần lượt `AUTHORIZING → CONNECTING → LIVE`.
2. Người xem mở:
   `https://viewer.millicast.com/?streamId=<AccountID>/<StreamName>`
3. Đối chiếu với telemetry của app: bitrate, RTT, loss, jitter và số viewer đều lấy từ WebRTC stats thật.
4. Bấm **STOP** → publish token bị thu hồi (`DELETE /v1/publish-token/:id`).

## 5. Thông số khuyến nghị

| Preset | Mode | Video |
|---|---|---|
| MOBILE | 1080p30 | 3–5 Mbps (bắt đầu từ 4) |
| BROADCAST | 1080p60 | 5–8 Mbps (bắt đầu từ 6.5) |
| LOW BANDWIDTH | 720p30 | 1.5–2.5 Mbps |

Audio: Opus 48 kHz. MillicastSDK 2.6 không có tuỳ chọn đặt bitrate Opus (`MCClientOptions` không có trường này), nên bitrate audio do SDK tự quản lý. Giá trị audio trong preset hiện chỉ để tham khảo.

Codec: H.264 (encoder phần cứng VideoToolbox, qua WebRTC). Với 60 fps, app đặt `degradationPreference = maintainFrameRate`. Khi băng thông giảm, encoder hạ độ phân giải trước để giữ chuyển động mượt.
