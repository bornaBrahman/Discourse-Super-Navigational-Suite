# Discourse Super Navigation Suite (Plugin Core)

Backend/API layer for a modular navigation, sidebar, and discovery system on Discourse.

## What this plugin currently ships (MVP)

- Config-driven mega menu API
- Dynamic panel topics API for hover/click previews
- Visibility rules by login state, groups, and trust level
- Config presets API (`reddit_style`, `netflix_style`, `knowledge_base`)
- Admin import/export endpoints for JSON config
- Optional persistent profile model (`super_navigation_profiles`)
- Response caching for performance

## Architecture

- Plugin core (this repo): data model, config parsing, visibility permissions, content queries, API endpoints
- Theme component (separate repo): UI rendering, interaction logic, animations, responsive behavior

## File Structure

```text
discourse-super-navigation-suite/
  plugin.rb
  config/
    initializers/01_super_navigation_suite.rb
    routes.rb
    settings.yml
    locales/server.en.yml
  app/
    controllers/discourse_super_navigation_suite/navigation_controller.rb
    models/discourse_super_navigation_suite/navigation_profile.rb
    serializers/discourse_super_navigation_suite/navigation_profile_serializer.rb
  lib/discourse_super_navigation_suite/
    engine.rb
    config_store.rb
    topic_query.rb
    visibility_resolver.rb
  db/migrate/20260218000100_create_super_navigation_profiles.rb
  docs/
    example-config.json
    presets.json
```

## API Endpoints

- `GET /super-navigation-suite/navigation/config`
- `GET /super-navigation-suite/navigation/panel`
- `GET /super-navigation-suite/navigation/presets` (admin)
- `GET /super-navigation-suite/navigation/export` (admin)
- `POST /super-navigation-suite/navigation/import` (admin, `config_json`)

Public endpoints are rate-limited by:

- `super_navigation_suite_config_rate_limit_per_minute`
- `super_navigation_suite_panel_rate_limit_per_minute`

## Installation (self-hosted Discourse)

1. Copy this folder into your Discourse container host at:
   `containers/app/plugins/discourse-super-navigation-suite`
2. Rebuild Discourse:
   `cd /var/discourse`
   `./launcher rebuild app`
3. In Admin -> Settings, search for `super_navigation_suite`.
4. Enable `super_navigation_suite_enabled`.
5. Paste `docs/example-config.json` into `super_navigation_suite_json`.

## Migration

If you use the profile model:

1. Enter container: `./launcher enter app`
2. Run migration: `rake db:migrate`

## Development Notes

- Menu config is JSON-first and designed for future drag-and-drop builders.
- Sidebars and discovery blocks are present in schema now and can be implemented in subsequent phases.
