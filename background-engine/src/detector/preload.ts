import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('detectorIpc', {
  send: (channel: string, data?: any) => {
    const valid = ['open-interactive-browser'];
    if (valid.includes(channel)) {
      ipcRenderer.send(channel, data);
    }
  },
  invoke: async (channel: string, data?: any) => {
    const valid = ['inspect-url', 'get-session-cookies', 'export-adapter-to-engine'];
    if (valid.includes(channel)) {
      return await ipcRenderer.invoke(channel, data);
    }
    throw new Error(`Unauthorized channel: ${channel}`);
  },
});
