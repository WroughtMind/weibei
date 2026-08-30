import type { WeiBeiDesktopAPI } from "../shared/contracts";

declare global {
  interface Window {
    weiBei: WeiBeiDesktopAPI;
  }
}

export {};
