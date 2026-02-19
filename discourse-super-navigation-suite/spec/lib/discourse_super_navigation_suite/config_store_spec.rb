# frozen_string_literal: true

require "rails_helper"

describe DiscourseSuperNavigationSuite::ConfigStore do
  describe ".valid_json?" do
    it "returns true for valid object JSON" do
      expect(described_class.valid_json?("{\"version\":1}")).to eq(true)
    end

    it "returns false for invalid JSON" do
      expect(described_class.valid_json?("{bad_json")).to eq(false)
    end

    it "accepts valid JSON objects even when optional fields are not normalized yet" do
      json = { version: 1, menus: "invalid" }.to_json
      expect(described_class.valid_json?(json)).to eq(true)
    end
  end

  describe ".visible_config" do
    fab!(:user) { Fabricate(:user, trust_level: 2) }

    it "filters menu items by trust level rules" do
      SiteSetting.super_navigation_suite_json = {
        version: 1,
        menus: [
          {
            id: "primary",
            items: [
              { id: "public", title: "Public", type: "link", url: "/" },
              {
                id: "hidden",
                title: "Hidden",
                type: "link",
                url: "/top",
                visibility: { trust_level_min: 3 },
              },
            ],
          },
        ],
      }.to_json

      config = described_class.visible_config(user)
      ids = config["menus"].first["items"].map { |item| item["id"] }

      expect(ids).to contain_exactly("public")
    end

    it "sanitizes unsafe item URLs" do
      SiteSetting.super_navigation_suite_json = {
        version: 1,
        menus: [
          {
            id: "primary",
            items: [
              { id: "safe", title: "Safe", type: "link", url: "/latest" },
              { id: "unsafe", title: "Unsafe", type: "link", url: "javascript:alert(1)" },
            ],
          },
        ],
      }.to_json

      config = described_class.visible_config(user)
      items = config["menus"].first["items"].index_by { |item| item["id"] }

      expect(items["safe"]["resolved_url"]).to eq("/latest")
      expect(items["unsafe"]["resolved_url"]).to be_nil
    end
  end
end
