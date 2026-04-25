# frozen_string_literal: true

module Products
  module Commands
    class ManageEffectiveDatedRule
      class Error < StandardError; end
      class InvalidRequest < Error; end

      Result = Data.define(:action, :rule, :superseded_rules, :preview)

      RULES = {
        "fee_rule" => {
          model: Models::DepositProductFeeRule,
          discriminator: :fee_code,
          default_type: Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
          value_attr: :amount_minor_units
        },
        "overdraft_policy" => {
          model: Models::DepositProductOverdraftPolicy,
          discriminator: :mode,
          default_type: Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
          value_attr: :nsf_fee_minor_units
        },
        "statement_profile" => {
          model: Models::DepositProductStatementProfile,
          discriminator: :frequency,
          default_type: Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
          value_attr: :cycle_day
        }
      }.freeze

      def self.preview_create(rule_kind:, attributes:)
        change = new(rule_kind: rule_kind, attributes: attributes)
        change.preview_create
      end

      def self.create(rule_kind:, attributes:)
        change = new(rule_kind: rule_kind, attributes: attributes)
        change.create
      end

      def self.preview_end_date(rule_kind:, rule_id:, ended_on:)
        change = new(rule_kind: rule_kind)
        change.preview_end_date(rule_id: rule_id, ended_on: ended_on)
      end

      def self.end_date(rule_kind:, rule_id:, ended_on:)
        change = new(rule_kind: rule_kind)
        change.end_date(rule_id: rule_id, ended_on: ended_on)
      end

      def initialize(rule_kind:, attributes: {})
        @rule_kind = rule_kind.to_s
        @config = RULES.fetch(@rule_kind) { raise InvalidRequest, "unsupported rule kind: #{rule_kind.inspect}" }
        @attributes = attributes.to_h.symbolize_keys
      end

      def preview_create
        rule = build_rule
        validate_rule!(rule)
        validate_overlaps_for_create!(rule)

        Result.new(action: :create, rule: rule, superseded_rules: overlapping_rules(rule).to_a, preview: true)
      end

      def create
        model.transaction do
          preview = preview_create
          preview.superseded_rules.each { |existing| supersede!(existing, preview.rule.effective_on) }
          preview.rule.save!
          Result.new(action: :create, rule: preview.rule, superseded_rules: preview.superseded_rules, preview: false)
        end
      end

      def preview_end_date(rule_id:, ended_on:)
        rule = find_rule(rule_id)
        date = parse_date!(ended_on, "ended_on")
        validate_end_date!(rule, date)
        preview = rule.dup
        preview.id = rule.id
        preview.ended_on = date

        Result.new(action: :end_date, rule: preview, superseded_rules: [], preview: true)
      end

      def end_date(rule_id:, ended_on:)
        model.transaction do
          rule = find_rule(rule_id)
          date = parse_date!(ended_on, "ended_on")
          validate_end_date!(rule, date)
          rule.update!(ended_on: date)
          Result.new(action: :end_date, rule: rule, superseded_rules: [], preview: false)
        end
      end

      private

      attr_reader :attributes, :config

      def model
        config.fetch(:model)
      end

      def build_rule
        product = Models::DepositProduct.find_by(id: required_integer(:deposit_product_id))
        raise InvalidRequest, "deposit_product_id not found" if product.nil?

        model.new(
          deposit_product: product,
          config.fetch(:discriminator) => attributes[config.fetch(:discriminator)].presence || config.fetch(:default_type),
          config.fetch(:value_attr) => required_integer(config.fetch(:value_attr)),
          currency: attributes[:currency].presence || product.currency,
          status: attributes[:status].presence || status_active,
          effective_on: parse_date!(attributes[:effective_on], "effective_on"),
          ended_on: parse_optional_date!(attributes[:ended_on], "ended_on"),
          description: attributes[:description].presence
        )
      end

      def validate_rule!(rule)
        raise InvalidRequest, rule.errors.full_messages.to_sentence unless rule.valid?
      end

      def validate_overlaps_for_create!(rule)
        conflicts = overlapping_rules(rule).select { |existing| existing.effective_on >= rule.effective_on }.to_a
        return if conflicts.empty?

        ids = conflicts.map(&:id).join(", ")
        raise InvalidRequest, "new effective_on must be after overlapping active rows (ids: #{ids})"
      end

      def overlapping_rules(rule)
        model
          .where(deposit_product_id: rule.deposit_product_id, config.fetch(:discriminator) => rule.public_send(config.fetch(:discriminator)))
          .where(status: status_active)
          .where("effective_on <= ?", rule.ended_on || Date.new(9999, 12, 31))
          .where("ended_on IS NULL OR ended_on >= ?", rule.effective_on)
          .order(:effective_on, :id)
      end

      def supersede!(existing, effective_on)
        ended_on = effective_on - 1.day
        validate_end_date!(existing, ended_on)
        existing.update!(ended_on: ended_on)
      end

      def validate_end_date!(rule, ended_on)
        if ended_on < rule.effective_on
          raise InvalidRequest, "ended_on must be on or after effective_on (#{rule.effective_on.iso8601})"
        end
      end

      def find_rule(rule_id)
        model.find_by(id: rule_id).tap do |rule|
          raise InvalidRequest, "#{@rule_kind} id not found" if rule.nil?
        end
      end

      def required_integer(name)
        value = attributes[name]
        raise InvalidRequest, "#{name} is required" if value.blank?

        Integer(value)
      rescue ArgumentError, TypeError
        raise InvalidRequest, "#{name} must be an integer"
      end

      def parse_date!(value, name)
        raise InvalidRequest, "#{name} is required" if value.blank?

        Date.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        raise InvalidRequest, "#{name} must be a valid ISO 8601 date (YYYY-MM-DD)"
      end

      def parse_optional_date!(value, name)
        return nil if value.blank?

        parse_date!(value, name)
      end

      def status_active
        model::STATUS_ACTIVE
      end
    end
  end
end
