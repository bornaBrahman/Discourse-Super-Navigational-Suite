/* global settings */
import { apiInitializer } from "discourse/lib/api";
import { scheduleOnce, later, cancel } from "@ember/runloop";
import { fetchNavigationConfig, fetchPanelData } from "../discourse/lib/sns-api";

const MOBILE_OPEN_CLASS = "sns-mobile-open";
const ACTIVE_CLASS = "is-open";

function hasDropdown(item) {
  return (item.children && item.children.length > 0) || item.panel;
}

function pickMenu(config, placement) {
  if (!config || !config.menus) {
    return null;
  }

  return (
    config.menus.find((menu) => menu.placement === placement) || config.menus[0] || null
  );
}

function panelCacheKey(panelConfig) {
  return JSON.stringify({
    source_type: panelConfig.source_type,
    category_slug: panelConfig.category_slug,
    category_id: panelConfig.category_id,
    tag: panelConfig.tag,
    time_range: panelConfig.time_range,
    limit: panelConfig.limit,
  });
}

function formatDate(value) {
  if (!value) {
    return "";
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return date.toLocaleDateString();
}

function parseRouteAllowlist() {
  const raw = settings.super_nav_route_allowlist || "";
  return raw
    .split(/[\n,]/)
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function routeAllowed(pathname) {
  const allowlist = parseRouteAllowlist();
  if (allowlist.length === 0 || allowlist.includes("*")) {
    return true;
  }

  return allowlist.some((entry) => {
    if (entry.endsWith("*")) {
      return pathname.startsWith(entry.slice(0, -1));
    }
    return pathname === entry;
  });
}

export default apiInitializer("1.8.0", (api) => {
  if (!settings.super_nav_enabled) {
    return;
  }

  if (window.__snsThemeInitialized) {
    return;
  }
  window.__snsThemeInitialized = true;

  const state = {
    root: null,
    nav: null,
    menu: null,
    config: null,
    openDropdown: null,
    hoverTimer: null,
    panelCache: new Map(),
  };

  function closeCurrentDropdown() {
    if (!state.openDropdown) {
      state.nav?.classList.remove("sns-click-mode");
      return;
    }

    const { li, toggleButton } = state.openDropdown;
    li.classList.remove(ACTIVE_CLASS);
    const dropdown = li.querySelector(":scope > .sns-dropdown");
    if (dropdown) {
      dropdown.hidden = true;
    }
    if (toggleButton) {
      toggleButton.setAttribute("aria-expanded", "false");
    }
    state.openDropdown = null;
    state.nav?.classList.remove("sns-click-mode");
  }

  function toggleMobileNav() {
    if (!state.nav) {
      return;
    }
    state.nav.classList.toggle(MOBILE_OPEN_CLASS);
  }

  function closeMobileNavOnDesktop() {
    if (!state.nav) {
      return;
    }

    const breakpoint = Number(settings.super_nav_mobile_breakpoint) || 960;
    if (window.innerWidth > breakpoint) {
      state.nav.classList.remove(MOBILE_OPEN_CLASS);
    }
  }

  function renderPanelLoading(panelBody) {
    panelBody.innerHTML = "";
    const loading = document.createElement("div");
    loading.className = "sns-panel-loading";
    loading.textContent = "Loading...";
    panelBody.appendChild(loading);
  }

  function renderPanelError(panelBody) {
    panelBody.innerHTML = "";
    const error = document.createElement("div");
    error.className = "sns-panel-empty";
    error.textContent = "No content available.";
    panelBody.appendChild(error);
  }

  function renderPanelTopics(panelBody, payload, panelConfig) {
    panelBody.innerHTML = "";
    const topics = (payload && payload.topics) || [];

    if (topics.length === 0) {
      renderPanelError(panelBody);
      return;
    }

    const list = document.createElement("ul");
    list.className = "sns-panel-topic-list";

    topics.forEach((topic) => {
      const item = document.createElement("li");
      item.className = "sns-panel-topic";

      if (panelConfig.show_thumbnail && topic.image_url) {
        const thumb = document.createElement("img");
        thumb.className = "sns-panel-topic-thumb";
        thumb.src = topic.image_url;
        thumb.alt = "";
        thumb.loading = "lazy";
        item.appendChild(thumb);
      }

      const link = document.createElement("a");
      link.className = "sns-panel-topic-title";
      link.href = topic.url;
      link.textContent = topic.title;

      const meta = document.createElement("div");
      meta.className = "sns-panel-topic-meta";
      const categoryName = topic.category ? topic.category.name : "General";
      meta.textContent = `${categoryName} - ${topic.posts_count} posts - ${formatDate(topic.bumped_at)}`;

      item.appendChild(link);
      item.appendChild(meta);

      if (panelConfig.show_excerpt && topic.excerpt) {
        const excerpt = document.createElement("p");
        excerpt.className = "sns-panel-topic-excerpt";
        excerpt.textContent = topic.excerpt;
        item.appendChild(excerpt);
      }

      list.appendChild(item);
    });

    panelBody.appendChild(list);
  }

  async function loadPanel(panelContainer, panelConfig) {
    if (!panelContainer || !panelConfig) {
      return;
    }

    const panelBody = panelContainer.querySelector(".sns-panel-body");
    if (!panelBody) {
      return;
    }

    const key = panelCacheKey(panelConfig);
    if (state.panelCache.has(key)) {
      renderPanelTopics(panelBody, state.panelCache.get(key), panelConfig);
      return;
    }

    renderPanelLoading(panelBody);
    try {
      const payload = await fetchPanelData(panelConfig);
      state.panelCache.set(key, payload);
      renderPanelTopics(panelBody, payload, panelConfig);
    } catch (error) {
      renderPanelError(panelBody);
    }
  }

  function openDropdown(li, toggleButton, item, menu) {
    if (state.openDropdown && state.openDropdown.li === li) {
      return;
    }

    closeCurrentDropdown();
    li.classList.add(ACTIVE_CLASS);

    const dropdown = li.querySelector(":scope > .sns-dropdown");
    if (dropdown) {
      dropdown.hidden = false;
    }

    if (toggleButton) {
      toggleButton.setAttribute("aria-expanded", "true");
    }

    state.openDropdown = { li, toggleButton };

    if (item.panel && dropdown) {
      const panelContainer = dropdown.querySelector(".sns-panel");
      if (panelContainer) {
        loadPanel(panelContainer, item.panel);
      }
    }

    if (menu.open_mode === "click") {
      state.nav.classList.add("sns-click-mode");
    }
  }

  function queueHoverOpen(li, toggleButton, item, menu) {
    cancel(state.hoverTimer);
    state.hoverTimer = later(() => openDropdown(li, toggleButton, item, menu), menu.hover_delay_ms || 120);
  }

  function bindItemInteractions(li, toggleButton, item, menu) {
    const shouldHover = menu.open_mode === "hover";

    if (shouldHover) {
      li.addEventListener("mouseenter", () => queueHoverOpen(li, toggleButton, item, menu));
      li.addEventListener("mouseleave", () => {
        cancel(state.hoverTimer);
        closeCurrentDropdown();
      });
    }

    if (toggleButton) {
      toggleButton.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();

        if (state.openDropdown && state.openDropdown.li === li) {
          closeCurrentDropdown();
        } else {
          openDropdown(li, toggleButton, item, menu);
        }
      });

      toggleButton.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
          closeCurrentDropdown();
          toggleButton.focus();
        }
      });
    }
  }

  function createItemRow(item, hasChildrenOrPanel, li, menu) {
    const row = document.createElement("div");
    row.className = "sns-item-row";

    if (item.type === "divider") {
      li.classList.add("is-divider");
      return { row, toggleButton: null };
    }

    if (item.type === "section_heading" && !item.resolved_url) {
      const heading = document.createElement("span");
      heading.className = "sns-heading";

      if (item.image_url) {
        const image = document.createElement("img");
        image.className = "sns-item-image";
        image.src = item.image_url;
        image.alt = "";
        image.loading = "lazy";
        heading.appendChild(image);
      } else if (item.icon) {
        const icon = document.createElement("span");
        icon.className = `sns-item-icon ${item.icon}`;
        icon.setAttribute("aria-hidden", "true");
        heading.appendChild(icon);
      }

      const label = document.createElement("span");
      label.className = "sns-label";
      label.textContent = item.title || "Section";
      heading.appendChild(label);
      row.appendChild(heading);
    } else {
      const link = document.createElement("a");
      link.className = "sns-link";

      if (item.image_url) {
        const image = document.createElement("img");
        image.className = "sns-item-image";
        image.src = item.image_url;
        image.alt = "";
        image.loading = "lazy";
        link.appendChild(image);
      } else if (item.icon) {
        const icon = document.createElement("span");
        icon.className = `sns-item-icon ${item.icon}`;
        icon.setAttribute("aria-hidden", "true");
        link.appendChild(icon);
      }

      const label = document.createElement("span");
      label.className = "sns-label";
      label.textContent = item.title || "Untitled";
      link.appendChild(label);
      link.href = item.resolved_url || item.url || "#";
      if (item.type === "external_link") {
        link.target = "_blank";
        link.rel = "noopener noreferrer";
      }
      row.appendChild(link);
    }

    let toggleButton = null;
    if (hasChildrenOrPanel) {
      toggleButton = document.createElement("button");
      toggleButton.type = "button";
      toggleButton.className = "sns-expand";
      toggleButton.setAttribute("aria-label", `Open ${item.title || "menu"}`);
      toggleButton.setAttribute("aria-expanded", "false");
      toggleButton.innerHTML = '<span aria-hidden="true">v</span>';
      row.appendChild(toggleButton);
    }

    return { row, toggleButton };
  }

  function createPanel(panelConfig) {
    const panel = document.createElement("section");
    panel.className = "sns-panel";

    const title = document.createElement("h4");
    title.className = "sns-panel-title";
    title.textContent = settings.super_nav_panel_title || "Trending";

    const body = document.createElement("div");
    body.className = "sns-panel-body";

    panel.appendChild(title);
    panel.appendChild(body);
    return panel;
  }

  function createMenuList(items, depth, menu) {
    const list = document.createElement("ul");
    list.className = `sns-menu sns-menu-depth-${depth}`;
    list.setAttribute("role", depth === 0 ? "menubar" : "menu");

    (items || []).forEach((item) => {
      const li = document.createElement("li");
      li.className = "sns-item";
      li.dataset.itemId = item.id;

      if (item.custom_css_class) {
        li.classList.add(item.custom_css_class);
      }

      if (settings.super_nav_allow_inline_item_css && item.custom_css) {
        li.style.cssText = item.custom_css;
      }

      const showDropdown = hasDropdown(item);
      const rowData = createItemRow(item, showDropdown, li, menu);
      li.appendChild(rowData.row);

      if (showDropdown) {
        const dropdown = document.createElement("div");
        dropdown.className = "sns-dropdown";
        dropdown.hidden = true;

        const grid = document.createElement("div");
        grid.className = "sns-dropdown-grid";

        if (item.children && item.children.length) {
          grid.appendChild(createMenuList(item.children, depth + 1, menu));
        }

        if (item.panel) {
          grid.appendChild(createPanel(item.panel));
        }

        dropdown.appendChild(grid);
        li.appendChild(dropdown);
        bindItemInteractions(li, rowData.toggleButton, item, menu);
      }

      list.appendChild(li);
    });

    return list;
  }

  function renderNavigation() {
    if (!state.nav || !state.menu) {
      return;
    }

    state.nav.innerHTML = "";

    const inner = document.createElement("div");
    inner.className = "sns-nav-inner";

    const mobileToggle = document.createElement("button");
    mobileToggle.type = "button";
    mobileToggle.className = "sns-mobile-toggle";
    mobileToggle.textContent = "Browse";
    mobileToggle.addEventListener("click", toggleMobileNav);

    const menuWrap = document.createElement("div");
    menuWrap.className = "sns-menu-wrap";

    const menuList = createMenuList(state.menu.items, 0, state.menu);
    menuWrap.appendChild(menuList);

    inner.appendChild(mobileToggle);
    inner.appendChild(menuWrap);
    state.nav.appendChild(inner);
  }

  async function loadConfigAndRender() {
    try {
      state.config = await fetchNavigationConfig();
      state.menu = pickMenu(state.config, settings.super_nav_placement || "top_nav");
      renderNavigation();
    } catch (error) {
      state.nav.innerHTML = "";
    }
  }

  function mount() {
    state.root = document.querySelector("#sns-mega-menu-root");
    if (!state.root) {
      const header = document.querySelector(".d-header");
      if (!header) {
        return false;
      }
      state.root = document.createElement("div");
      state.root.id = "sns-mega-menu-root";
      header.insertAdjacentElement("afterend", state.root);
    }

    if (!state.nav) {
      state.nav = document.createElement("nav");
      state.nav.className = "sns-nav-bar";
      state.nav.setAttribute("aria-label", "Super Navigation");

      state.nav.addEventListener("click", (event) => {
        const link = event.target.closest(".sns-link");
        if (!link) {
          return;
        }

        closeCurrentDropdown();

        const breakpoint = Number(settings.super_nav_mobile_breakpoint) || 960;
        if (window.innerWidth <= breakpoint) {
          state.nav.classList.remove(MOBILE_OPEN_CLASS);
        }
      });

      state.root.appendChild(state.nav);
    }

    return true;
  }

  function updateRouteVisibility() {
    if (!state.root) {
      return false;
    }

    const visible = routeAllowed(window.location.pathname);
    state.root.style.display = visible ? "" : "none";
    if (!visible) {
      closeCurrentDropdown();
    }
    return visible;
  }

  function attachGlobalEvents() {
    document.addEventListener("click", (event) => {
      if (!state.nav) {
        return;
      }

      if (!state.nav.contains(event.target)) {
        closeCurrentDropdown();
        state.nav.classList.remove(MOBILE_OPEN_CLASS);
      }
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closeCurrentDropdown();
      }
    });

    window.addEventListener("resize", closeMobileNavOnDesktop);
  }

  attachGlobalEvents();

  api.onPageChange(() => {
    scheduleOnce("afterRender", null, () => {
      if (!mount()) {
        return;
      }

      if (!updateRouteVisibility()) {
        return;
      }

      if (!state.config) {
        loadConfigAndRender();
      } else {
        state.menu = pickMenu(state.config, settings.super_nav_placement || "top_nav");
        renderNavigation();
      }
    });
  });
});
