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
    end

    def panel
      expires_in SiteSetting.super_navigation_suite_cache_minutes.minutes, public: false
      render_json_dump(TopicQuery.fetch(current_user, panel_params.to_h.symbolize_keys))
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
        SiteSetting.super_navigation_suite_config_rate_limit_per_minute,
      )
    end

    def ensure_panel_rate_limit!
      perform_rate_limit!(
        "sns-panel",
        SiteSetting.super_navigation_suite_panel_rate_limit_per_minute,
      )
    end

    def perform_rate_limit!(prefix, max_per_minute)
      identifier = current_user ? "u#{current_user.id}" : "ip#{request.remote_ip}"
      RateLimiter.new(
        current_user,
        "#{prefix}:#{identifier}",
        max_per_minute,
        1.minute,
      ).performed!
    end
  end
end
