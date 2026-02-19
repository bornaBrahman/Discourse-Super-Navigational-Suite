# Discourse Super Navigation Suite (Theme Component)

Frontend/UI layer for the plugin backend.

## What this theme component currently ships (MVP)

- Renders mega menu in header area
- Supports nested menu items
- Supports `hover` and `click` open modes
- Debounced hover open
- Lazy-loads panel topic content on interaction
- Mobile-first responsive behavior
- Keyboard close support (`Escape`)

## File Structure

```text
discourse-super-navigation-suite-theme/
  about.json
  settings.yml
  locales/en.yml
  javascripts/discourse/
    connectors/above-site-header/super-navigation-suite.hbs
    lib/sns-api.js
  javascripts/api-initializers/
    super-navigation-suite.js
  stylesheets/common/super-navigation-suite-theme.scss
```

## Installation

1. Ensure plugin core is installed and running first.
2. In Discourse Admin -> Customize -> Themes -> Install.
3. Add this as a theme component (from local git repo or upload).
4. Attach it to your active theme.
5. Confirm `super_nav_enabled` is true in theme settings.

## Settings

- `super_nav_enabled`
- `super_nav_placement`
- `super_nav_mobile_breakpoint`
- `super_nav_allow_inline_item_css`
- `super_nav_panel_title`
- `super_nav_route_allowlist` (`/latest`, `/c/support*`, one per line or comma-separated)
