import { ajax } from "discourse/lib/ajax";

const BASE_PATH = "/super-navigation-suite/navigation";

export function fetchNavigationConfig() {
  return ajax(`${BASE_PATH}/config`);
}

export function fetchPanelData(panelConfig) {
  const params = new URLSearchParams();
  Object.entries(panelConfig || {}).forEach(([key, value]) => {
    if (value !== null && value !== undefined && value !== "") {
      params.set(key, value);
    }
  });

  return ajax(`${BASE_PATH}/panel?${params.toString()}`);
}
