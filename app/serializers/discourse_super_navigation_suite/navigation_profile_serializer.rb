# frozen_string_literal: true

module ::DiscourseSuperNavigationSuite
  class NavigationProfileSerializer < ApplicationSerializer
    attributes :id, :name, :profile_key, :active, :updated_at, :created_at
  end
end
