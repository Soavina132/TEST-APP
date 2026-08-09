import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.lalaomada.app',
  appName: 'Lalao MADA',
  webDir: '.output/public',
  server: {
    androidScheme: 'https',
  },
};

export default config;
