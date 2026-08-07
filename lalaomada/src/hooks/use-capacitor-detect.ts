import { Capacitor } from "@capacitor/core";

/**
 * Returns true if the app is running inside a Capacitor native container
 * (Android APK or iOS app), false if running in a regular web browser.
 */
export function isNativeApp(): boolean {
  return Capacitor.isNativePlatform();
}
