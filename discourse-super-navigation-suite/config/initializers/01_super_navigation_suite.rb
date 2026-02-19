# frozen_string_literal: true

module ::DiscourseSuperNavigationSuite
end

Rails.application.config.to_prepare do
  # Keep plugin namespace loaded during code reload in development.
  ::DiscourseSuperNavigationSuite::PLUGIN_NAME ||= "discourse-super-navigation-suite"
end
