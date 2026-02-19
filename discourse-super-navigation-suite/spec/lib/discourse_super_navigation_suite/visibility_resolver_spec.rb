# frozen_string_literal: true

require "rails_helper"

describe DiscourseSuperNavigationSuite::VisibilityResolver do
  describe ".allowed?" do
    it "allows visible item when no rules exist" do
      context = { user: nil, trust_level: 0, group_names: [] }
      expect(described_class.allowed?({}, nil, context)).to eq(true)
    end

    it "blocks logged in only items for anon users" do
      context = { user: nil, trust_level: 0, group_names: [] }
      visibility = { "logged_in_only" => true }

      expect(described_class.allowed?(visibility, nil, context)).to eq(false)
    end

    it "checks trust level minimum" do
      context = { user: double(:user), trust_level: 1, group_names: [] }
      visibility = { "trust_level_min" => 2 }

      expect(described_class.allowed?(visibility, nil, context)).to eq(false)
    end

    it "checks group intersection" do
      context = { user: double(:user), trust_level: 4, group_names: %w[staff mods] }
      visibility = { "groups" => %w[staff] }

      expect(described_class.allowed?(visibility, nil, context)).to eq(true)
    end
  end
end
