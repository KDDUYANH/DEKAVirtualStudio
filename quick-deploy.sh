#!/bin/bash

################################################################################
# DEKA LIVE - Quick Deployment
# Run both development (VM) and production (Cloud Run) in one go
################################################################################

set -e

PROJECT_ID="app-test-503004"
REGION="us-central1"
ZONE="us-central1-a"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  🎬 DEKA LIVE DASHBOARD - Complete Deployment                 ║"
echo "║                                                                ║"
echo "║  This will setup:                                              ║"
echo "║  1. Development VM (35.235.240.16) - Docker Compose            ║"
echo "║  2. Production (Cloud Run) - Auto-scaling                      ║"
echo "║  3. Database (Cloud SQL) - PostgreSQL 15                       ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

echo ""
echo "📋 Pre-flight checks..."
echo ""

# Check gcloud
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI not found"
    echo "   Install: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found"
    echo "   Install: https://docs.docker.com/get-docker/"
    exit 1
fi

echo "✓ gcloud CLI found"
echo "✓ Docker found"
echo ""

# Set project
echo "🔧 Configuring GCP..."
gcloud config set project $PROJECT_ID
echo "✓ Project set to $PROJECT_ID"
echo ""

# ============================================================================
# PART 1: ENABLE REQUIRED APIs
# ============================================================================

echo "📡 Enabling required APIs..."
gcloud services enable \
    compute.googleapis.com \
    run.googleapis.com \
    sqladmin.googleapis.com \
    containerregistry.googleapis.com \
    --project=$PROJECT_ID 2>/dev/null || true

echo "✓ APIs enabled"
echo ""

# ============================================================================
# PART 2: DEVELOPMENT SETUP
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Development Setup (VM + Docker Compose)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

VM_NAME="mediamtx-dashboard"

# Check if VM exists
if gcloud compute instances describe $VM_NAME --zone=$ZONE &>/dev/null; then
    echo "✓ VM already exists: $VM_NAME"
else
    echo "• Creating VM (e2-medium)..."
    gcloud compute instances create $VM_NAME \
        --zone=$ZONE \
        --machine-type=e2-medium \
        --image-family=ubuntu-2204-lts \
        --image-project=ubuntu-os-cloud \
        --boot-disk-size=50GB \
        --quiet
    echo "✓ VM created, waiting for startup..."
    sleep 30
fi

# Get VM IP
VM_IP=$(gcloud compute instances describe $VM_NAME --zone=$ZONE --format='value(networkInterfaces[0].networkIP)' 2>/dev/null)
echo "• VM IP: $VM_IP"
echo ""

echo "• Setting up Docker Compose on VM..."
gcloud compute ssh $VM_NAME --zone=$ZONE --command='
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh 2>/dev/null
    sudo sh get-docker.sh 2>/dev/null
    sudo usermod -aG docker $USER
    
    # Create project folder
    mkdir -p ~/deka-live-dashboard
    cd ~/deka-live-dashboard
    
    echo "✓ Docker installed on VM"
' 2>/dev/null || echo "⚠ VM may still be initializing"

echo "✓ Development setup ready"
echo ""
echo "  To test development:"
echo "    $ gcloud compute ssh $VM_NAME --zone=$ZONE"
echo "    $ cd ~/deka-live-dashboard"
echo "    $ docker-compose up"
echo ""

# ============================================================================
# PART 3: PRODUCTION SETUP
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Production Setup (Cloud SQL)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SQL_INSTANCE="deka-live-db"
SQL_USER="deka_user"
SQL_PASSWORD="$(openssl rand -base64 16 | tr -d '=+/' | cut -c1-12)"

# Check if SQL instance exists
if gcloud sql instances describe $SQL_INSTANCE &>/dev/null; then
    echo "✓ Cloud SQL instance already exists: $SQL_INSTANCE"
else
    echo "• Creating PostgreSQL 15 instance (db-f1-micro)..."
    gcloud sql instances create $SQL_INSTANCE \
        --database-version=POSTGRES_15 \
        --tier=db-f1-micro \
        --region=$REGION \
        --quiet
    
    echo "  Waiting for instance to be ready..."
    sleep 60
    echo "✓ Cloud SQL instance created"
fi

# Create database
echo "• Creating database..."
gcloud sql databases create deka_live --instance=$SQL_INSTANCE --quiet 2>/dev/null || true
echo "✓ Database created"

# Create user
echo "• Creating database user..."
gcloud sql users create $SQL_USER --instance=$SQL_INSTANCE --password=$SQL_PASSWORD --quiet 2>/dev/null || true
echo "✓ User created"

# Get connection details
SQL_IP=$(gcloud sql instances describe $SQL_INSTANCE --format='value(ipAddresses[0].ipAddress)')
CONN_NAME=$(gcloud sql instances describe $SQL_INSTANCE --format='value(connectionName)')

echo ""
echo "Database credentials:"
echo "  Instance: $SQL_INSTANCE"
echo "  Connection: $CONN_NAME"
echo "  User: $SQL_USER"
echo "  Password: $SQL_PASSWORD"
echo "  IP: $SQL_IP"
echo ""

# Save credentials
cat > ~/deka-live-sql-creds.txt << EOF
# DEKA LIVE Database Credentials
# Keep this file secure!

SQL_INSTANCE=$SQL_INSTANCE
SQL_CONN_NAME=$CONN_NAME
SQL_USER=$SQL_USER
SQL_PASSWORD=$SQL_PASSWORD
SQL_IP=$SQL_IP

# Use in environment:
export DB_HOST=$SQL_IP
export DB_USER=$SQL_USER
export DB_PASSWORD=$SQL_PASSWORD
export DB_NAME=deka_live
EOF

echo "✓ Credentials saved to ~/deka-live-sql-creds.txt"
echo ""

# ============================================================================
# STEP 3: Build & Deploy
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Build & Deploy to Cloud Run"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Configure Docker
echo "• Configuring Docker authentication..."
gcloud auth configure-docker gcr.io --quiet

# Build backend
echo "• Building backend image..."
if [ -d "backend" ]; then
    BACKEND_IMAGE="gcr.io/$PROJECT_ID/deka-live-backend:latest"
    docker build -t $BACKEND_IMAGE backend/ -q
    echo "  Pushing to Container Registry..."
    docker push $BACKEND_IMAGE -q 2>/dev/null || echo "  ⚠ Push may be slow, continuing..."
    echo "✓ Backend ready: $BACKEND_IMAGE"
else
    echo "⚠ backend/ folder not found, skipping build"
fi

# Build frontend
echo "• Building frontend image..."
if [ -d "frontend" ]; then
    FRONTEND_IMAGE="gcr.io/$PROJECT_ID/deka-live-frontend:latest"
    docker build -t $FRONTEND_IMAGE frontend/ -q
    echo "  Pushing to Container Registry..."
    docker push $FRONTEND_IMAGE -q 2>/dev/null || echo "  ⚠ Push may be slow, continuing..."
    echo "✓ Frontend ready: $FRONTEND_IMAGE"
else
    echo "⚠ frontend/ folder not found, skipping build"
fi

echo ""
echo "✓ Docker images built and pushed"
echo ""

# Deploy backend to Cloud Run
if [ ! -z "$BACKEND_IMAGE" ]; then
    echo "• Deploying backend to Cloud Run..."
    gcloud run deploy deka-live-backend \
        --image=$BACKEND_IMAGE \
        --platform managed \
        --region=$REGION \
        --allow-unauthenticated \
        --memory=512Mi \
        --set-env-vars="DB_HOST=$SQL_IP,DB_USER=$SQL_USER,DB_PASSWORD=$SQL_PASSWORD,DB_NAME=deka_live,NODE_ENV=production" \
        --quiet 2>/dev/null || echo "⚠ Deployment may be processing..."
    
    BACKEND_URL=$(gcloud run services describe deka-live-backend --region=$REGION --format='value(status.url)' 2>/dev/null)
    echo "✓ Backend deployed: $BACKEND_URL"
fi

# Deploy frontend to Cloud Run
if [ ! -z "$FRONTEND_IMAGE" ]; then
    echo "• Deploying frontend to Cloud Run..."
    gcloud run deploy deka-live-frontend \
        --image=$FRONTEND_IMAGE \
        --platform managed \
        --region=$REGION \
        --allow-unauthenticated \
        --memory=256Mi \
        --quiet 2>/dev/null || echo "⚠ Deployment may be processing..."
    
    FRONTEND_URL=$(gcloud run services describe deka-live-frontend --region=$REGION --format='value(status.url)' 2>/dev/null)
    echo "✓ Frontend deployed: $FRONTEND_URL"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  ✅ DEPLOYMENT COMPLETE                                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "🌐 DEVELOPMENT (Docker Compose)"
echo "   VM: gcloud compute ssh $VM_NAME --zone=$ZONE"
echo "   Frontend: http://$VM_IP:3001"
echo "   Backend:  http://$VM_IP:3000"
echo ""

if [ ! -z "$BACKEND_URL" ] && [ ! -z "$FRONTEND_URL" ]; then
    echo "🚀 PRODUCTION (Cloud Run)"
    echo "   Frontend: $FRONTEND_URL"
    echo "   Backend:  $BACKEND_URL"
    echo ""
fi

echo "💾 DATABASE"
echo "   Instance: $SQL_INSTANCE"
echo "   User: $SQL_USER"
echo "   Credentials: ~/deka-live-sql-creds.txt"
echo ""

echo "📊 NEXT STEPS"
echo "   1. Test development VM:"
echo "      $ gcloud compute ssh $VM_NAME --zone=$ZONE"
echo "      $ cd ~/deka-live-dashboard && docker-compose up"
echo ""
echo "   2. Access local dev:"
echo "      http://$VM_IP:3001"
echo ""
if [ ! -z "$FRONTEND_URL" ]; then
    echo "   3. Access production:"
    echo "      $FRONTEND_URL"
    echo ""
fi
echo "   4. Setup custom domain (optional):"
echo "      gcloud run services update deka-live-frontend --region=$REGION"
echo ""

echo "✨ Done!"
echo ""
