# frozen_string_literal: true

require "rails_helper"

describe DiscourseSuperNavigationSuite::NavigationController do
  fab!(:user) { Fabricate(:user) }

  before do
    SiteSetting.super_navigation_suite_enabled = true
    SiteSetting.super_navigation_suite_json = {
      version: 1,
      menus: [
        {
          id: "primary",
          placement: "top_nav",
          items: [{ id: "latest", title: "Latest", type: "link", url: "/latest" }],
        },
      ],
    }.to_json
  end

  it "returns config for signed in user" do
    sign_in(user)
    get "/super-navigation-suite/navigation/config"

    expect(response.status).to eq(200)
    parsed = response.parsed_body
    expect(parsed["menus"].first["id"]).to eq("primary")
  end

  it "returns panel payload" do
    sign_in(user)
    get "/super-navigation-suite/navigation/panel", params: { source_type: "latest", limit: 3 }

    expect(response.status).to eq(200)
    expect(response.parsed_body).to have_key("topics")
  end

  it "normalizes unsupported panel params safely" do
    sign_in(user)
    get "/super-navigation-suite/navigation/panel",
        params: { source_type: "unknown", time_range: "bad", limit: 999 }

    expect(response.status).to eq(200)
    source = response.parsed_body["source"]
    expect(source["source_type"]).to eq("latest")
    expect(source["time_range"]).to eq("weekly")
    expect(source["limit"]).to eq(SiteSetting.super_navigation_suite_max_panel_items)
  end
end
