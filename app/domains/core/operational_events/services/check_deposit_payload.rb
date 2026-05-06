# frozen_string_literal: true

require "digest"
require "json"

module Core
  module OperationalEvents
    module Services
      # Normalizes and validates `check.deposit.accepted` payload per ADR-0040 / T1 plan.
      module CheckDepositPayload
        EVENT_TYPE = "check.deposit.accepted"
        MAX_ITEMS = 100
        MAX_SERIALIZED_BYTES = 65_536
        CLASSIFICATIONS = %w[on_us transit unknown].freeze
        LEGACY_IDENTITY_KEYS = %w[item_reference serial_number].freeze
        STRUCTURED_IDENTITY_KEYS = %w[routing_number account_number check_serial_number].freeze

        module_function

        # @param raw_payload [Hash, ActionController::Parameters]
        # @param amount_minor_units [Integer] event header total — must equal sum(items amounts)
        # @return [Hash] canonical payload with string keys (persist / fingerprint source)
        # @raise [Core::OperationalEvents::Commands::RecordEvent::InvalidRequest]
        def normalize!(raw_payload, amount_minor_units:)
          invalid = Core::OperationalEvents::Commands::RecordEvent::InvalidRequest
          raise invalid, "payload is required for #{EVENT_TYPE}" if raw_payload.blank?

          hash = raw_payload.respond_to?(:to_unsafe_h) ? raw_payload.to_unsafe_h : raw_payload.to_h
          hash = hash.stringify_keys
          extra_root = hash.keys - %w[items]
          if extra_root.any?
            raise invalid, "unknown payload keys: #{extra_root.sort.join(", ")}"
          end

          items = hash["items"]
          unless items.is_a?(Array) && items.present?
            raise invalid, "payload.items must be a non-empty array"
          end
          if items.size > MAX_ITEMS
            raise invalid, "payload.items exceeds maximum of #{MAX_ITEMS}"
          end

          canonical_items = []
          seen_keys = {}

          items.each_with_index do |raw_item, idx|
            unless raw_item.is_a?(Hash) || raw_item.respond_to?(:to_unsafe_h)
              raise invalid, "payload.items[#{idx}] must be an object"
            end
            item = raw_item.respond_to?(:to_unsafe_h) ? raw_item.to_unsafe_h : raw_item.to_h
            item = item.stringify_keys

            unknown_item_keys = item.keys - %w[
              amount_minor_units
              item_reference
              serial_number
              routing_number
              account_number
              check_serial_number
              classification
            ]
            if unknown_item_keys.any?
              raise invalid,
                    "payload.items[#{idx}] unknown keys: #{unknown_item_keys.sort.join(", ")}"
            end

            unless item.key?("amount_minor_units")
              raise invalid, "payload.items[#{idx}].amount_minor_units is required"
            end

            amt = item["amount_minor_units"].to_i
            raise invalid, "payload.items[#{idx}].amount_minor_units must be positive" unless amt.positive?

            legacy_present = LEGACY_IDENTITY_KEYS.select { |key| item[key].present? }
            structured_present = STRUCTURED_IDENTITY_KEYS.select { |key| item[key].present? }

            if legacy_present.any? && structured_present.any?
              raise invalid,
                    "payload.items[#{idx}] must use either legacy identity or structured check identity, not both"
            end

            canonical_item = {
              "amount_minor_units" => amt
            }

            item_key =
              if structured_present.any?
                unless structured_present.sort == STRUCTURED_IDENTITY_KEYS.sort
                  missing = STRUCTURED_IDENTITY_KEYS - structured_present
                  raise invalid,
                        "payload.items[#{idx}] structured identity requires: #{missing.join(", ")}"
                end

                routing_number = item["routing_number"].to_s.strip
                account_number = item["account_number"].to_s.strip
                check_serial_number = item["check_serial_number"].to_s.strip
                if [ routing_number, account_number, check_serial_number ].any?(&:blank?)
                  raise invalid,
                        "payload.items[#{idx}] structured identity fields cannot be blank"
                end

                canonical_item["routing_number"] = routing_number
                canonical_item["account_number"] = account_number
                canonical_item["check_serial_number"] = check_serial_number
                [ routing_number, account_number, check_serial_number ].join(":")
              else
                if legacy_present.size != 1
                  raise invalid,
                        "payload.items[#{idx}] must set exactly one of item_reference or serial_number, or all structured check identity fields"
                end

                legacy_key = legacy_present.first
                legacy_value = item[legacy_key].to_s.strip
                if legacy_value.blank?
                  raise invalid,
                        "payload.items[#{idx}] identity field cannot be blank"
                end

                canonical_item[legacy_key] = legacy_value
                legacy_value
              end

            if seen_keys[item_key]
              raise invalid, "duplicate item identity #{item_key.inspect}"
            end
            seen_keys[item_key] = true

            if item.key?("classification") && item["classification"].present?
              cls = item["classification"].to_s
              unless CLASSIFICATIONS.include?(cls)
                raise invalid,
                      "payload.items[#{idx}].classification must be one of: #{CLASSIFICATIONS.join(", ")}"
              end
              canonical_item["classification"] = cls
            end

            canonical_items << [ item_key, amt, canonical_item ]
          end

          canonical_items.sort_by! { |(key, amt, _)| [ key, amt ] }
          sum = canonical_items.sum { |(_, amt, _)| amt }
          unless sum == amount_minor_units.to_i
            raise invalid,
                  "sum of payload.items amounts (#{sum}) must equal amount_minor_units (#{amount_minor_units})"
          end

          out = { "items" => canonical_items.map { |(_, _, ci)| ci } }
          json = JSON.generate(out)
          if json.bytesize > MAX_SERIALIZED_BYTES
            raise invalid, "payload exceeds maximum serialized size"
          end

          out
        end

        def digest(canonical_payload)
          stable_json =
            JSON.generate(deep_sort_keys_for_digest(canonical_payload))
          Digest::SHA256.hexdigest(stable_json)
        end

        def deep_sort_keys_for_digest(obj)
          case obj
          when Hash
            obj.keys.sort.each_with_object({}) do |k, acc|
              acc[k.to_s] = deep_sort_keys_for_digest(obj[k])
            end
          when Array
            obj.map { |e| deep_sort_keys_for_digest(e) }
          else
            obj
          end
        end

        def payload_summary(canonical_payload)
          items =
            if canonical_payload.is_a?(Hash)
              canonical_payload["items"] || canonical_payload[:items]
            end
          items ||= []
          masked =
            items.map do |it|
              it = it.respond_to?(:stringify_keys) ? it.stringify_keys : it.to_h.stringify_keys
              if structured_identity?(it)
                {
                  "routing_number_masked" => mask_identity(it["routing_number"].to_s),
                  "account_number_masked" => mask_identity(it["account_number"].to_s),
                  "check_serial_number_masked" => mask_identity(it["check_serial_number"].to_s)
                }
              else
                ref = it["item_reference"].presence || it["serial_number"].presence

                { "item_reference_masked" => mask_identity(ref.to_s) }
              end
            end
          {
            "items_count" => items.size,
            "amount_minor_units_total" => items.sum { |it| it.stringify_keys["amount_minor_units"].to_i },
            "items_masked" => masked
          }
        end

        def mask_identity(ref)
          s = ref.to_s
          return s if s.length <= 4

          "#{"*" * (s.length - 4)}#{s[-4..]}"
        end

        def structured_identity?(item)
          STRUCTURED_IDENTITY_KEYS.all? { |key| item[key].present? }
        end
      end
    end
  end
end
