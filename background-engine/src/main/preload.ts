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
      'scan-source',
      'detect-browser',
      'preview-source',
      'test-source',
      'add-source-adapter',
      'remove-source-adapter',
      'reconnect-adapter',
    ];
    if (validChannels.includes(channel)) {
      ipcRenderer.send(channel, data);
    }
  },
  invoke: async (channel: string, data: any) => {
    const validChannels = [
      'scan-source',
      'detect-browser',
      'test-source',
      'add-source-adapter',
      'remove-source-adapter',
      'get-configured-sources',
    ];
    if (validChannels.includes(channel)) {
      return await ipcRenderer.invoke(channel, data);
    }
    throw new Error(`Unauthorized IPC invoke channel: ${channel}`);
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
      'scan-results',
      'adapter-status-changed',
      'adapter-health',
      'adapter-frame',
      'adapter-game-state',
      'adapter-chat-message',
      'configured-sources-changed',
    ];
    if (validChannels.includes(channel)) {
      ipcRenderer.on(channel, (_event, ...args) => callback(_event, ...args));
    }
  },
});
