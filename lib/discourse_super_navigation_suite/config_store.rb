# frozen_string_literal: true

require "digest"
require "json"
require "uri"

module ::DiscourseSuperNavigationSuite
  class ConfigStore
    ALLOWED_MENU_LAYOUTS = %w[dropdown mega_grid sidebar].freeze
    ALLOWED_OPEN_MODES = %w[hover click].freeze
    ALLOWED_PLACEMENTS = %w[top_nav sidebar floating].freeze
    ALLOWED_ITEM_TYPES = %w[
      link
      category
      tag
      topic
      external_link
      section_heading
      divider
    ].freeze
    ALLOWED_PANEL_SOURCES = %w[
      latest
      category_latest
      category_top
      tag_latest
      featured
    ].freeze
    ALLOWED_TIME_RANGES = %w[daily weekly monthly quarterly yearly all].freeze

    DEFAULT_CONFIG = {
      "version" => 1,
      "menus" => [],
      "sidebars" => [],
      "discovery_blocks" => [],
    }.freeze

    class << self
      def raw_json
        active_profile_json.presence || SiteSetting.super_navigation_suite_json.presence || DEFAULT_CONFIG.to_json
      end

      def valid_json?(json)
        parsed = JSON.parse(json)
        return false unless parsed.is_a?(Hash)

        normalize_config(parsed)
        true
      rescue JSON::ParserError, StandardError
        false
      end

      def active_profile_summary
        profile = active_profile
        return nil unless profile

        {
          id: profile.id,
          name: profile.name,
          profile_key: profile.profile_key,
          updated_at: profile.updated_at,
        }
      end

      def visible_config(user)
        normalized = normalized_config
        context = VisibilityResolver.build_context(user)

        {
          "version" => normalized["version"],
          "menus" => Array(normalized["menus"]).map { |menu| visible_menu(menu, user, context) }.compact,
          "sidebars" => Array(normalized["sidebars"]).map { |sidebar| visible_sidebar(sidebar, user, context) }.compact,
          "discovery_blocks" => Array(normalized["discovery_blocks"]).map { |block| visible_block(block, user, context) }.compact,
        }
      end

      def presets
        {
          "reddit_style" => reddit_style_preset,
          "netflix_style" => netflix_style_preset,
          "knowledge_base" => knowledge_base_preset,
        }
      end

      private

      def normalized_config
        json = raw_json
        cache_key = "sns:config:normalized:#{Digest::SHA256.hexdigest(json)}"

        Rails.cache.fetch(cache_key, expires_in: SiteSetting.super_navigation_suite_cache_minutes.minutes) do
          parsed = JSON.parse(json)
          normalize_config(parsed)
        rescue JSON::ParserError
          DEFAULT_CONFIG.deep_dup
        end
      end

      def active_profile_json
        profile = active_profile
        profile&.config_json
      end

      def active_profile
        return nil unless NavigationProfile.table_exists?

        NavigationProfile.active.order(updated_at: :desc).first
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
        nil
      end

      def normalize_config(config)
        config = DEFAULT_CONFIG.deep_merge(config.is_a?(Hash) ? config : {})
        menus = Array(config["menus"]).map.with_index { |menu, index| normalize_menu(menu, index) }

        {
          "version" => config["version"].to_i.nonzero? || 1,
          "menus" => menus,
          "sidebars" => Array(config["sidebars"]).map { |sidebar| normalize_generic_entity(sidebar) },
          "discovery_blocks" => Array(config["discovery_blocks"]).map { |block| normalize_generic_entity(block) },
        }
      end

      def normalize_menu(menu, index)
        menu = menu.is_a?(Hash) ? menu : {}
        menu_id = menu["id"].presence || "menu-#{index + 1}"

        {
          "id" => menu_id,
          "label" => menu["label"].presence || menu_id.titleize,
          "placement" => safe_enum(menu["placement"], ALLOWED_PLACEMENTS, "top_nav"),
          "layout" => safe_enum(menu["layout"], ALLOWED_MENU_LAYOUTS, "mega_grid"),
          "open_mode" => safe_enum(menu["open_mode"], ALLOWED_OPEN_MODES, "hover"),
          "hover_delay_ms" => menu["hover_delay_ms"].to_i.clamp(0, 1000),
          "visibility" => VisibilityResolver.normalize_visibility(menu["visibility"]),
          "items" => Array(menu["items"]).map.with_index { |item, item_index| normalize_item(item, "#{menu_id}-#{item_index + 1}") },
        }
      end

      def normalize_item(item, generated_id)
        item = item.is_a?(Hash) ? item : {}
        item_id = item["id"].presence || generated_id
        item_type = safe_enum(item["type"], ALLOWED_ITEM_TYPES, "link")

        normalized = {
          "id" => item_id,
          "title" => item["title"].to_s,
          "type" => item_type,
          "url" => sanitize_url(item["url"]),
          "resolved_url" => resolve_url(item_type, item),
          "icon" => item["icon"].to_s.presence,
          "image_url" => item["image_url"].to_s.presence,
          "custom_css_class" => item["custom_css_class"].to_s.presence,
          "custom_css" => item["custom_css"].to_s.presence,
          "visibility" => VisibilityResolver.normalize_visibility(item["visibility"]),
          "panel" => normalize_panel(item["panel"]),
          "children" => [],
        }

        normalized["children"] =
          Array(item["children"]).map.with_index do |child, child_index|
            normalize_item(child, "#{item_id}-#{child_index + 1}")
          end

        normalized
      end

      def normalize_panel(panel)
        return nil unless panel.is_a?(Hash)

        source_type = safe_enum(panel["source_type"], ALLOWED_PANEL_SOURCES, "latest")
        limit = panel["limit"].to_i
        limit = 6 if limit <= 0
        limit = [limit, SiteSetting.super_navigation_suite_max_panel_items].min

        {
          "source_type" => source_type,
          "category_slug" => panel["category_slug"].to_s.presence,
          "category_id" => panel["category_id"].to_i.positive? ? panel["category_id"].to_i : nil,
          "tag" => panel["tag"].to_s.presence,
          "time_range" => safe_enum(panel["time_range"], ALLOWED_TIME_RANGES, "weekly"),
          "limit" => limit,
          "show_thumbnail" => panel["show_thumbnail"] != false,
          "show_excerpt" => panel["show_excerpt"] != false,
        }
      end

      def normalize_generic_entity(entity)
        entity = entity.is_a?(Hash) ? entity : {}
        entity.merge("visibility" => VisibilityResolver.normalize_visibility(entity["visibility"]))
      end

      def visible_menu(menu, user, context)
        return nil unless VisibilityResolver.allowed?(menu["visibility"], user, context)

        items = Array(menu["items"]).map { |item| visible_item(item, user, context) }.compact
        return nil if items.blank?

        menu.merge("items" => items)
      end

      def visible_sidebar(sidebar, user, context)
        return nil unless VisibilityResolver.allowed?(sidebar["visibility"], user, context)

        widgets = Array(sidebar["widgets"]).map { |widget| visible_block(widget, user, context) }.compact
        sidebar.merge("widgets" => widgets)
      end

      def visible_block(block, user, context)
        return nil unless VisibilityResolver.allowed?(block["visibility"], user, context)
        block
      end

      def visible_item(item, user, context)
        return nil unless VisibilityResolver.allowed?(item["visibility"], user, context)

        children = Array(item["children"]).map { |child| visible_item(child, user, context) }.compact
        visible = item.merge(
          "children" => children,
          "resolved_url" => resolve_url_for_user(item, user),
        )
        return nil if item["type"] == "divider" && children.blank? && item["panel"].blank?

        visible
      end

      def safe_enum(value, accepted_values, fallback)
        accepted_values.include?(value.to_s) ? value.to_s : fallback
      end

      def resolve_url(item_type, item)
        case item_type
        when "link", "external_link"
          sanitize_url(item["url"])
        when "category"
          category = find_category(item)
          category ? sanitize_url("/c/#{category.slug}/#{category.id}") : sanitize_url(item["url"])
        when "tag"
          tag = item["tag"].to_s.presence
          tag ? sanitize_url("/tag/#{tag}") : sanitize_url(item["url"])
        when "topic"
          topic = find_topic(item)
          topic ? sanitize_url(topic.relative_url) : sanitize_url(item["url"])
        else
          nil
        end
      end

      def resolve_url_for_user(item, user)
        item_type = item["type"].to_s
        guardian = Guardian.new(user)

        case item_type
        when "category"
          category = find_category(item)
          return nil unless category && guardian.can_see?(category)

          "/c/#{category.slug}/#{category.id}"
        when "topic"
          topic = find_topic(item)
          return nil unless topic && guardian.can_see?(topic)

          topic.relative_url
        else
          sanitize_url(item["resolved_url"] || item["url"])
        end
      end

      def find_category(item)
        if item["category_id"].to_i.positive?
          Category.find_by(id: item["category_id"].to_i)
        elsif item["category_slug"].present?
          Category.find_by(slug: item["category_slug"])
        end
      end

      def find_topic(item)
        Topic.find_by(id: item["topic_id"].to_i) if item["topic_id"].to_i.positive?
      end

      def sanitize_url(value)
        url = value.to_s.strip
        return nil if url.blank?
        return url if url.start_with?("/")

        uri = URI.parse(url)
        return url if %w[http https mailto tel].include?(uri.scheme)

        nil
      rescue URI::InvalidURIError
        nil
      end

      def reddit_style_preset
        {
          "version" => 1,
          "menus" => [
            {
              "id" => "reddit-primary",
              "label" => "Reddit Style",
              "placement" => "top_nav",
              "layout" => "mega_grid",
              "open_mode" => "hover",
              "hover_delay_ms" => 100,
              "items" => [
                { "id" => "hot", "title" => "Hot", "type" => "link", "url" => "/latest" },
                { "id" => "new", "title" => "New", "type" => "link", "url" => "/new" },
                { "id" => "top", "title" => "Top", "type" => "link", "url" => "/top" },
                {
                  "id" => "communities",
                  "title" => "Communities",
                  "type" => "section_heading",
                  "panel" => { "source_type" => "category_latest", "category_slug" => "general", "limit" => 8 },
                },
              ],
            },
          ],
          "sidebars" => [],
          "discovery_blocks" => [],
        }
      end

      def netflix_style_preset
        {
          "version" => 1,
          "menus" => [
            {
              "id" => "netflix-primary",
              "label" => "Netflix Style",
              "placement" => "top_nav",
              "layout" => "mega_grid",
              "open_mode" => "hover",
              "hover_delay_ms" => 220,
              "items" => [
                { "id" => "home", "title" => "Home", "type" => "link", "url" => "/" },
                {
                  "id" => "trending",
                  "title" => "Trending",
                  "type" => "link",
                  "url" => "/top",
                  "panel" => { "source_type" => "category_top", "category_slug" => "general", "time_range" => "weekly", "limit" => 10 },
                },
                {
                  "id" => "new-releases",
                  "title" => "New Releases",
                  "type" => "link",
                  "url" => "/latest",
                  "panel" => { "source_type" => "latest", "limit" => 10 },
                },
              ],
            },
          ],
          "sidebars" => [],
          "discovery_blocks" => [],
        }
      end

      def knowledge_base_preset
        {
          "version" => 1,
          "menus" => [
            {
              "id" => "kb-primary",
              "label" => "Knowledge Base",
              "placement" => "top_nav",
              "layout" => "dropdown",
              "open_mode" => "click",
              "hover_delay_ms" => 0,
              "items" => [
                { "id" => "docs-home", "title" => "Documentation", "type" => "link", "url" => "/categories" },
                {
                  "id" => "popular-guides",
                  "title" => "Popular Guides",
                  "type" => "section_heading",
                  "panel" => { "source_type" => "category_top", "category_slug" => "general", "time_range" => "monthly", "limit" => 6 },
                },
                {
                  "id" => "release-notes",
                  "title" => "Release Notes",
                  "type" => "tag",
                  "tag" => "release-notes",
                },
              ],
            },
          ],
          "sidebars" => [],
          "discovery_blocks" => [],
        }
      end
    end
  end
end
