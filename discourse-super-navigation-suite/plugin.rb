# frozen_string_literal: true

# name: discourse-super-navigation-suite
# about: Modular navigation and discovery backend for Discourse Super Navigation Suite
# version: 0.1.0
# authors: Codex
# url: https://example.com/discourse-super-navigation-suite

enabled_site_setting :super_navigation_suite_enabled

register_asset "stylesheets/common/super-navigation-suite.scss"

require_relative "lib/discourse_super_navigation_suite/engine"

after_initialize do
  module ::DiscourseSuperNavigationSuite
    PLUGIN_NAME ||= "discourse-super-navigation-suite"
  end

  require_relative "app/models/discourse_super_navigation_suite/navigation_profile"
  require_relative "lib/discourse_super_navigation_suite/visibility_resolver"
  require_relative "lib/discourse_super_navigation_suite/config_store"
  require_relative "lib/discourse_super_navigation_suite/topic_query"
  require_relative "app/controllers/discourse_super_navigation_suite/navigation_controller"

  Discourse::Application.routes.append do
    mount ::DiscourseSuperNavigationSuite::Engine, at: "/super-navigation-suite"
  end
end
