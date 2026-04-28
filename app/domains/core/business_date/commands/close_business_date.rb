# frozen_string_literal: true

module Core
  module BusinessDate
    module Commands
      # ADR-0018: advance singleton only after ADR-0016 EOD readiness; append-only audit row.
      class CloseBusinessDate
        # @param closed_by_operator_id [Integer, nil] workspace operator who initiated close (Teller supervisor)
        # @param business_date [Date, nil] when present, must equal current open day
        # @return [Hash] :setting (reload), :closed_on (Date), :previous_business_on (same as closed_on)
        def self.call(closed_by_operator_id: nil, business_date: nil)
          Workspace::Authorization::Authorizer.require_capability!(
            actor_id: closed_by_operator_id,
            capability_code: Workspace::Authorization::CapabilityRegistry::BUSINESS_DATE_CLOSE
          )

          Models::BusinessDateSetting.transaction do
            setting = Models::BusinessDateSetting.lock.first
            raise Errors::NotSet, "core_business_date_settings has no row" if setting.nil?

            closing_on = setting.current_business_on
            if business_date.present?
              requested = business_date.is_a?(Date) ? business_date : Date.iso8601(business_date.to_s)
              unless requested == closing_on
                raise ArgumentError,
                  "business_date must match current open day (#{closing_on.iso8601}), was #{requested.iso8601}"
              end
            end

            readiness = Teller::Queries::EodReadiness.call(business_date: closing_on)
            unless readiness[:eod_ready]
              raise Errors::EodNotReady.new("EOD readiness checks failed for #{closing_on.iso8601}", readiness)
            end

            next_on = closing_on + 1.day
            setting.update!(current_business_on: next_on)

            Models::BusinessDateCloseEvent.create!(
              closed_on: closing_on,
              closed_at: Time.current,
              closed_by_operator_id: closed_by_operator_id
            )

            {
              setting: setting.reload,
              closed_on: closing_on,
              previous_business_on: closing_on
            }
          end
        end
      end
    end
  end
end
