import fs from 'fs';
import path from 'path';
import os from 'os';
import { EngineConfig, PositionId, PositionPreset } from './types.js';
import { DEFAULT_CONFIG } from './defaultPresets.js';

export interface AppPaths {
  root: string;
  app: string;
  config: string;
  layouts: string;
  browserProfile: string;
  cache: string;
  logs: string;
  backups: string;
}

export class PersistenceStore {
  public paths: AppPaths;
  private configFilePath: string;
  private currentConfig: EngineConfig;
  private saveTimeout: NodeJS.Timeout | null = null;

  constructor() {
    const localAppData = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
    const root = path.join(localAppData, 'BackgroundEngine');

    this.paths = {
      root,
      app: path.join(root, 'app'),
      config: path.join(root, 'config'),
      layouts: path.join(root, 'layouts'),
      browserProfile: path.join(root, 'browser profile'),
      cache: path.join(root, 'cache'),
      logs: path.join(root, 'logs'),
      backups: path.join(root, 'backups'),
    };

    this.ensureDirectories();
    this.configFilePath = path.join(this.paths.config, 'settings.json');
    this.currentConfig = this.loadConfig();
  }

  private ensureDirectories(): void {
    for (const p of Object.values(this.paths)) {
      if (!fs.existsSync(p)) {
        fs.mkdirSync(p, { recursive: true });
      }
    }
  }

  public getConfig(): EngineConfig {
    return JSON.parse(JSON.stringify(this.currentConfig));
  }

  public updateConfig(partial: Partial<EngineConfig>): EngineConfig {
    this.currentConfig = {
      ...this.currentConfig,
      ...partial,
    };
    this.scheduleSave();
    return this.getConfig();
  }

  public savePosition(posId: PositionId, preset: PositionPreset): void {
    this.currentConfig.positions[posId] = JSON.parse(JSON.stringify(preset));
    
    // Also save separate preset file in layouts folder for easy backup/sharing
    const presetPath = path.join(this.paths.layouts, `${posId}.json`);
    try {
      fs.writeFileSync(presetPath, JSON.stringify(preset, null, 2), 'utf-8');
    } catch (err) {
      console.error(`[Persistence] Failed to export layout ${posId}:`, err);
    }

    this.scheduleSave();
  }

  private scheduleSave(): void {
    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout);
    }
    this.saveTimeout = setTimeout(() => {
      this.flushSync();
    }, 400); // 400ms debounce
  }

  public flushSync(): void {
    try {
      const data = JSON.stringify(this.currentConfig, null, 2);
      const tmpPath = `${this.configFilePath}.tmp`;
      const bakPath = path.join(this.paths.backups, `settings-${Date.now()}.bak.json`);
      const mainBakPath = `${this.configFilePath}.bak`;

      // 1. Write to temp file
      fs.writeFileSync(tmpPath, data, 'utf-8');

      // 2. Backup previous config if exists
      if (fs.existsSync(this.configFilePath)) {
        try {
          fs.copyFileSync(this.configFilePath, mainBakPath);
          fs.copyFileSync(this.configFilePath, bakPath);
          this.pruneOldBackups();
        } catch {
          // Non-fatal if backup copy fails
        }
      }

      // 3. Atomic rename tmp -> destination
      fs.renameSync(tmpPath, this.configFilePath);
    } catch (err) {
      console.error('[Persistence] Atomic write failed:', err);
    }
  }

  private loadConfig(): EngineConfig {
    if (fs.existsSync(this.configFilePath)) {
      try {
        const raw = fs.readFileSync(this.configFilePath, 'utf-8');
        const parsed = JSON.parse(raw);
        return {
          ...DEFAULT_CONFIG,
          ...parsed,
          appDataPath: this.paths.root,
        };
      } catch (err) {
        console.warn('[Persistence] Main settings file corrupted, attempting recovery from backup:', err);
        const bakPath = `${this.configFilePath}.bak`;
        if (fs.existsSync(bakPath)) {
          try {
            const rawBak = fs.readFileSync(bakPath, 'utf-8');
            const recovered = JSON.parse(rawBak);
            console.log('[Persistence] Successfully restored config from backup!');
            return {
              ...DEFAULT_CONFIG,
              ...recovered,
              appDataPath: this.paths.root,
            };
          } catch {
            console.error('[Persistence] Backup recovery failed, resetting to defaults.');
          }
        }
      }
    }

    // Default init
    const initial: EngineConfig = {
      ...DEFAULT_CONFIG,
      appDataPath: this.paths.root,
    };
    try {
      fs.writeFileSync(this.configFilePath, JSON.stringify(initial, null, 2), 'utf-8');
    } catch (e) {
      console.error('[Persistence] Error writing initial config:', e);
    }
    return initial;
  }

  private pruneOldBackups(): void {
    try {
      const files = fs.readdirSync(this.paths.backups)
        .filter(f => f.endsWith('.bak.json'))
        .map(f => path.join(this.paths.backups, f))
        .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);

      // Keep max 10 backups
      if (files.length > 10) {
        for (let i = 10; i < files.length; i++) {
          fs.unlinkSync(files[i]);
        }
      }
    } catch {
      // Ignore prune errors
    }
  }
}
