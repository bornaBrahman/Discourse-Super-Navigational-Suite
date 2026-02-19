# frozen_string_literal: true

module ::DiscourseSuperNavigationSuite
  class NavigationProfile < ActiveRecord::Base
    self.table_name = "super_navigation_profiles"

    validates :name, presence: true
    validates :profile_key, presence: true, uniqueness: true
    validates :config_json, presence: true

    scope :active, -> { where(active: true) }
  end
end
