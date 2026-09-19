# 🎬 DEKA LIVE DASHBOARD - Complete Build Package

## 📦 PROJECT STRUCTURE

```
deka-live-dashboard/
├── README.md
├── package.json
├── docker-compose.yml
├── .env.example
│
├── backend/
│   ├── src/
│   │   ├── index.ts              # Express + WebSocket server
│   │   ├── config/
│   │   │   ├── env.ts
│   │   │   └── database.ts
│   │   ├── routes/
│   │   │   ├── auth.ts           # Login/signup/JWT
│   │   │   ├── cameras.ts        # Camera CRUD
│   │   │   ├── streams.ts        # Stream metrics
│   │   │   ├── vimix.ts          # vMix control
│   │   │   └── subscriptions.ts  # Stripe payments
│   │   ├── services/
│   │   │   ├── mediamtx.ts       # MediaMTX adapter
│   │   │   ├── vmix.ts           # vMix API client
│   │   │   ├── auth.ts           # JWT + OAuth
│   │   │   ├── stripe.ts         # Payment processing
│   │   │   └── websocket.ts      # Real-time updates
│   │   ├── models/
│   │   │   ├── User.ts
│   │   │   ├── Camera.ts
│   │   │   ├── Stream.ts
│   │   │   ├── Subscription.ts
│   │   │   └── Alert.ts
│   │   ├── middleware/
│   │   │   ├── auth.ts
│   │   │   ├── errorHandler.ts
│   │   │   └── rateLimit.ts
│   │   └── types/
│   │       └── index.ts
│   ├── migrations/
│   │   └── init.sql
│   └── Dockerfile
│
├── frontend/
│   ├── src/
│   │   ├── App.tsx
│   │   ├── index.css             # Tailwind + custom
│   │   ├── pages/
│   │   │   ├── Login.tsx
│   │   │   ├── Dashboard.tsx
│   │   │   ├── CameraDetail.tsx
│   │   │   ├── Settings.tsx
│   │   │   ├── History.tsx
│   │   │   └── Pricing.tsx
│   │   ├── components/
│   │   │   ├── StreamCard.tsx
│   │   │   ├── MetricsGrid.tsx
│   │   │   ├── ControlPanel.tsx
│   │   │   ├── AlertCenter.tsx
│   │   │   ├── CameraForm.tsx
│   │   │   └── PaymentModal.tsx
│   │   ├── hooks/
│   │   │   ├── useWebSocket.ts
│   │   │   ├── useAuth.ts
│   │   │   ├── useStripe.ts
│   │   │   └── useLocalStorage.ts
│   │   ├── services/
│   │   │   ├── api.ts            # Fetch wrapper
│   │   │   ├── auth.ts
│   │   │   └── stripe.ts
│   │   ├── store/
│   │   │   ├── store.ts          # Zustand state
│   │   │   ├── slices/
│   │   │   │   ├── auth.ts
│   │   │   │   ├── cameras.ts
│   │   │   │   ├── streams.ts
│   │   │   │   └── ui.ts
│   │   └── types/
│   │       └── index.ts
│   ├── package.json
│   └── Dockerfile
│
├── deploy/
│   ├── gcp-setup.sh              # Cloud Run + SQL setup
│   ├── docker-compose.yml        # Local dev
│   └── kubernetes/
│       ├── deployment.yaml
│       └── service.yaml
│
└── docs/
    ├── API.md                    # API documentation
    ├── ARCHITECTURE.md
    ├── DEPLOYMENT.md
    └── DEVELOPMENT.md

```

---

## 🚀 PHASE 1 MVP - TECHNICAL SPECS

### **Backend (Node.js + Express + TypeScript)**

**Key Endpoints:**
```
AUTH
  POST   /auth/register          - Email signup
  POST   /auth/login             - Email login
  POST   /auth/oauth             - Google OAuth
  POST   /auth/logout            - Logout
  GET    /auth/me                - Current user

CAMERAS
  GET    /cameras                - List user's cameras
  POST   /cameras                - Add camera
  GET    /cameras/:id            - Get camera details
  PUT    /cameras/:id            - Update camera
  DELETE /cameras/:id            - Delete camera

STREAMS (Real-time via WebSocket)
  WS     /ws/streams             - Subscribe to metrics
    └─ Events:
       - stream:online
       - stream:quality
       - stream:alert
       - stream:offline

VMIX CONTROL
  POST   /vimix/connect          - Connect to vMix
  POST   /vimix/scene/:id        - Switch scene
  POST   /vimix/record/start     - Start recording
  POST   /vimix/record/stop      - Stop recording

SUBSCRIPTIONS
  GET    /subscriptions/current   - User's plan
  POST   /subscriptions/upgrade   - Upgrade plan (Stripe)
  POST   /webhooks/stripe         - Webhook handler
```

**Database Schema:**
```sql
-- Users
CREATE TABLE users (
  id UUID PRIMARY KEY,
  email VARCHAR UNIQUE,
  password_hash VARCHAR,
  google_id VARCHAR,
  plan ENUM ('free', 'pro', 'enterprise'),
  created_at TIMESTAMP
);

-- Cameras
CREATE TABLE cameras (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users,
  name VARCHAR,
  srt_url VARCHAR,
  vmix_index INT,
  status ENUM ('online', 'offline'),
  created_at TIMESTAMP
);

-- Streams (metrics)
CREATE TABLE streams (
  id UUID PRIMARY KEY,
  camera_id UUID REFERENCES cameras,
  bitrate_kbps INT,
  fps INT,
  resolution VARCHAR,
  jitter_ms FLOAT,
  packet_loss_pct FLOAT,
  uptime_seconds INT,
  recorded BOOLEAN,
  created_at TIMESTAMP
);

-- Alerts
CREATE TABLE alerts (
  id UUID PRIMARY KEY,
  camera_id UUID REFERENCES cameras,
  alert_type VARCHAR,
  severity ENUM ('info', 'warning', 'critical'),
  message VARCHAR,
  resolved BOOLEAN,
  created_at TIMESTAMP
);

-- Subscriptions
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users,
  plan VARCHAR,
  stripe_id VARCHAR,
  status VARCHAR,
  next_billing_date DATE,
  created_at TIMESTAMP
);
```

### **Frontend (React + TypeScript + Tailwind)**

**Key Features:**
- Real-time metrics via WebSocket
- Responsive grid layout (1-4 cameras)
- Dark mode (default for streamers)
- Keyboard shortcuts (space to toggle, arrow keys to switch)
- One-click vMix scene switching
- Quality alerts (red banner)
- Subscription upsell (modal)

**UI States:**
```
LOADING
├─ Skeleton screens
└─ Pulsing indicators

EMPTY
├─ No cameras connected
├─ First-time setup wizard
└─ "Add Camera" CTA

STREAMING
├─ Live metrics
├─ Control panel active
└─ Alert indicator

OFFLINE
├─ Last metrics shown (faded)
├─ "Reconnect" button
└─ Offline indicator
```

### **Infrastructure (GCP)**

**Services Used:**
```
Cloud Run          - Backend + Frontend (containers)
Cloud SQL          - PostgreSQL database
Cloud Storage      - Stream recordings (optional Phase 2)
Cloud Pub/Sub      - Real-time event streaming
Cloud Load Balancer - Public endpoint + SSL
Secret Manager     - API keys, passwords
Cloud Logging      - Application logs
Cloud Monitoring   - Performance metrics
```

**Deployment:**
```bash
# Build Docker images
docker build -t gcr.io/app-test-503004/deka-live-backend:latest backend/
docker build -t gcr.io/app-test-503004/deka-live-frontend:latest frontend/

# Push to Container Registry
docker push gcr.io/app-test-503004/deka-live-backend:latest
docker push gcr.io/app-test-503004/deka-live-frontend:latest

# Deploy to Cloud Run
gcloud run deploy deka-live-backend \
  --image=gcr.io/app-test-503004/deka-live-backend:latest \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated

gcloud run deploy deka-live-frontend \
  --image=gcr.io/app-test-503004/deka-live-frontend:latest \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated

# Setup Cloud SQL
gcloud sql instances create deka-live-db \
  --database-version=POSTGRES_15 \
  --tier=db-f1-micro \
  --region=us-central1
```

---

## 🔌 INTEGRATIONS

### **MediaMTX Adapter**
```typescript
// Fetch metrics from MediaMTX Prometheus endpoint
interface StreamMetrics {
  bitrate: number;        // kbps
  fps: number;
  resolution: string;     // "1920x1080"
  jitter: number;         // ms
  packetLoss: number;     // percentage
  uptime: number;         // seconds
  timestamp: Date;
}

// Poll every 5 seconds
// Cache in Redis for 10 seconds
// Broadcast via WebSocket to clients
```

### **vMix API Integration**
```typescript
// vMix TCP port 8099 (XML)
interface VmixCommand {
  command: 'SetOutputList' | 'Function' | 'PreviewInput' | 'StartRecording';
  param?: string;
}

// Example: Switch to scene "Camera 1"
const switchScene = (sceneIndex: number) => {
  return `<Command Function="PreviewInput" Input="1" />`
}

// Rate limit: 1 request per second
// Queue for reliability
```

### **Stripe Integration**
```typescript
// Node: stripe package
// Events:
//   - payment_intent.succeeded
//   - customer.subscription.updated
//   - invoice.payment_succeeded

// Webhook signature verification
// Auto-upgrade user tier on success
```

---

## 📊 DEVELOPMENT TIMELINE

```
WEEK 1 (MVP)
├─ Day 1: Project setup + database
├─ Day 2: Auth (login/signup)
├─ Day 3: Camera CRUD + MediaMTX adapter
├─ Day 4: Dashboard UI + WebSocket
├─ Day 5: vMix integration + alerts
└─ Result: Working beta (1 camera, free tier)

WEEK 2 (Iteration)
├─ Day 1: Multi-camera support
├─ Day 2: Advanced metrics + history
├─ Day 3: Stripe integration
├─ Day 4: Mobile responsive
└─ Day 5: Beta testing + fixes

WEEK 3 (Polish)
├─ Day 1: Dark mode + keyboard shortcuts
├─ Day 2: Performance optimization
├─ Day 3: Error handling + edge cases
├─ Day 4: Documentation
└─ Day 5: Launch preparation

Launch: End of week 3
First 100 beta users: Week 1-2
```

---

## 💡 TECH STACK RATIONALE

| Component | Choice | Why |
|-----------|--------|-----|
| Backend | Node.js + Express | Fast to build, real-time with WebSocket |
| Language | TypeScript | Catch errors early, better IDE support |
| Frontend | React | Component-based, great ecosystem |
| Styling | Tailwind CSS | Fast to build, minimal CSS knowledge |
| State | Zustand | Simple, no boilerplate vs Redux |
| Real-time | WebSocket | Low latency (<100ms) |
| Database | PostgreSQL | Robust, JSONB for flexibility |
| Hosting | GCP Cloud Run | Serverless, scales automatically |
| Payments | Stripe | Industry standard, webhook support |
| Storage | Google Cloud Storage | Integrated with GCP, CDN ready |

---

## 🎯 SUCCESS CRITERIA (Phase 1)

```
Technical
✓ <500ms dashboard update latency
✓ Support 4 concurrent streams
✓ 99.9% uptime
✓ <5 second MediaMTX reconnect

Product
✓ 100+ beta signups in week 1
✓ 30+ active users by end week 2
✓ 10% convert to Pro tier
✓ NPS > 40

Business
✓ $0 COGS (free tier testing)
✓ First $100 MRR by week 3
✓ Social proof (feedback from KOLs)
✓ Ready for public launch
```

---

## 📝 NEXT STEPS

1. **Setup local dev environment**
   ```bash
   git clone <repo>
   cp .env.example .env
   docker-compose up
   npm install
   npm run dev
   ```

2. **Deploy to GCP**
   ```bash
   bash deploy/gcp-setup.sh
   ```

3. **Beta test with 5 users**
   - Gather feedback
   - Fix bugs
   - Iterate

4. **Launch publicly**
   - Share on TikTok (@DEKA)
   - Reach out to KOL network
   - Launch Product Hunt
   - First-month free offer

---

## 🔐 SECURITY CHECKLIST

- [ ] HTTPS only (Cloud Load Balancer)
- [ ] JWT tokens (30min expiry)
- [ ] Rate limiting (50req/min per IP)
- [ ] SQL injection prevention (prepared statements)
- [ ] CORS configured (frontend only)
- [ ] Secrets in Secret Manager
- [ ] Audit logging (all API calls)
- [ ] 2FA optional (for Pro users)
- [ ] Data encryption at rest (Cloud SQL)
- [ ] Data encryption in transit (TLS 1.3)

---

## 💰 COST ESTIMATE

```
GCP (prod)
├─ Cloud Run (backend)      ~$20/month
├─ Cloud SQL (db)           ~$10/month
├─ Load Balancer            ~$18/month
├─ Storage                  ~$5/month
└─ Total                    ~$53/month

Service Fees
├─ Stripe (2.9% + $0.30)    Variable
└─ Domain                   ~$12/year

Monthly burn: ~$60
Break-even: 10 paying users @ $9.99/month

ROI Analysis
├─ 100 free users (week 1)
├─ 10% conversion (10 Pro users)
├─ 10 × $9.99 = ~$100 MRR
├─ Profit after costs: ~$40/month
├─ Scale to 100 users: $1000 MRR
└─ Full profit: $940/month
```

---

## 📞 QUESTIONS BEFORE STARTING

1. **vMix integration**: Do you have vMix running? (for testing)
2. **MediaMTX setup**: Using the infrastructure from Phase 1?
3. **Deployment**: GCP Cloud Run or your own server?
4. **Timeline**: Can you commit 3 weeks to this?
5. **Testing**: Will you beta test with your KOL network?

---

**Status**: ✅ Ready to build  
**Complexity**: Medium  
**Time to MVP**: 1 week  
**Time to launch**: 3 weeks

🚀 **Ready to start coding?**
