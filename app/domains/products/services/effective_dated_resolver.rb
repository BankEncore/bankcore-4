# frozen_string_literal: true

module Products
  module Services
    module EffectiveDatedResolver
      ACTIVE_STATUS = "active"

      def self.active_scope(scope, as_of:)
        on_date = as_of.to_date
        scope
          .where(status: ACTIVE_STATUS)
          .where("effective_on <= ?", on_date)
          .where("ended_on IS NULL OR ended_on >= ?", on_date)
      end

      def self.resolve_one(scope, as_of:)
        active_scope(scope, as_of: as_of).order(effective_on: :desc, id: :desc).first
      end

      def self.overlap?(record, constraints:)
        overlapping_active_scope(record, constraints: constraints).exists?
      end

      def self.overlapping_active_scope(record, constraints:)
        return record.class.none unless active_record_with_window?(record)

        scope = record.class.where(status: ACTIVE_STATUS)
        constraints.each do |attribute|
          value = record.public_send(attribute)
          return record.class.none if value.blank?

          scope = scope.where(attribute => value)
        end

        scope = scope.where.not(id: record.id) if record.persisted?
        scope = scope.where("effective_on <= ?", record.ended_on) if record.ended_on.present?
        scope.where("ended_on IS NULL OR ended_on >= ?", record.effective_on)
      end

      def self.active_record_with_window?(record)
        record.status == ACTIVE_STATUS && record.effective_on.present?
      end
      private_class_method :active_record_with_window?
    end
  end
end
