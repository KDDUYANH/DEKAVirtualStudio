# 🚀 Deploy DEKA LIVE - Both Development & Production

**Complete setup in one command**

---

## 📋 What Gets Deployed

### Development (VM)
```
Compute Engine: e2-medium Ubuntu 22.04
Docker Compose: Backend + Frontend + PostgreSQL
Access: http://YOUR_VM_IP:3001 (dev)
Purpose: Test & iterate before production
```

### Production (Cloud Run)
```
Backend Service: Containerized Node.js
Frontend Service: Containerized React
Database: Cloud SQL PostgreSQL 15 (managed)
Access: Public URLs with auto-scaling
Purpose: Production-ready deployment
```

---

## 🎯 One-Command Deploy

### From GCP Cloud Shell:

```bash
# 1. Clone this repo or create folder
mkdir -p ~/deka-live-deployment
cd ~/deka-live-deployment

# 2. Download deployment script
# (Copy quick-deploy.sh from /mnt/user-data/outputs/)
wget https://your-repo/quick-deploy.sh
chmod +x quick-deploy.sh

# 3. Run (handles everything automatically)
./quick-deploy.sh
```

---

## 📝 Manual Step-by-Step (If Preferred)

### Step 1: Setup GCP

```bash
# Set project
gcloud config set project app-test-503004

# Enable APIs
gcloud services enable \
    compute.googleapis.com \
    run.googleapis.com \
    sqladmin.googleapis.com \
    containerregistry.googleapis.com
```

### Step 2: Create Development VM

```bash
# Create VM
gcloud compute instances create mediamtx-dashboard \
    --zone=us-central1-a \
    --machine-type=e2-medium \
    --image-family=ubuntu-2204-lts \
    --image-project=ubuntu-os-cloud \
    --boot-disk-size=50GB

# SSH and install Docker
gcloud compute ssh mediamtx-dashboard --zone=us-central1-a

# On the VM:
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Setup project
mkdir -p ~/deka-live-dashboard
cd ~/deka-live-dashboard
# Copy docker-compose.yml here
docker-compose up
```

### Step 3: Setup Production Database

```bash
# Create Cloud SQL instance
gcloud sql instances create deka-live-db \
    --database-version=POSTGRES_15 \
    --tier=db-f1-micro \
    --region=us-central1

# Create database
gcloud sql databases create deka_live \
    --instance=deka-live-db

# Create user
gcloud sql users create deka_user \
    --instance=deka-live-db \
    --password=YOUR_SECURE_PASSWORD

# Get IP
gcloud sql instances describe deka-live-db \
    --format='value(ipAddresses[0].ipAddress)'
```

### Step 4: Build & Deploy Docker Images

```bash
# Configure Docker auth
gcloud auth configure-docker gcr.io

# Build backend
docker build -t gcr.io/app-test-503004/deka-live-backend:latest backend/
docker push gcr.io/app-test-503004/deka-live-backend:latest

# Build frontend
docker build -t gcr.io/app-test-503004/deka-live-frontend:latest frontend/
docker push gcr.io/app-test-503004/deka-live-frontend:latest

# Deploy backend
gcloud run deploy deka-live-backend \
    --image=gcr.io/app-test-503004/deka-live-backend:latest \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --memory=512Mi \
    --set-env-vars="DB_HOST=CLOUD_SQL_IP,DB_USER=deka_user,DB_PASSWORD=YOUR_PASSWORD,DB_NAME=deka_live"

# Deploy frontend
gcloud run deploy deka-live-frontend \
    --image=gcr.io/app-test-503004/deka-live-frontend:latest \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --memory=256Mi
```

---

## 🧪 Testing After Deploy

### Test Development (VM)

```bash
# SSH to VM
gcloud compute ssh mediamtx-dashboard --zone=us-central1-a

# Check services
docker-compose ps

# View logs
docker-compose logs -f backend

# Access frontend
# http://VM_IP:3001
```

### Test Production (Cloud Run)

```bash
# List deployed services
gcloud run services list --platform managed

# Get service URLs
gcloud run services describe deka-live-backend --region us-central1 --format='value(status.url)'
gcloud run services describe deka-live-frontend --region us-central1 --format='value(status.url)'

# View logs
gcloud run services logs read deka-live-backend --limit 50

# Test API
curl https://[BACKEND_URL]/health
```

---

## 📊 Architecture After Deploy

```
┌─────────────────────────────────────────────────────────────┐
│                    User Traffic                              │
└──────────────┬──────────────────────────┬────────────────────┘
               │                          │
         DEVELOPMENT                   PRODUCTION
               │                          │
     ┌─────────▼────────┐        ┌────────▼─────────────────┐
     │   Compute Engine │        │  Cloud Run Services      │
     │   (e2-medium)    │        │  ├─ Frontend (React)     │
     │                  │        │  └─ Backend (Node.js)    │
     │  Docker Compose  │        └────────┬─────────────────┘
     │  ├─ Backend      │                 │
     │  ├─ Frontend     │                 │
     │  └─ PostgreSQL   │                 │
     │                  │                 │
     └──────────────────┘        ┌────────▼─────────────────┐
                                 │   Cloud SQL Database     │
                                 │   (PostgreSQL 15)        │
                                 └──────────────────────────┘
```

---

## 🔑 Important Credentials

Save these somewhere secure:

```bash
# Database
DB_HOST=<CLOUD_SQL_IP>
DB_USER=deka_user
DB_PASSWORD=<YOUR_PASSWORD>
DB_NAME=deka_live

# JWT Secret
JWT_SECRET=<GENERATE_NEW>

# Container Registry Images
gcr.io/app-test-503004/deka-live-backend:latest
gcr.io/app-test-503004/deka-live-frontend:latest
```

---

## 📈 Monitoring

### Check Development Status

```bash
# SSH to VM
gcloud compute ssh mediamtx-dashboard --zone=us-central1-a

# Check Docker Compose
docker-compose ps
docker-compose logs
docker stats

# Check resources
free -h
df -h
```

### Check Production Status

```bash
# Cloud Run logs
gcloud run services logs read deka-live-backend --limit 100
gcloud run services logs read deka-live-frontend --limit 100

# Cloud SQL status
gcloud sql instances describe deka-live-db

# Check metrics
gcloud monitoring time-series list --filter='metric.type="run.googleapis.com/request_count"'
```

---

## 💰 Cost Estimate

```
Development (VM):
  - Compute Engine e2-medium: ~$25/month
  - Storage: ~$2/month
  ───────────────────────────
  Total: ~$27/month

Production (Cloud Run):
  - Backend service: ~$20/month (varies with traffic)
  - Frontend service: ~$10/month (varies with traffic)
  - Cloud SQL: ~$10/month
  - Networking: ~$5/month
  ───────────────────────────
  Total: ~$45/month (scales with users)

TOTAL: ~$72/month for both
```

---

## 🔒 Security Checklist

Before going public:

- [ ] Change JWT_SECRET to new random value
- [ ] Change DB_PASSWORD to strong password
- [ ] Setup HTTPS on Cloud Run (automatic)
- [ ] Enable audit logging
- [ ] Setup Cloud Armor (DDoS protection)
- [ ] Enable VPC connector for Cloud SQL
- [ ] Backup Cloud SQL daily
- [ ] Setup monitoring & alerts

---

## 🚨 Troubleshooting

### VM not responding

```bash
# Check VM status
gcloud compute instances describe mediamtx-dashboard --zone=us-central1-a

# Restart VM
gcloud compute instances stop mediamtx-dashboard --zone=us-central1-a
gcloud compute instances start mediamtx-dashboard --zone=us-central1-a

# Check VM startup script
gcloud compute instances describe mediamtx-dashboard --zone=us-central1-a --format='value(metadata.items[serial-port-output].value)'
```

### Cloud Run service failing

```bash
# Check logs
gcloud run services logs read deka-live-backend --limit 50

# Check environment variables
gcloud run services describe deka-live-backend --region us-central1

# Restart service (redeploy)
gcloud run deploy deka-live-backend \
    --image=gcr.io/app-test-503004/deka-live-backend:latest \
    --region us-central1
```

### Database connection failed

```bash
# Check SQL instance
gcloud sql instances describe deka-live-db

# Get IP
gcloud sql instances describe deka-live-db \
    --format='value(ipAddresses[0].ipAddress)'

# Test connection from Cloud Run (requires IAM setup)
# For now, use public IP but restrict firewall
```

---

## ✅ Success Checklist

- [ ] Script downloaded and marked executable
- [ ] Running from GCP Cloud Shell
- [ ] VM created and running
- [ ] Docker Compose working on VM
- [ ] Can access dev at http://VM_IP:3001
- [ ] Cloud SQL instance ready
- [ ] Docker images built and pushed
- [ ] Cloud Run services deployed
- [ ] Frontend URL accessible
- [ ] Backend health check passing
- [ ] Database connected
- [ ] Create account + add camera works

---

## 🎉 You're Done!

Both development and production are now running:

**Development**: Quick iteration on VM  
**Production**: Scaled deployment on Cloud Run  
**Database**: Managed PostgreSQL on Cloud SQL

Time to beta test with your KOL network! 🚀

---

*Last updated: 2026-09-19*  
*Script version: 1.0*
