# 🎬 DEKA LIVE DASHBOARD - Quick Start (10 minutes)

## Prerequisites

```bash
# Install these (or verify you have them)
- Node.js 18+ (node --version)
- Docker (docker --version)
- Docker Compose (docker-compose --version)
- Git (git --version)
```

---

## Step 1: Clone & Setup (2 min)

```bash
# Create project directory
mkdir deka-live-dashboard
cd deka-live-dashboard

# Create folder structure
mkdir -p backend frontend deploy logs

# Copy files from this package:
# - backend-starter.ts → backend/src/index.ts
# - frontend-starter.tsx → frontend/src/App.tsx
# - docker-compose.yml → ./
# - DEKA-LIVE-DASHBOARD-BUILD.md → ./docs/
```

---

## Step 2: Backend Setup (2 min)

```bash
cd backend

# Create package.json
cat > package.json << 'EOF'
{
  "name": "deka-live-backend",
  "version": "1.0.0",
  "main": "src/index.ts",
  "scripts": {
    "dev": "ts-node src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "ws": "^8.14.2",
    "jsonwebtoken": "^9.1.2",
    "bcrypt": "^5.1.1",
    "pg": "^8.11.3",
    "cors": "^2.8.5",
    "dotenv": "^16.3.1"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.6",
    "ts-node": "^10.9.2",
    "typescript": "^5.3.3"
  }
}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

EXPOSE 3000

CMD ["npm", "run", "dev"]
EOF

# Create .env
cat > .env << 'EOF'
PORT=3000
NODE_ENV=development
DB_HOST=postgres
DB_PORT=5432
DB_NAME=deka_live
DB_USER=deka_user
DB_PASSWORD=dev-password-change
JWT_SECRET=dev-secret-change-in-prod
MEDIAMTX_URL=http://mediamtx:9998
VMIX_HOST=localhost
VMIX_PORT=8099
EOF

npm install
cd ..
```

---

## Step 3: Frontend Setup (2 min)

```bash
cd frontend

# Create package.json
cat > package.json << 'EOF'
{
  "name": "deka-live-frontend",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "lucide-react": "^0.309.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.0.7",
    "tailwindcss": "^3.3.6",
    "postcss": "^8.4.32",
    "autoprefixer": "^10.4.16"
  }
}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

FROM nginx:alpine

COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

npm install
cd ..
```

---

## Step 4: Run Locally (3 min)

```bash
# From project root

# Start everything
docker-compose up

# Wait for containers to start
# ✓ postgres healthy
# ✓ backend running on :3000
# ✓ frontend running on :3001
# ✓ mediamtx running on :9998 (optional)

# In another terminal, check health
curl http://localhost:3000/health

# You should see: {"status":"ok"}
```

---

## Step 5: Access the App (1 min)

**Frontend**: http://localhost:3001
**API**: http://localhost:3000/api
**WebSocket**: ws://localhost:3000

---

## Step 6: First-Time Setup

### Create Account

1. Go to http://localhost:3001
2. Click "Sign Up"
3. Enter email: `test@example.com`
4. Enter password: `password123`
5. Click "Sign Up"

### Add Camera

1. After login, click "+ Add Camera"
2. Fill in:
   - **Name**: "Camera 1"
   - **SRT URL**: `srt://localhost:9000` (if using MediaMTX)
   - **vMix Index**: `1`
3. Click "Add"

### Test Stream

If you have vMix:
```bash
# Configure vMix to receive SRT on port 9000
# or use ffmpeg for testing:

ffmpeg -f lavfi -i testsrc=s=1920x1080:d=1 \
  -f lavfi -i sine=f=1000:d=1 \
  -c:v libx264 -b:v 5000k -c:a aac \
  -f mpegts "srt://localhost:9000?mode=caller"
```

---

## 🎯 What's Working

✅ **Authentication**
- Email signup/login
- JWT tokens
- Password hashing

✅ **Cameras**
- Add/remove cameras
- List cameras
- Save vMix indexes

✅ **Real-time Metrics**
- WebSocket connection
- Live bitrate/FPS/resolution
- Jitter and packet loss

✅ **vMix Control**
- Scene switching
- Recording start/stop

✅ **Database**
- PostgreSQL with proper schema
- Migrations applied automatically

---

## 🔧 Development Commands

```bash
# View logs
docker-compose logs -f backend
docker-compose logs -f frontend
docker-compose logs -f postgres

# Restart services
docker-compose restart backend

# Stop everything
docker-compose down

# Remove data (fresh start)
docker-compose down -v

# Execute SQL
docker exec -it deka-postgres psql -U deka_user -d deka_live -c "SELECT * FROM users;"

# Rebuild containers
docker-compose build --no-cache
```

---

## 📊 Default Credentials

```
Email:    test@example.com
Password: password123
Plan:     free (1 camera)
```

---

## ⚠️ Important: Before Production

Change these in `.env`:

```env
# Generate new secrets
JWT_SECRET=<use: node -e "console.log(require('crypto').randomBytes(32).toString('hex'))">
DB_PASSWORD=<strong-password>
NODE_ENV=production
```

---

## 🚀 Next Steps

### 1. Customize

- [ ] Update colors in `frontend/src/App.tsx`
- [ ] Add your logo in header
- [ ] Customize camera names
- [ ] Setup vMix API integration

### 2. Add Features

- [ ] Recording control
- [ ] Stream history
- [ ] Quality alerts
- [ ] Email notifications

### 3. Deploy to GCP

```bash
# Build Docker images
docker build -t gcr.io/app-test-503004/deka-live-backend:latest backend/
docker build -t gcr.io/app-test-503004/deka-live-frontend:latest frontend/

# Push to Container Registry
docker push gcr.io/app-test-503004/deka-live-backend:latest
docker push gcr.io/app-test-503004/deka-live-frontend:latest

# Deploy to Cloud Run (see DEKA-LIVE-DASHBOARD-BUILD.md)
```

### 4. Setup Payments

- [ ] Create Stripe account
- [ ] Add `/api/subscriptions` endpoints
- [ ] Implement tier checks (free vs pro)
- [ ] Add upgrade modal

---

## ❌ Troubleshooting

### Port 3000/3001 already in use

```bash
# Kill existing process
lsof -ti:3000 | xargs kill -9
lsof -ti:3001 | xargs kill -9

# Or use different ports in docker-compose.yml
```

### Database connection fails

```bash
# Check PostgreSQL is healthy
docker exec deka-postgres pg_isready -U deka_user

# Check connection string
# Should be: postgres://deka_user:password@postgres:5432/deka_live
```

### WebSocket connection fails

```bash
# Check backend is running
curl http://localhost:3000/health

# Check browser console for errors
# Should connect to ws://localhost:3000
```

### Camera not showing metrics

```bash
# Check MediaMTX is running
curl http://localhost:9998/metrics | head

# Check camera is configured with correct SRT URL
# Check WebSocket is receiving messages in browser DevTools
```

---

## 📚 File Structure Created

```
deka-live-dashboard/
├── backend/
│   ├── src/
│   │   └── index.ts          (backend-starter.ts)
│   ├── package.json
│   ├── Dockerfile
│   └── .env
├── frontend/
│   ├── src/
│   │   └── App.tsx           (frontend-starter.tsx)
│   ├── package.json
│   ├── Dockerfile
│   └── .env
├── docker-compose.yml
├── mediamtx.yml              (optional)
└── docs/
    └── DEKA-LIVE-DASHBOARD-BUILD.md
```

---

## ✅ Success Checklist

- [ ] Docker containers running
- [ ] Backend server healthy
- [ ] Frontend loads in browser
- [ ] Can create account
- [ ] Can add camera
- [ ] Can see real-time metrics
- [ ] vMix scene switching works

---

## 🎉 Ready to Launch!

Once everything is working locally:

1. **Test with 5 beta users** (friends/KOLs)
2. **Gather feedback** (surveys/interviews)
3. **Fix bugs** (iterate)
4. **Deploy to GCP** (production)
5. **Launch publicly** (marketing)

---

**Time to first working app**: ~15 minutes  
**Time to production MVP**: ~1 week  
**Time to revenue**: ~2 weeks

Good luck! 🚀
