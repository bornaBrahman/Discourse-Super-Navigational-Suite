# frozen_string_literal: true

module ::DiscourseSuperNavigationSuite
  class VisibilityResolver
    SUPPORTED_KEYS = %w[logged_in_only logged_out_only groups trust_level_min].freeze

    def self.build_context(user)
      {
        user: user,
        trust_level: user&.trust_level || 0,
        group_names: user ? user.groups.pluck(:name).map(&:downcase) : [],
      }
    end

    def self.allowed?(visibility, user, context = nil)
      visibility = normalize_visibility(visibility)
      return true if visibility.empty?

      context ||= build_context(user)

      return false if visibility["logged_in_only"] && context[:user].nil?
      return false if visibility["logged_out_only"] && context[:user].present?
      return false if visibility["trust_level_min"].to_i > context[:trust_level].to_i

      required_groups = Array(visibility["groups"]).map { |name| name.to_s.downcase }.reject(&:blank?)
      if required_groups.any?
        return false if context[:user].nil?
        return false if (required_groups & context[:group_names]).empty?
      end

      true
    end

    def self.normalize_visibility(visibility)
      return {} unless visibility.is_a?(Hash)

      visibility.slice(*SUPPORTED_KEYS).tap do |normalized|
        normalized["trust_level_min"] = normalized["trust_level_min"].to_i if normalized.key?("trust_level_min")
      end
    end
  end
end
