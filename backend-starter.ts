/**
 * DEKA LIVE DASHBOARD - Backend Server
 * Express + TypeScript + WebSocket
 * 
 * Features:
 * - JWT authentication
 * - Real-time metrics via WebSocket
 * - MediaMTX adapter
 * - vMix control
 * - PostgreSQL database
 */

import express, { Express, Request, Response, NextFunction } from 'express';
import { WebSocketServer, WebSocket } from 'ws';
import { createServer } from 'http';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcrypt';
import { Pool } from 'pg';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

// ============================================================================
// TYPES & INTERFACES
// ============================================================================

interface User {
  id: string;
  email: string;
  plan: 'free' | 'pro' | 'enterprise';
}

interface AuthPayload {
  userId: string;
  email: string;
  plan: string;
}

interface Camera {
  id: string;
  userId: string;
  name: string;
  srtUrl: string;
  vmixIndex: number;
  status: 'online' | 'offline';
}

interface StreamMetrics {
  cameraId: string;
  bitrate: number;
  fps: number;
  resolution: string;
  jitter: number;
  packetLoss: number;
  uptime: number;
  timestamp: Date;
}

// ============================================================================
// CONFIG
// ============================================================================

const config = {
  port: parseInt(process.env.PORT || '3000'),
  dbHost: process.env.DB_HOST || 'localhost',
  dbPort: parseInt(process.env.DB_PORT || '5432'),
  dbName: process.env.DB_NAME || 'deka_live',
  dbUser: process.env.DB_USER || 'postgres',
  dbPassword: process.env.DB_PASSWORD || '',
  jwtSecret: process.env.JWT_SECRET || 'dev-secret-change-in-prod',
  mediaStxUrl: process.env.MEDIAMTX_URL || 'http://localhost:9998',
  vmixHost: process.env.VMIX_HOST || 'localhost',
  vmixPort: parseInt(process.env.VMIX_PORT || '8099'),
};

// ============================================================================
// DATABASE
// ============================================================================

const pool = new Pool({
  host: config.dbHost,
  port: config.dbPort,
  database: config.dbName,
  user: config.dbUser,
  password: config.dbPassword,
});

// Init database schema
async function initDatabase() {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        email VARCHAR UNIQUE NOT NULL,
        password_hash VARCHAR NOT NULL,
        plan VARCHAR DEFAULT 'free',
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS cameras (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        name VARCHAR NOT NULL,
        srt_url VARCHAR,
        vmix_index INT,
        status VARCHAR DEFAULT 'offline',
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS streams (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        camera_id UUID REFERENCES cameras(id) ON DELETE CASCADE,
        bitrate_kbps INT,
        fps INT,
        resolution VARCHAR,
        jitter_ms FLOAT,
        packet_loss_pct FLOAT,
        uptime_seconds INT,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE TABLE IF NOT EXISTS alerts (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        camera_id UUID REFERENCES cameras(id) ON DELETE CASCADE,
        alert_type VARCHAR NOT NULL,
        severity VARCHAR,
        message VARCHAR,
        resolved BOOLEAN DEFAULT false,
        created_at TIMESTAMP DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
      CREATE INDEX IF NOT EXISTS idx_cameras_user_id ON cameras(user_id);
      CREATE INDEX IF NOT EXISTS idx_streams_camera_id ON streams(camera_id);
      CREATE INDEX IF NOT EXISTS idx_alerts_camera_id ON alerts(camera_id);
    `);
    console.log('✓ Database initialized');
  } catch (error) {
    console.error('✗ Database init failed:', error);
  }
}

// ============================================================================
// MIDDLEWARE
// ============================================================================

// Auth middleware
function authenticateToken(req: any, res: Response, next: NextFunction) {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'No token' });
  }

  try {
    const decoded = jwt.verify(token, config.jwtSecret) as AuthPayload;
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(403).json({ error: 'Invalid token' });
  }
}

// Error handler
function errorHandler(err: any, req: Request, res: Response, next: NextFunction) {
  console.error('Error:', err);
  res.status(500).json({ error: err.message });
}

// ============================================================================
// SERVICES
// ============================================================================

// MediaMTX Adapter
class MediaMTXAdapter {
  private metricsCache = new Map<string, StreamMetrics>();

  async fetchMetrics(cameraId: string): Promise<StreamMetrics | null> {
    try {
      const response = await fetch(`${config.mediaStxUrl}/metrics`);
      const text = await response.text();

      // Parse Prometheus metrics
      const lines = text.split('\n');
      const metrics = this.parsePrometheusMetrics(lines, cameraId);
      
      if (metrics) {
        this.metricsCache.set(cameraId, metrics);
      }
      
      return metrics;
    } catch (error) {
      console.error('MediaMTX fetch failed:', error);
      return this.metricsCache.get(cameraId) || null;
    }
  }

  private parsePrometheusMetrics(lines: string[], cameraId: string): StreamMetrics | null {
    // Example: Parse bitrate, fps, etc from Prometheus format
    // This is simplified - real implementation would parse actual metrics
    
    return {
      cameraId,
      bitrate: Math.random() * 6000,
      fps: 30,
      resolution: '1920x1080',
      jitter: Math.random() * 50,
      packetLoss: Math.random() * 2,
      uptime: Math.floor(Math.random() * 3600),
      timestamp: new Date(),
    };
  }
}

// vMix API Client
class VmixClient {
  async switchScene(sceneIndex: number): Promise<boolean> {
    try {
      // vMix uses TCP on port 8099
      // Send XML command
      const command = `<Command Function="PreviewInput" Input="${sceneIndex}" />`;
      
      // In production: use TCP socket or HTTP API
      console.log(`vMix command: ${command}`);
      return true;
    } catch (error) {
      console.error('vMix command failed:', error);
      return false;
    }
  }

  async startRecording(): Promise<boolean> {
    try {
      const command = `<Command Function="StartRecording" />`;
      console.log(`vMix command: ${command}`);
      return true;
    } catch (error) {
      console.error('vMix command failed:', error);
      return false;
    }
  }
}

// ============================================================================
// EXPRESS APP
// ============================================================================

const app: Express = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

// Middleware
app.use(cors());
app.use(express.json());

// Initialize services
const mediamtx = new MediaMTXAdapter();
const vmix = new VmixClient();

// ============================================================================
// ROUTES - AUTH
// ============================================================================

app.post('/api/auth/register', async (req: Request, res: Response) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password required' });
  }

  try {
    const hashedPassword = await bcrypt.hash(password, 10);

    const result = await pool.query(
      'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id, email, plan',
      [email, hashedPassword]
    );

    const user = result.rows[0];
    const token = jwt.sign(
      { userId: user.id, email: user.email, plan: user.plan },
      config.jwtSecret,
      { expiresIn: '30d' }
    );

    res.status(201).json({ token, user });
  } catch (error: any) {
    if (error.code === '23505') {
      return res.status(400).json({ error: 'Email already exists' });
    }
    res.status(500).json({ error: 'Registration failed' });
  }
});

app.post('/api/auth/login', async (req: Request, res: Response) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({ error: 'Email and password required' });
  }

  try {
    const result = await pool.query(
      'SELECT * FROM users WHERE email = $1',
      [email]
    );

    const user = result.rows[0];
    if (!user) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { userId: user.id, email: user.email, plan: user.plan },
      config.jwtSecret,
      { expiresIn: '30d' }
    );

    res.json({ token, user: { id: user.id, email: user.email, plan: user.plan } });
  } catch (error) {
    res.status(500).json({ error: 'Login failed' });
  }
});

// ============================================================================
// ROUTES - CAMERAS
// ============================================================================

app.get('/api/cameras', authenticateToken, async (req: any, res: Response) => {
  try {
    const result = await pool.query(
      'SELECT * FROM cameras WHERE user_id = $1',
      [req.user.userId]
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch cameras' });
  }
});

app.post('/api/cameras', authenticateToken, async (req: any, res: Response) => {
  const { name, srtUrl, vmixIndex } = req.body;

  try {
    const result = await pool.query(
      'INSERT INTO cameras (user_id, name, srt_url, vmix_index) VALUES ($1, $2, $3, $4) RETURNING *',
      [req.user.userId, name, srtUrl, vmixIndex]
    );
    res.status(201).json(result.rows[0]);
  } catch (error) {
    res.status(500).json({ error: 'Failed to create camera' });
  }
});

// ============================================================================
// ROUTES - VMIX CONTROL
// ============================================================================

app.post('/api/vmix/scene/:id', authenticateToken, async (req: any, res: Response) => {
  const { id } = req.params;

  try {
    const success = await vmix.switchScene(parseInt(id));
    res.json({ success });
  } catch (error) {
    res.status(500).json({ error: 'vMix command failed' });
  }
});

app.post('/api/vmix/record/start', authenticateToken, async (req: any, res: Response) => {
  try {
    const success = await vmix.startRecording();
    res.json({ success });
  } catch (error) {
    res.status(500).json({ error: 'Recording start failed' });
  }
});

// ============================================================================
// WEBSOCKET - REAL-TIME METRICS
// ============================================================================

interface WSClient {
  ws: WebSocket;
  userId: string;
  cameraIds: Set<string>;
}

const clients = new Set<WSClient>();
const metricsInterval = new Map<string, NodeJS.Timeout>();

wss.on('connection', (ws: WebSocket) => {
  console.log('Client connected');

  ws.on('message', async (data: Buffer) => {
    try {
      const message = JSON.parse(data.toString());

      if (message.type === 'auth') {
        // Verify token
        const decoded = jwt.verify(message.token, config.jwtSecret) as AuthPayload;
        
        const client: WSClient = {
          ws,
          userId: decoded.userId,
          cameraIds: new Set(message.cameraIds || []),
        };

        clients.add(client);

        // Start streaming metrics
        for (const cameraId of client.cameraIds) {
          if (!metricsInterval.has(cameraId)) {
            startMetricsStream(cameraId);
          }
        }

        ws.send(JSON.stringify({ type: 'auth:success' }));
      }
    } catch (error) {
      ws.send(JSON.stringify({ type: 'error', message: 'Auth failed' }));
      ws.close();
    }
  });

  ws.on('close', () => {
    clients.forEach((client) => {
      if (client.ws === ws) {
        clients.delete(client);
      }
    });
    console.log('Client disconnected');
  });
});

async function startMetricsStream(cameraId: string) {
  const interval = setInterval(async () => {
    const metrics = await mediamtx.fetchMetrics(cameraId);

    if (metrics) {
      const message = JSON.stringify({
        type: 'stream:metrics',
        cameraId,
        metrics,
      });

      clients.forEach((client) => {
        if (client.cameraIds.has(cameraId) && client.ws.readyState === WebSocket.OPEN) {
          client.ws.send(message);
        }
      });
    }
  }, 5000); // Update every 5 seconds

  metricsInterval.set(cameraId, interval);
}

// ============================================================================
// ERROR HANDLING & SERVER START
// ============================================================================

app.use(errorHandler);

async function start() {
  try {
    // Initialize database
    await initDatabase();

    // Start server
    server.listen(config.port, () => {
      console.log(`\n🎬 DEKA LIVE DASHBOARD - Backend Running`);
      console.log(`   Server: http://localhost:${config.port}`);
      console.log(`   WebSocket: ws://localhost:${config.port}`);
      console.log(`   Database: ${config.dbName}\n`);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Shutting down...');
  server.close(() => {
    pool.end();
    process.exit(0);
  });
});

start();

export { app, server };
