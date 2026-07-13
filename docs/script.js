"use strict";

/**
 * 1. Theme preferences
 */

const DEFAULT_THEME_PREFERENCE = "system";
const THEME_PREFERENCES = ["system", "light", "dark"];
const THEME_STORAGE_KEY = "tesviye-website-theme";
const SYSTEM_THEME_QUERY = window.matchMedia("(prefers-color-scheme: dark)");
const THEME_LABEL_DATASETS = {
  system: "labelSystem",
  light: "labelLight",
  dark: "labelDark",
};

let currentThemePreference = getStoredThemePreference();

function getStoredThemePreference() {
  try {
    const storedPreference = window.localStorage.getItem(THEME_STORAGE_KEY);
    return THEME_PREFERENCES.includes(storedPreference) ? storedPreference : DEFAULT_THEME_PREFERENCE;
  } catch {
    // Browsers may disable storage; system mode remains a safe and functional fallback
    return DEFAULT_THEME_PREFERENCE;
  }
}

function getResolvedTheme(preference) {
  if (preference === DEFAULT_THEME_PREFERENCE) {
    return SYSTEM_THEME_QUERY.matches ? "dark" : "light";
  }

  return preference;
}

function updateThemeColor(resolvedTheme) {
  const themeColor = document.querySelector('meta[name="theme-color"]');
  if (!themeColor) {
    return;
  }

  const color = resolvedTheme === "dark" ? themeColor.dataset.colorDark : themeColor.dataset.colorLight;
  if (color) {
    themeColor.setAttribute("content", color);
  }
}

function updateThemeControl(preference) {
  const toggle = document.querySelector(".theme-toggle");
  if (!toggle) {
    return;
  }

  const labelKey = THEME_LABEL_DATASETS[preference];
  const label = toggle.dataset[labelKey];
  if (label) {
    toggle.setAttribute("aria-label", label);
    toggle.setAttribute("title", label);
  }
}

function applyThemePreference(preference) {
  const nextPreference = THEME_PREFERENCES.includes(preference) ? preference : DEFAULT_THEME_PREFERENCE;
  const resolvedTheme = getResolvedTheme(nextPreference);
  const root = document.documentElement;

  currentThemePreference = nextPreference;
  root.dataset.themePreference = nextPreference;
  root.dataset.theme = resolvedTheme;
  root.style.colorScheme = resolvedTheme;
  updateThemeColor(resolvedTheme);
  updateThemeControl(nextPreference);
}

function saveThemePreference(preference) {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, preference);
    return true;
  } catch {
    // The selected theme still applies for the current page when storage is unavailable
    return false;
  }
}

function getNextThemePreference(preference) {
  const currentIndex = THEME_PREFERENCES.indexOf(preference);
  return THEME_PREFERENCES[(currentIndex + 1) % THEME_PREFERENCES.length];
}

function handleSystemThemeChange() {
  if (currentThemePreference === DEFAULT_THEME_PREFERENCE) {
    applyThemePreference(DEFAULT_THEME_PREFERENCE);
  }
}

function initThemeControl() {
  const toggle = document.querySelector(".theme-toggle");
  if (!toggle) {
    return;
  }

  updateThemeControl(currentThemePreference);
  toggle.addEventListener("click", () => {
    const nextPreference = getNextThemePreference(currentThemePreference);
    applyThemePreference(nextPreference);
    saveThemePreference(nextPreference);
  });

  SYSTEM_THEME_QUERY.addEventListener("change", handleSystemThemeChange);
}

applyThemePreference(currentThemePreference);

/**
 * 2. Mobile navigation
 */

function initMobileNavigation() {
  const header = document.querySelector(".header-inner");
  const toggle = document.querySelector(".menu-toggle");
  const navigation = document.querySelector("#primary-navigation");

  if (!header || !toggle || !navigation) {
    return;
  }

  const setMenuState = (isOpen) => {
    const label = isOpen ? toggle.dataset.labelClose : toggle.dataset.labelOpen;
    header.dataset.menuOpen = String(isOpen);
    toggle.setAttribute("aria-expanded", String(isOpen));
    toggle.setAttribute("aria-label", label);
  };

  toggle.addEventListener("click", () => {
    setMenuState(toggle.getAttribute("aria-expanded") !== "true");
  });

  navigation.addEventListener("click", (event) => {
    if (event.target.closest("a")) {
      setMenuState(false);
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
      setMenuState(false);
      toggle.focus();
    }
  });
}

/**
 * 3. In-page navigation
 */

function removeLocationHash() {
  const cleanUrl = `${window.location.pathname}${window.location.search}`;

  try {
    window.history.replaceState(window.history.state, "", cleanUrl);
    return true;
  } catch {
    // Navigation remains functional when the browser prevents history updates
    return false;
  }
}

function scrollToInPageTarget(target, shouldFocus = false) {
  if (shouldFocus) {
    target.focus({ preventScroll: true });
  }

  target.scrollIntoView({ block: "start" });
}

function handleLocationHashChange() {
  const targetId = window.location.hash.slice(1);
  const target = targetId ? document.getElementById(targetId) : null;

  if (!target) {
    return;
  }

  scrollToInPageTarget(target);
  removeLocationHash();
}

function initInPageNavigation() {
  const inPageLinks = document.querySelectorAll('a[href^="#"]');

  inPageLinks.forEach((link) => {
    link.addEventListener("click", (event) => {
      const targetId = link.getAttribute("href")?.slice(1);
      const target = targetId ? document.getElementById(targetId) : null;

      if (!target) {
        return;
      }

      event.preventDefault();
      scrollToInPageTarget(target, link.classList.contains("skip-link"));
      removeLocationHash();
    });
  });

  window.addEventListener("hashchange", handleLocationHashChange);
  handleLocationHashChange();
}

/**
 * 4. Initialization
 */

function initPage() {
  initInPageNavigation();
  initThemeControl();
  initMobileNavigation();
}

document.addEventListener("DOMContentLoaded", initPage);
