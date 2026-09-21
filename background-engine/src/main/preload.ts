import { contextBridge, ipcRenderer } from 'electron';

// Expose safe, bounded IPC bridge
contextBridge.exposeInMainWorld('electronIpc', {
  send: (channel: string, data: any) => {
    const validChannels = [
      'open-login',
      'logout',
      'set-position',
      'save-position',
      'automove-cmd',
      'test-output',
      'recheck-sources',
      'reconnect-game',
      'reconnect-chat',
    ];
    if (validChannels.includes(channel)) {
      ipcRenderer.send(channel, data);
    }
  },
  on: (channel: string, callback: (...args: any[]) => void) => {
    const validChannels = [
      'safety-state-changed',
      'auth-status-changed',
      'game-state-changed',
      'chat-state-changed',
      'automove-tick',
      'ndi-telemetry',
      'app-telemetry',
      'set-safety-state',
      'set-position',
      'new-chat-message',
    ];
    if (validChannels.includes(channel)) {
      ipcRenderer.on(channel, (_event, ...args) => callback(_event, ...args));
    }
  },
});
