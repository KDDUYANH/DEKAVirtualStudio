import { EventEmitter } from 'events';
import { spawn, ChildProcess } from 'child_process';
import path from 'path';
import net from 'net';
import fs from 'fs';

export interface NdiTelemetry {
  state: 'READY' | 'STARTING' | 'FALLBACK_ACTIVE' | 'FAILED' | 'STOPPED';
  streamName: string;
  fps: number;
  receivers: number;
  ndiLoaded: boolean;
  message?: string;
  warning?: string;
}

export class NdiController extends EventEmitter {
  private bridgeProcess: ChildProcess | null = null;
  private pipeSocket: net.Socket | null = null;
  private streamName: string;
  private pipeName = '\\\\.\\pipe\\BackgroundEngine_NdiPipe';
  private telemetry: NdiTelemetry;
  private isShuttingDown = false;
  private reconnectPipeTimeout: NodeJS.Timeout | null = null;

  constructor(streamName: string = 'BackgroundEngine-PGM') {
    super();
    this.streamName = streamName;
    this.telemetry = {
      state: 'STARTING',
      streamName,
      fps: 0,
      receivers: 0,
      ndiLoaded: false,
    };
  }

  public getTelemetry(): NdiTelemetry {
    return { ...this.telemetry };
  }

  public start(): void {
    this.isShuttingDown = false;
    this.spawnBridge();
    this.connectPipe();
  }

  private findBridgeExecutable(): { cmd: string; args: string[] } {
    // 1. Check published release bin
    const publishedExe = path.join(process.cwd(), 'bin', 'ndi', 'NdiBridge.exe');
    if (fs.existsSync(publishedExe)) {
      return { cmd: publishedExe, args: ['--stream', this.streamName] };
    }

    // 2. Check debug build
    const debugExe = path.join(process.cwd(), 'src', 'ndi', 'bin', 'Debug', 'net9.0-windows', 'NdiBridge.exe');
    if (fs.existsSync(debugExe)) {
      return { cmd: debugExe, args: ['--stream', this.streamName] };
    }

    // 3. Fallback to dotnet run
    const projectPath = path.join(process.cwd(), 'src', 'ndi', 'NdiBridge.csproj');
    return {
      cmd: 'dotnet',
      args: ['run', '--project', projectPath, '--', '--stream', this.streamName],
    };
  }

  private spawnBridge(): void {
    const target = this.findBridgeExecutable();
    console.log(`[NdiController] Spawning NdiBridge via: ${target.cmd} ${target.args.join(' ')}`);

    try {
      this.bridgeProcess = spawn(target.cmd, target.args, {
        stdio: ['pipe', 'pipe', 'pipe'],
        windowsHide: true,
      });

      this.bridgeProcess.stdout?.on('data', (chunk: Buffer) => {
        const lines = chunk.toString('utf-8').split('\n');
        for (const line of lines) {
          if (!line.trim().startsWith('{')) continue;
          try {
            const data = JSON.parse(line.trim());
            this.handleBridgeMessage(data);
          } catch {
            // Ignore non-JSON line
          }
        }
      });

      this.bridgeProcess.stderr?.on('data', (errChunk: Buffer) => {
        console.warn(`[NdiBridge Stderr]: ${errChunk.toString('utf-8').trim()}`);
      });

      this.bridgeProcess.on('close', (code) => {
        console.log(`[NdiController] NdiBridge exited with code ${code}`);
        this.bridgeProcess = null;
        if (!this.isShuttingDown) {
          this.telemetry.state = 'STOPPED';
          this.emit('telemetry-updated', this.telemetry);
          setTimeout(() => this.spawnBridge(), 3000);
        }
      });
    } catch (err) {
      console.error('[NdiController] Failed to spawn NdiBridge:', err);
      this.telemetry.state = 'FAILED';
      this.telemetry.warning = 'Failed to launch NDI bridge process.';
      this.emit('telemetry-updated', this.telemetry);
    }
  }

  private handleBridgeMessage(msg: any): void {
    if (msg.type === 'runtime') {
      this.telemetry.ndiLoaded = Boolean(msg.loaded);
      if (!msg.loaded) {
        this.telemetry.state = 'FALLBACK_ACTIVE';
        this.telemetry.warning = msg.message;
      }
    } else if (msg.type === 'status') {
      if (msg.state) this.telemetry.state = msg.state;
      if (msg.warning) this.telemetry.warning = msg.warning;
    } else if (msg.type === 'telemetry') {
      this.telemetry.fps = msg.fps || 0;
      this.telemetry.receivers = msg.receivers || 0;
      this.telemetry.ndiLoaded = Boolean(msg.ndiLoaded);
      this.emit('telemetry-updated', this.telemetry);
    }
  }

  private connectPipe(): void {
    if (this.isShuttingDown) return;

    this.pipeSocket = net.connect(this.pipeName, () => {
      console.log('[NdiController] Connected to NdiBridge high-speed video pipe.');
    });

    this.pipeSocket.on('error', () => {
      // Named pipe server might not be ready yet, retry in 1s
      this.schedulePipeReconnect();
    });

    this.pipeSocket.on('close', () => {
      this.pipeSocket = null;
      this.schedulePipeReconnect();
    });
  }

  private schedulePipeReconnect(): void {
    if (this.isShuttingDown || this.reconnectPipeTimeout) return;
    this.reconnectPipeTimeout = setTimeout(() => {
      this.reconnectPipeTimeout = null;
      this.connectPipe();
    }, 1500);
  }

  public sendFrame(bgraBuffer: Buffer): boolean {
    if (this.pipeSocket && !this.pipeSocket.destroyed && this.pipeSocket.writable) {
      // Backpressure protection: Drop frame if pipe buffer is saturated (> 2 frames backlog)
      // Broadcast rule: Never queue stale frames; prioritize lowest real-time latency.
      if (this.pipeSocket.writableLength > 8294400 * 2) {
        return false;
      }
      return this.pipeSocket.write(bgraBuffer);
    }
    return false;
  }

  public stop(): void {
    this.isShuttingDown = true;
    if (this.reconnectPipeTimeout) {
      clearTimeout(this.reconnectPipeTimeout);
      this.reconnectPipeTimeout = null;
    }
    if (this.pipeSocket) {
      this.pipeSocket.destroy();
      this.pipeSocket = null;
    }
    if (this.bridgeProcess) {
      this.bridgeProcess.kill();
      this.bridgeProcess = null;
    }
    this.telemetry.state = 'STOPPED';
  }
}
