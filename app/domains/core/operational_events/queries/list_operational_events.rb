# frozen_string_literal: true

module Core
  module OperationalEvents
    module Queries
      # Read-only observability listing (ADR-0017 product context, ADR-0016/0018 date rules).
      class ListOperationalEvents
        class InvalidQuery < StandardError; end

        MAX_SPAN_DAYS = 31
        DEFAULT_LIMIT = 50
        MAX_LIMIT = 200

        # @return [Hash] :rows (Array<OperationalEvent>), :envelope (Hash), :next_after_id, :has_more
        def self.call(
          business_date: nil,
          business_date_from: nil,
          business_date_to: nil,
          source_account_id: nil,
          destination_account_id: nil,
          status: nil,
          event_type: nil,
          channel: nil,
          actor_id: nil,
          deposit_product_id: nil,
          product_code: nil,
          after_id: nil,
          limit: nil
        )
          current = Core::BusinessDate::Services::CurrentBusinessDate.call
          from_date, to_date = resolve_range(
            business_date: business_date,
            business_date_from: business_date_from,
            business_date_to: business_date_to,
            current: current
          )
          validate_range!(from_date, to_date, current)

          lim = if limit.present?
            [ [ limit.to_i, 1 ].max, MAX_LIMIT ].min
          else
            DEFAULT_LIMIT
          end
          raise InvalidQuery, "limit must be between 1 and #{MAX_LIMIT}" unless lim.between?(1, MAX_LIMIT)

          scope = base_scope(
            from_date: from_date,
            to_date: to_date,
            source_account_id: source_account_id,
            destination_account_id: destination_account_id,
            status: status,
            event_type: event_type,
            channel: channel,
            actor_id: actor_id,
            deposit_product_id: deposit_product_id,
            product_code: product_code
          )

          scope = scope.where("operational_events.id > ?", after_id.to_i) if after_id.present?

          fetched = scope.order(:id).limit(lim + 1).includes(
            :posting_batches,
            { posting_batches: :journal_entries },
            { source_account: :deposit_product },
            { destination_account: :deposit_product }
          ).to_a

          has_more = fetched.size > lim
          rows = has_more ? fetched.take(lim) : fetched
          next_after_id = has_more ? rows.last.id : nil

          envelope = {
            current_business_on: current,
            posting_day_closed: to_date < current,
            business_date_from: from_date,
            business_date_to: to_date
          }

          { rows: rows, envelope: envelope, next_after_id: next_after_id, has_more: has_more }
        end

        def self.resolve_range(business_date:, business_date_from:, business_date_to:, current:)
          bd = parse_optional_date!(business_date)
          bf = parse_optional_date!(business_date_from)
          bt = parse_optional_date!(business_date_to)

          if bd && (bf || bt)
            raise InvalidQuery, "use either business_date or business_date_from/business_date_to, not both"
          end

          if bd
            [ bd, bd ]
          elsif bf || bt
            raise InvalidQuery, "business_date_from and business_date_to are both required" if bf.nil? || bt.nil?

            [ bf, bt ]
          else
            [ current, current ]
          end
        end
        private_class_method :resolve_range

        def self.parse_optional_date!(value)
          return nil if value.blank?

          return value if value.is_a?(Date)

          Date.iso8601(value.to_s)
        rescue ArgumentError, TypeError
          raise InvalidQuery, "invalid or malformed ISO date"
        end
        private_class_method :parse_optional_date!

        def self.validate_range!(from_date, to_date, current)
          raise InvalidQuery, "business_date_from must be on or before business_date_to" if from_date > to_date

          if (to_date - from_date).to_i + 1 > MAX_SPAN_DAYS
            raise InvalidQuery, "date range must not exceed #{MAX_SPAN_DAYS} days"
          end
          raise InvalidQuery, "business_date cannot be after current business date" if to_date > current
        end
        private_class_method :validate_range!

        def self.base_scope(from_date:, to_date:, source_account_id:, destination_account_id:, status:, event_type:,
                            channel:, actor_id:, deposit_product_id:, product_code:)
          scope = Models::OperationalEvent.where(business_date: from_date..to_date)
          scope = scope.where(source_account_id: source_account_id.to_i) if source_account_id.present?
          scope = scope.where(destination_account_id: destination_account_id.to_i) if destination_account_id.present?
          scope = scope.where(status: status.to_s) if status.present?
          scope = scope.where(event_type: event_type.to_s) if event_type.present?
          scope = scope.where(channel: channel.to_s) if channel.present?
          scope = scope.where(actor_id: actor_id.to_i) if actor_id.present?

          account_ids = matching_deposit_account_ids(deposit_product_id: deposit_product_id, product_code: product_code)
          if account_ids.nil?
            # no product filter
          elsif account_ids.empty?
            scope = scope.none
          else
            scope = scope.where(
              "operational_events.source_account_id IN (:ids) OR operational_events.destination_account_id IN (:ids)",
              ids: account_ids
            )
          end

          scope
        end
        private_class_method :base_scope

        # @return [Array<Integer>, nil] nil means no product filter
        def self.matching_deposit_account_ids(deposit_product_id:, product_code:)
          return nil if deposit_product_id.blank? && product_code.blank?

          rel = Accounts::Models::DepositAccount.all
          rel = rel.where(deposit_product_id: deposit_product_id.to_i) if deposit_product_id.present?
          rel = rel.where(product_code: product_code.to_s) if product_code.present?
          rel.pluck(:id)
        end
        private_class_method :matching_deposit_account_ids
      end
    end
  end
end
