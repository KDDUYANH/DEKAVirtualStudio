#!/usr/bin/env bash
set -Eeuo pipefail

APP="/opt/deka-media"
BACKUP="/root/deka-clean-backup-$(date +%Y%m%d-%H%M%S)"

echo "========================================"
echo " DEKA MEDIA SERVER CLEAN INSTALL"
echo "========================================"

if [[ $EUID -ne 0 ]]; then
  echo "Run: sudo bash ~/install-deka-media.sh"
  exit 1
fi

echo "[1/10] Pre-flight"
hostname
cat /etc/os-release | grep -E 'PRETTY_NAME|VERSION_ID'
df -h /
free -h

echo
echo "[2/10] Backup existing configuration"
mkdir -p "$BACKUP"

for p in \
  /opt/deka-media \
  /srv/server \
  /srv/server-backup-20260826-150037
do
  if [[ -e "$p" ]]; then
    echo "Backing up $p"
    tar -czf "$BACKUP/$(basename "$p").tar.gz" "$p" 2>/dev/null || true
  fi
done

docker ps -a > "$BACKUP/docker-ps.txt" 2>/dev/null || true
docker images > "$BACKUP/docker-images.txt" 2>/dev/null || true
docker network ls > "$BACKUP/docker-networks.txt" 2>/dev/null || true
ss -lntup > "$BACKUP/listening-ports.txt" 2>/dev/null || true

echo
echo "[3/10] Stop old Compose projects"

if [[ -f /opt/deka-media/docker-compose.yml ]]; then
  cd /opt/deka-media
  docker compose down --remove-orphans || true
fi

if [[ -f /srv/server/docker-compose.yml ]]; then
  cd /srv/server
  docker compose down --remove-orphans || true
fi

echo
echo "[4/10] Remove old application containers"

for c in \
  deka-dashboard \
  deka-mediamtx \
  deka-portainer \
  deka-uptime \
  deka-filebrowser \
  deka-minio
do
  docker rm -f "$c" 2>/dev/null || true
done

echo
echo "[5/10] Remove old application directories"

rm -rf /opt/deka-media
rm -rf /srv/server

mkdir -p "$APP"/{mediamtx,nginx,dashboard,data,logs}

echo
echo "[6/10] Docker cleanup"

docker image rm \
  bluenviron/mediamtx:1.21.0 \
  bluenviron/mediamtx:latest \
  nginx:alpine \
  portainer/portainer-ce:latest \
  louislam/uptime-kuma:latest \
  filebrowser/filebrowser:latest \
  minio/minio:latest \
  ghcr.io/gethomepage/homepage:latest \
  2>/dev/null || true

docker network prune -f
docker container prune -f
docker image prune -f

echo
echo "[7/10] Create MediaMTX configuration"

cat > "$APP/mediamtx/mediamtx.yml" <<'MTX'
logLevel: info

api: yes
apiAddress: 127.0.0.1:9997

metrics: yes
metricsAddress: 127.0.0.1:9998

rtmp: yes
rtmpAddress: :1935

rtsp: yes
rtspAddress: :8554

webrtc: yes
webrtcAddress: :8889

hls: yes
hlsAddress: :8888

srt: yes
srtAddress: :8890

pathDefaults:
  source: publisher
  overridePublisher: false
  record: no

paths:
  all:
    publishUser: deka
    publishPass: CHANGE_THIS_STREAM_PASSWORD
    readUser: deka
    readPass: CHANGE_THIS_STREAM_PASSWORD
MTX

echo
echo "[8/10] Create minimal dashboard"

cat > "$APP/dashboard/index.html" <<'HTML'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>DEKA Media Server</title>
<style>
body{
  margin:0;
  background:#0b0b0c;
  color:#eee;
  font-family:Arial,sans-serif;
}
main{
  max-width:1100px;
  margin:60px auto;
  padding:24px;
}
h1{font-size:32px;font-weight:500}
.grid{
  display:grid;
  grid-template-columns:repeat(auto-fit,minmax(220px,1fr));
  gap:16px;
}
.card{
  border:1px solid #29292c;
  background:#111113;
  padding:20px;
  border-radius:12px;
}
.label{
  color:#888;
  font-size:12px;
  text-transform:uppercase;
  letter-spacing:1px;
}
.value{
  margin-top:10px;
  font-size:20px;
}
.ok{color:#8fd18f}
</style>
</head>
<body>
<main>
<h1>DEKA Media Server</h1>

<div class="grid">

<div class="card">
<div class="label">Status</div>
<div class="value ok">ONLINE</div>
</div>

<div class="card">
<div class="label">Media Engine</div>
<div class="value">MediaMTX</div>
</div>

<div class="card">
<div class="label">RTMP</div>
<div class="value">1935</div>
</div>

<div class="card">
<div class="label">SRT</div>
<div class="value">8890 UDP</div>
</div>

<div class="card">
<div class="label">WebRTC</div>
<div class="value">8889</div>
</div>

<div class="card">
<div class="label">HLS</div>
<div class="value">8888</div>
</div>

</div>
</main>
</body>
</html>
HTML

echo
echo "[9/10] Create NGINX"

cat > "$APP/nginx/nginx.conf" <<'NGINX'
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy no-referrer always;

    location / {
        try_files $uri $uri/ =404;
    }
}
NGINX

echo
echo "[10/10] Create Docker Compose"

cat > "$APP/docker-compose.yml" <<'COMPOSE'
services:

  mediamtx:
    image: bluenviron/mediamtx:1.21.0
    container_name: deka-mediamtx
    restart: unless-stopped

    ports:
      - "1935:1935/tcp"
      - "8890:8890/udp"
      - "8554:8554/tcp"
      - "8888:8888/tcp"
      - "8889:8889/tcp"
      - "8189:8189/udp"

    volumes:
      - ./mediamtx/mediamtx.yml:/mediamtx.yml:ro
      - ./data:/data

    security_opt:
      - no-new-privileges:true

    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  dashboard:
    image: nginx:alpine
    container_name: deka-dashboard
    restart: unless-stopped

    ports:
      - "80:80/tcp"

    volumes:
      - ./nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./dashboard:/usr/share/nginx/html:ro

    security_opt:
      - no-new-privileges:true

    logging:
      driver: json-file
      options:
        max-size: "5m"
        max-file: "3"
COMPOSE

cd "$APP"

docker compose pull
docker compose up -d

echo
echo "========================================"
echo " INSTALL COMPLETE"
echo "========================================"

docker compose ps

echo
echo "Listening ports:"
ss -lntup | grep -E ':(80|1935|8554|8888|8889|8890)\b' || true

echo
echo "Disk:"
df -h /

echo
echo "Docker:"
docker system df

echo
echo "Backup:"
echo "$BACKUP"

echo
echo "IMPORTANT:"
echo "Change CHANGE_THIS_STREAM_PASSWORD in:"
echo "$APP/mediamtx/mediamtx.yml"
echo
echo "Then:"
echo "cd $APP && docker compose restart mediamtx"
