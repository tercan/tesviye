"use strict";

/**
 * 1. Mobile navigation
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
 * 2. Footer metadata
 */

function updateCurrentYear() {
  const year = String(new Date().getFullYear());
  document.querySelectorAll("[data-current-year]").forEach((element) => {
    element.textContent = year;
  });
}

/**
 * 3. Initialization
 */

initMobileNavigation();
updateCurrentYear();
