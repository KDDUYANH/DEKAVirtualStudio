import path from 'path';
import dotenv from 'dotenv';

dotenv.config();

const rootDir = typeof __dirname !== 'undefined'
  ? path.resolve(__dirname, '..')
  : path.resolve(process.cwd());

export const CONFIG = {
  PORT: parseInt(process.env.PORT || '3030', 10),
  HOST: process.env.HOST || '0.0.0.0',
  JWT_SECRET: process.env.JWT_SECRET || 'deka-live-bg-engine-secret-key-2026-secure-32bytes',
  JWT_ACCESS_EXPIRY: process.env.JWT_ACCESS_EXPIRY || '15m',
  JWT_PERSISTENT_EXPIRY: process.env.JWT_PERSISTENT_EXPIRY || '90d',
  STORAGE_DIR: process.env.STORAGE_DIR || path.resolve(rootDir, 'data'),
  PUBLIC_DIR: process.env.PUBLIC_DIR || path.resolve(rootDir, 'public'),
  DEFAULT_TABLES: ['table-01', 'table-02', 'table-03', 'table-04', 'table-05'],
  HEARTBEAT_TIMEOUT_MS: 15000,
  AUTO_SAVE_INTERVAL_MS: 10000,
};
