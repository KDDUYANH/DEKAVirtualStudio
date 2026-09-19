/**
 * DEKA LIVE DASHBOARD - Frontend
 * React + TypeScript + Tailwind CSS
 * 
 * Key Features:
 * - Real-time metrics via WebSocket
 * - Multi-camera grid view
 * - vMix scene switching
 * - Dark mode (default)
 * - Responsive design
 */

import React, { useState, useEffect, useRef } from 'react';
import { AlertCircle, Activity, Radio, Settings, LogOut } from 'lucide-react';

// ============================================================================
// TYPES
// ============================================================================

interface User {
  id: string;
  email: string;
  plan: 'free' | 'pro' | 'enterprise';
}

interface Camera {
  id: string;
  name: string;
  vmixIndex: number;
  status: 'online' | 'offline';
}

interface StreamMetrics {
  bitrate: number;
  fps: number;
  resolution: string;
  jitter: number;
  packetLoss: number;
  uptime: number;
  timestamp: Date;
}

interface StreamData {
  [cameraId: string]: StreamMetrics;
}

// ============================================================================
// MAIN APP
// ============================================================================

export const Dashboard: React.FC = () => {
  const [user, setUser] = useState<User | null>(null);
  const [cameras, setCameras] = useState<Camera[]>([]);
  const [metrics, setMetrics] = useState<StreamData>({});
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const tokenRef = useRef<string | null>(localStorage.getItem('token'));

  // ========================================================================
  // WEBSOCKET CONNECTION
  // ========================================================================

  useEffect(() => {
    if (!tokenRef.current) {
      setIsLoading(false);
      return;
    }

    connectWebSocket();
    fetchCameras();
    checkAuth();

    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  const connectWebSocket = () => {
    const wsUrl = `${window.location.origin.replace('http', 'ws')}/ws`;
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      console.log('WebSocket connected');
      
      // Send auth message
      ws.send(JSON.stringify({
        type: 'auth',
        token: tokenRef.current,
        cameraIds: cameras.map(c => c.id),
      }));
    };

    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);

      if (message.type === 'stream:metrics') {
        setMetrics(prev => ({
          ...prev,
          [message.cameraId]: message.metrics,
        }));
      }

      if (message.type === 'error') {
        setError(message.message);
      }
    };

    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
      setError('Connection lost');
    };

    ws.onclose = () => {
      console.log('WebSocket closed');
      // Reconnect after 3 seconds
      setTimeout(() => connectWebSocket(), 3000);
    };

    wsRef.current = ws;
  };

  // ========================================================================
  // API CALLS
  // ========================================================================

  const checkAuth = async () => {
    try {
      const response = await fetch('/api/auth/me', {
        headers: { 'Authorization': `Bearer ${tokenRef.current}` },
      });

      if (response.ok) {
        const userData = await response.json();
        setUser(userData);
      } else {
        localStorage.removeItem('token');
        tokenRef.current = null;
      }
    } catch (err) {
      console.error('Auth check failed:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const fetchCameras = async () => {
    try {
      const response = await fetch('/api/cameras', {
        headers: { 'Authorization': `Bearer ${tokenRef.current}` },
      });

      if (response.ok) {
        const cameraList = await response.json();
        setCameras(cameraList);
      }
    } catch (err) {
      setError('Failed to fetch cameras');
    }
  };

  const switchScene = async (cameraId: string, vmixIndex: number) => {
    try {
      const response = await fetch(`/api/vmix/scene/${vmixIndex}`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${tokenRef.current}` },
      });

      if (!response.ok) {
        setError('Failed to switch scene');
      }
    } catch (err) {
      setError('Scene switch failed');
    }
  };

  const logout = () => {
    localStorage.removeItem('token');
    window.location.href = '/login';
  };

  // ========================================================================
  // RENDER
  // ========================================================================

  if (isLoading) {
    return <LoadingScreen />;
  }

  if (!user) {
    return <LoginForm />;
  }

  const cameraCount = cameras.length;
  const maxCameras = user.plan === 'free' ? 1 : user.plan === 'pro' ? 4 : 999;
  const canAddCamera = cameraCount < maxCameras;

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      {/* Header */}
      <div className="border-b border-gray-800 bg-gray-900/50 backdrop-blur">
        <div className="max-w-7xl mx-auto px-4 py-4 flex justify-between items-center">
          <div className="flex items-center gap-3">
            <div className="text-2xl font-bold">🎬 DEKA LIVE</div>
            <div className="text-xs bg-purple-500/20 text-purple-400 px-2 py-1 rounded">
              {user.plan.toUpperCase()}
            </div>
          </div>

          <div className="flex items-center gap-4">
            <span className="text-sm text-gray-400">{user.email}</span>
            <button onClick={logout} className="text-gray-400 hover:text-white">
              <LogOut size={20} />
            </button>
          </div>
        </div>
      </div>

      {/* Error Banner */}
      {error && (
        <div className="bg-red-950/50 border-b border-red-800 px-4 py-3 flex items-center gap-3">
          <AlertCircle size={20} className="text-red-400" />
          <span className="text-sm">{error}</span>
          <button
            onClick={() => setError(null)}
            className="ml-auto text-xs text-red-400 hover:text-red-300"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Main Content */}
      <div className="max-w-7xl mx-auto px-4 py-8">
        {cameras.length === 0 ? (
          <EmptyState canAddCamera={canAddCamera} plan={user.plan} />
        ) : (
          <>
            {/* Camera Grid */}
            <div className={`grid gap-4 mb-8 ${getGridClass(cameraCount, maxCameras)}`}>
              {cameras.map(camera => (
                <StreamCard
                  key={camera.id}
                  camera={camera}
                  metrics={metrics[camera.id]}
                  onSwitchScene={() => switchScene(camera.id, camera.vmixIndex)}
                />
              ))}
            </div>

            {/* Control Panel */}
            {cameraCount > 0 && <ControlPanel />}
          </>
        )}
      </div>

      {/* Upgrade Modal for Free Users */}
      {user.plan === 'free' && cameraCount === 1 && (
        <UpgradeModal onClose={() => {}} />
      )}
    </div>
  );
};

// ============================================================================
// COMPONENTS
// ============================================================================

interface StreamCardProps {
  camera: Camera;
  metrics?: StreamMetrics;
  onSwitchScene: () => void;
}

const StreamCard: React.FC<StreamCardProps> = ({ camera, metrics, onSwitchScene }) => {
  const isOnline = camera.status === 'online' && metrics;
  const qualityStatus = getQualityStatus(metrics);

  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg overflow-hidden hover:border-gray-700 transition-colors">
      {/* Preview Area */}
      <div className="aspect-video bg-black flex items-center justify-center relative overflow-hidden">
        {isOnline ? (
          <>
            <div className="absolute inset-0 bg-gradient-to-b from-black/0 to-black/50" />
            
            {/* Metrics Overlay */}
            <div className="absolute top-4 right-4 flex gap-2">
              <div className={`px-2 py-1 rounded text-xs font-mono flex items-center gap-1 ${
                qualityStatus.color
              }`}>
                <Radio size={12} className="animate-pulse" />
                {metrics!.bitrate.toFixed(0)} kbps
              </div>
            </div>

            {/* Camera Name */}
            <div className="absolute bottom-4 left-4">
              <h3 className="font-semibold text-lg">{camera.name}</h3>
              <p className="text-xs text-gray-400">
                {metrics!.resolution} @ {metrics!.fps}fps
              </p>
            </div>
          </>
        ) : (
          <div className="text-center text-gray-500">
            <div className="text-4xl mb-2">⚫</div>
            <div className="text-sm">{camera.name}</div>
            <div className="text-xs mt-1">Offline</div>
          </div>
        )}
      </div>

      {/* Control Bar */}
      <div className="bg-gray-800/50 border-t border-gray-700 p-3 flex items-center justify-between">
        <div className="text-xs text-gray-400">
          {isOnline && metrics && (
            <>
              <Activity size={12} className="inline mr-1" />
              {getUptimeString(metrics.uptime)}
            </>
          )}
        </div>

        <button
          onClick={onSwitchScene}
          className="px-3 py-1 bg-purple-600 hover:bg-purple-700 rounded text-xs font-medium transition-colors"
        >
          Switch
        </button>
      </div>

      {/* Quality Indicator */}
      {isOnline && metrics && qualityStatus.warning && (
        <div className={`text-xs p-2 text-center ${qualityStatus.warnBg} ${qualityStatus.warnText}`}>
          ⚠️ {qualityStatus.warning}
        </div>
      )}
    </div>
  );
};

const ControlPanel: React.FC = () => {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded-lg p-6">
      <h2 className="font-semibold mb-4 flex items-center gap-2">
        <Settings size={20} />
        Stream Control
      </h2>

      <div className="grid grid-cols-3 gap-4">
        <button className="bg-red-600 hover:bg-red-700 px-4 py-2 rounded font-medium transition-colors">
          🔴 Start Stream
        </button>
        <button className="bg-gray-700 hover:bg-gray-600 px-4 py-2 rounded font-medium transition-colors">
          ⏹️ Stop
        </button>
        <button className="bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded font-medium transition-colors">
          📹 Record
        </button>
      </div>
    </div>
  );
};

const EmptyState: React.FC<{ canAddCamera: boolean; plan: string }> = ({ canAddCamera, plan }) => {
  return (
    <div className="text-center py-20">
      <div className="text-6xl mb-4">🎬</div>
      <h2 className="text-2xl font-bold mb-2">No Cameras Connected</h2>
      <p className="text-gray-400 mb-6">
        {plan === 'free'
          ? 'Connect your first camera to get started (free tier: 1 camera)'
          : `You can connect up to ${plan === 'pro' ? '4' : 'unlimited'} cameras`}
      </p>

      {canAddCamera && (
        <button className="bg-purple-600 hover:bg-purple-700 px-6 py-3 rounded-lg font-medium">
          + Add Camera
        </button>
      )}

      {!canAddCamera && plan === 'free' && (
        <button className="bg-blue-600 hover:bg-blue-700 px-6 py-3 rounded-lg font-medium">
          Upgrade to Pro
        </button>
      )}
    </div>
  );
};

const UpgradeModal: React.FC<{ onClose: () => void }> = ({ onClose }) => {
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-gray-900 border border-gray-800 rounded-lg p-8 max-w-sm">
        <h2 className="text-2xl font-bold mb-2">Unlock More Cameras</h2>
        <p className="text-gray-400 mb-6">
          Upgrade to Pro to monitor up to 4 cameras simultaneously
        </p>

        <div className="bg-gray-800 p-4 rounded mb-6 text-sm">
          <div className="flex justify-between mb-2">
            <span>Monthly subscription</span>
            <span className="font-bold">$9.99</span>
          </div>
          <div className="text-gray-500 text-xs">Cancel anytime</div>
        </div>

        <button className="w-full bg-purple-600 hover:bg-purple-700 py-2 rounded font-medium mb-2">
          Upgrade to Pro
        </button>
        <button
          onClick={onClose}
          className="w-full bg-gray-800 hover:bg-gray-700 py-2 rounded font-medium"
        >
          Remind Later
        </button>
      </div>
    </div>
  );
};

const LoginForm: React.FC = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isSignup, setIsSignup] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const endpoint = isSignup ? '/api/auth/register' : '/api/auth/login';
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });

      const data = await response.json();

      if (response.ok) {
        localStorage.setItem('token', data.token);
        window.location.reload();
      } else {
        setError(data.error || 'Authentication failed');
      }
    } catch (err) {
      setError('Network error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-950 text-white flex items-center justify-center">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="text-4xl mb-2">🎬</div>
          <h1 className="text-3xl font-bold">DEKA LIVE</h1>
          <p className="text-gray-400">Stream Quality Monitoring</p>
        </div>

        <form onSubmit={handleSubmit} className="bg-gray-900 border border-gray-800 rounded-lg p-6">
          <div className="mb-4">
            <label className="block text-sm font-medium mb-2">Email</label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded px-4 py-2 focus:outline-none focus:border-purple-500"
              required
            />
          </div>

          <div className="mb-6">
            <label className="block text-sm font-medium mb-2">Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded px-4 py-2 focus:outline-none focus:border-purple-500"
              required
            />
          </div>

          {error && <div className="text-red-400 text-sm mb-4">{error}</div>}

          <button
            type="submit"
            disabled={loading}
            className="w-full bg-purple-600 hover:bg-purple-700 disabled:bg-gray-700 py-2 rounded font-medium transition-colors"
          >
            {loading ? 'Loading...' : isSignup ? 'Sign Up' : 'Log In'}
          </button>

          <button
            type="button"
            onClick={() => setIsSignup(!isSignup)}
            className="w-full mt-3 text-gray-400 hover:text-white text-sm"
          >
            {isSignup ? 'Already have an account? Log In' : "Don't have an account? Sign Up"}
          </button>
        </form>
      </div>
    </div>
  );
};

const LoadingScreen: React.FC = () => (
  <div className="min-h-screen bg-gray-950 flex items-center justify-center text-white">
    <div className="text-center">
      <div className="text-6xl mb-4 animate-pulse">🎬</div>
      <p className="text-gray-400">Loading DEKA LIVE...</p>
    </div>
  </div>
);

// ============================================================================
// HELPERS
// ============================================================================

function getGridClass(count: number, max: number): string {
  if (count <= 1) return 'grid-cols-1';
  if (count <= 2) return 'grid-cols-2';
  if (count <= 4) return 'grid-cols-2 lg:grid-cols-4';
  return 'grid-cols-2 lg:grid-cols-3';
}

function getQualityStatus(metrics?: StreamMetrics) {
  if (!metrics) {
    return { color: 'text-gray-500', warning: null, warnBg: '', warnText: '' };
  }

  const bitrateLow = metrics.bitrate < 3000;
  const jitterHigh = metrics.jitter > 100;
  const packetLossHigh = metrics.packetLoss > 2;

  if (packetLossHigh || jitterHigh) {
    return {
      color: 'bg-red-950 text-red-400',
      warning: 'Poor connection',
      warnBg: 'bg-red-950/50 border-b border-red-800',
      warnText: 'text-red-400',
    };
  }

  if (bitrateLow) {
    return {
      color: 'bg-yellow-950 text-yellow-400',
      warning: 'Low bitrate',
      warnBg: 'bg-yellow-950/50 border-b border-yellow-800',
      warnText: 'text-yellow-400',
    };
  }

  return {
    color: 'bg-green-950 text-green-400',
    warning: null,
    warnBg: '',
    warnText: '',
  };
}

function getUptimeString(seconds: number): string {
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);

  if (hours > 0) return `${hours}h ${minutes % 60}m`;
  if (minutes > 0) return `${minutes}m`;
  return `${seconds}s`;
}

export default Dashboard;
