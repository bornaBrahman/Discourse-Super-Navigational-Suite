# frozen_string_literal: true

module ::DiscourseSuperNavigationSuite
  class NavigationController < ::ApplicationController
    requires_plugin DiscourseSuperNavigationSuite::PLUGIN_NAME

    before_action :ensure_plugin_enabled
    before_action :ensure_config_rate_limit!, only: [:config]
    before_action :ensure_panel_rate_limit!, only: [:panel]

    def config
      expires_in SiteSetting.super_navigation_suite_cache_minutes.minutes, public: false
      render_json_dump(ConfigStore.visible_config(current_user))
    rescue StandardError => e
      Rails.logger.warn("[SNS] config endpoint failed: #{e.class} #{e.message}")
      render_json_dump(
        "version" => 1,
        "menus" => [],
        "sidebars" => [],
        "discovery_blocks" => [],
      )
    end

    def panel
      expires_in SiteSetting.super_navigation_suite_cache_minutes.minutes, public: false
      render_json_dump(TopicQuery.fetch(current_user, panel_params.to_h.symbolize_keys))
    rescue StandardError => e
      Rails.logger.warn("[SNS] panel endpoint failed: #{e.class} #{e.message}")
      render_json_dump(
        source: panel_params.to_h,
        topics: [],
      )
    end

    def presets
      guardian.ensure_can_admin!
      render_json_dump(ConfigStore.presets)
    end

    def export
      guardian.ensure_can_admin!
      render_json_dump(
        active_profile: ConfigStore.active_profile_summary,
        raw_json: ConfigStore.raw_json,
        normalized: ConfigStore.visible_config(current_user),
      )
    end

    def import
      guardian.ensure_can_admin!
      json = params.require(:config_json)
      raise Discourse::InvalidParameters.new(:config_json) unless ConfigStore.valid_json?(json)

      SiteSetting.super_navigation_suite_json = json
      render_json_dump(success: true)
    end

    private

    def panel_params
      params.permit(:source_type, :category_slug, :category_id, :tag, :time_range, :limit)
    end

    def ensure_plugin_enabled
      raise Discourse::NotFound unless SiteSetting.super_navigation_suite_enabled
    end

    def ensure_config_rate_limit!
      perform_rate_limit!(
        "sns-config",
        safe_site_setting(:super_navigation_suite_config_rate_limit_per_minute, 120),
      )
    end

    def ensure_panel_rate_limit!
      perform_rate_limit!(
        "sns-panel",
        safe_site_setting(:super_navigation_suite_panel_rate_limit_per_minute, 240),
      )
    end

    def perform_rate_limit!(prefix, max_per_minute)
      return if max_per_minute.to_i <= 0

      identifier = current_user ? "u#{current_user.id}" : "ip#{request.remote_ip}"
      RateLimiter.new(
        current_user,
        "#{prefix}:#{identifier}",
        max_per_minute,
        1.minute,
      ).performed!
    rescue RateLimiter::LimitExceeded
      raise
    rescue StandardError => e
      Rails.logger.warn("[SNS] rate limit check skipped: #{e.class} #{e.message}")
    end

    def safe_site_setting(name, fallback)
      return fallback unless SiteSetting.respond_to?(name)

      SiteSetting.public_send(name).to_i
    rescue StandardError
      fallback
    end
  end
end
