# frozen_string_literal: true

module Party
  module Queries
    class PartySearch
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 50

      Result = Data.define(:rows, :query, :limit)

      def self.call(query:, limit: nil)
        q = query.to_s.strip
        lim = normalized_limit(limit)
        return Result.new(rows: [], query: q, limit: lim) if q.blank?

        scope = Models::PartyRecord
          .left_outer_joins(:individual_profile)
          .includes(:individual_profile)
          .distinct

        scope = if q.match?(/\A\d+\z/)
          scope.where(id: q.to_i)
            .or(text_search_scope(scope, q))
        else
          text_search_scope(scope, q)
        end

        Result.new(rows: scope.order(:name, :id).limit(lim).to_a, query: q, limit: lim)
      end

      def self.normalized_limit(limit)
        return DEFAULT_LIMIT if limit.blank?

        [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min
      end
      private_class_method :normalized_limit

      def self.text_search_scope(scope, query)
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
        scope.where(
          "LOWER(party_records.name) LIKE :pattern OR " \
            "LOWER(party_individual_profiles.first_name) LIKE :pattern OR " \
            "LOWER(party_individual_profiles.last_name) LIKE :pattern OR " \
            "LOWER(party_individual_profiles.preferred_first_name) LIKE :pattern OR " \
            "LOWER(party_individual_profiles.preferred_last_name) LIKE :pattern",
          pattern: pattern
        )
      end
      private_class_method :text_search_scope
    end
  end
end
