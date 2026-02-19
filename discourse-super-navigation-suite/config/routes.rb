# frozen_string_literal: true

DiscourseSuperNavigationSuite::Engine.routes.draw do
  get "/navigation/config" => "navigation#config"
  get "/navigation/panel" => "navigation#panel"
  get "/navigation/presets" => "navigation#presets"
  get "/navigation/export" => "navigation#export"
  post "/navigation/import" => "navigation#import"
end
