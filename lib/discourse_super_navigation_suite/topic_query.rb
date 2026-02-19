# frozen_string_literal: true

require "digest"

module ::DiscourseSuperNavigationSuite
  class TopicQuery
    MAX_SERVER_LIMIT = 40
    ALLOWED_SOURCES = %w[latest category_latest category_top tag_latest featured].freeze
    TIME_RANGES = {
      "daily" => 1.day,
      "weekly" => 1.week,
      "monthly" => 1.month,
      "quarterly" => 3.months,
      "yearly" => 1.year,
      "all" => nil,
    }.freeze

    def self.fetch(user, params = {})
      new(user, params).fetch
    end

    def initialize(user, params = {})
      @user = user
      @guardian = Guardian.new(user)
      @params = params || {}
    end

    def fetch
      normalized = normalize_params
      cache_key = cache_key_for(normalized)

      Rails.cache.fetch(cache_key, expires_in: SiteSetting.super_navigation_suite_cache_minutes.minutes) do
        topics = apply_source(base_scope, normalized).limit(normalized[:limit])

        {
          source: normalized,
          topics: topics.map { |topic| serialize_topic(topic, normalized) },
        }
      end
    end

    private

    attr_reader :guardian, :params

    def normalize_params
      limit = params[:limit].to_i
      limit = 6 if limit <= 0
      limit = [limit, SiteSetting.super_navigation_suite_max_panel_items, MAX_SERVER_LIMIT].min

      {
        source_type: normalize_source_type(params[:source_type]),
        category_slug: params[:category_slug].to_s.presence,
        category_id: params[:category_id].to_i.positive? ? params[:category_id].to_i : nil,
        tag: params[:tag].to_s.presence,
        time_range: normalize_time_range(params[:time_range]),
        limit: limit,
      }
    end

    def cache_key_for(normalized)
      user_key = @user&.id || "anon"
      digest = Digest::SHA256.hexdigest(normalized.to_json)
      "sns:panel:v1:user:#{user_key}:#{digest}"
    end

    def base_scope
      Topic.visible
           .secured(guardian)
           .where(archetype: Archetype.default)
           .includes(:category, :user, :first_post)
    end

    def apply_source(scope, normalized)
      case normalized[:source_type]
      when "category_latest"
        scoped_by_category(scope, normalized)
          .order(bumped_at: :desc)
      when "category_top"
        apply_time_range(scoped_by_category(scope, normalized), normalized[:time_range])
          .order(like_count: :desc, views: :desc, posts_count: :desc)
      when "tag_latest"
        scoped_by_tag(scope, normalized).order(bumped_at: :desc)
      when "featured"
        scope.where("topics.pinned_globally = TRUE OR topics.pinned_at IS NOT NULL")
             .order(bumped_at: :desc)
      else
        apply_time_range(scope, normalized[:time_range]).order(bumped_at: :desc)
      end
    end

    def scoped_by_category(scope, normalized)
      category = find_category(normalized)
      return scope.none unless category

      scope.where(category_id: category.id)
    end

    def scoped_by_tag(scope, normalized)
      tag = normalized[:tag]
      return scope.none if tag.blank?

      scope.joins(:tags).where(tags: { name: tag }).distinct
    end

    def find_category(normalized)
      category =
        if normalized[:category_id].present?
          Category.find_by(id: normalized[:category_id])
        elsif normalized[:category_slug].present?
          Category.find_by(slug: normalized[:category_slug])
        end

      return nil unless category && guardian.can_see?(category)

      category
    end

    def apply_time_range(scope, time_range)
      window = TIME_RANGES[time_range] || TIME_RANGES["weekly"]
      return scope if window.nil?

      scope.where("topics.bumped_at >= ?", Time.zone.now - window)
    end

    def serialize_topic(topic, normalized)
      {
        id: topic.id,
        slug: topic.slug,
        title: topic.title,
        fancy_title: topic.fancy_title,
        url: topic.relative_url,
        created_at: topic.created_at,
        bumped_at: topic.bumped_at,
        posts_count: topic.posts_count,
        like_count: topic.like_count,
        views: topic.views,
        image_url: topic.image_url,
        excerpt: normalized[:source_type] == "featured" ? nil : topic_excerpt(topic),
        author_username: topic.user&.username,
        category: topic.category && {
          id: topic.category.id,
          name: topic.category.name,
          slug: topic.category.slug,
          color: topic.category.color,
          text_color: topic.category.text_color,
          url: "/c/#{topic.category.slug}/#{topic.category.id}",
        },
      }
    end

    def topic_excerpt(topic)
      cooked = topic.first_post&.cooked
      return nil if cooked.blank?

      PrettyText.excerpt(cooked, 140)
    end

    def normalize_source_type(raw_source)
      source = raw_source.to_s
      ALLOWED_SOURCES.include?(source) ? source : "latest"
    end

    def normalize_time_range(raw_time_range)
      range = raw_time_range.to_s
      TIME_RANGES.key?(range) ? range : "weekly"
    end
  end
end
