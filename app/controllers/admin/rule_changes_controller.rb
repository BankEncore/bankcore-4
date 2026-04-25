# frozen_string_literal: true

module Admin
  class RuleChangesController < ApplicationController
    RULE_PARAMS = [
      :deposit_product_id, :fee_code, :amount_minor_units, :mode, :nsf_fee_minor_units,
      :frequency, :cycle_day, :currency, :status, :effective_on, :ended_on, :description
    ].freeze

    def new
      @rule_kind = rule_kind
      @deposit_products = deposit_products
      @rule_attrs = default_rule_attrs
    end

    def preview
      @rule_kind = rule_kind
      @deposit_products = deposit_products
      @rule_attrs = rule_params
      @result = Products::Commands::ManageEffectiveDatedRule.preview_create(
        rule_kind: @rule_kind,
        attributes: @rule_attrs
      )
      render :preview
    rescue Products::Commands::ManageEffectiveDatedRule::InvalidRequest => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def create
      @rule_kind = rule_kind
      @result = Products::Commands::ManageEffectiveDatedRule.create(
        rule_kind: @rule_kind,
        attributes: rule_params
      )
      redirect_to index_path_for(@rule_kind), notice: "Created #{rule_kind_label(@rule_kind).downcase} ##{@result.rule.id}."
    rescue Products::Commands::ManageEffectiveDatedRule::InvalidRequest => e
      @deposit_products = deposit_products
      @rule_attrs = rule_params
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def preview_end_date
      @rule_kind = rule_kind
      @ended_on = params.dig(:rule_change, :ended_on)
      @result = Products::Commands::ManageEffectiveDatedRule.preview_end_date(
        rule_kind: @rule_kind,
        rule_id: params[:id],
        ended_on: @ended_on
      )
      render :preview_end_date
    rescue Products::Commands::ManageEffectiveDatedRule::InvalidRequest => e
      redirect_to index_path_for(@rule_kind), alert: e.message
    end

    def end_date
      @rule_kind = rule_kind
      result = Products::Commands::ManageEffectiveDatedRule.end_date(
        rule_kind: @rule_kind,
        rule_id: params[:id],
        ended_on: params.dig(:rule_change, :ended_on)
      )
      redirect_to index_path_for(@rule_kind), notice: "End-dated #{rule_kind_label(@rule_kind).downcase} ##{result.rule.id}."
    rescue Products::Commands::ManageEffectiveDatedRule::InvalidRequest => e
      redirect_to index_path_for(@rule_kind), alert: e.message
    end

    private

    def rule_kind
      kind = params[:rule_kind].to_s
      unless Products::Commands::ManageEffectiveDatedRule::RULES.key?(kind)
        raise ActionController::RoutingError, "unknown rule kind"
      end

      kind
    end

    def rule_params
      params.require(:rule_change).permit(*RULE_PARAMS).to_h.symbolize_keys
    end

    def default_rule_attrs
      params.permit(:deposit_product_id).to_h.symbolize_keys
    end

    def deposit_products
      Products::Models::DepositProduct.order(:product_code)
    end

    def index_path_for(kind)
      case kind
      when "fee_rule"
        admin_deposit_product_fee_rules_path
      when "overdraft_policy"
        admin_deposit_product_overdraft_policies_path
      when "statement_profile"
        admin_deposit_product_statement_profiles_path
      end
    end

    def rule_kind_label(kind)
      case kind
      when "fee_rule"
        "Fee rule"
      when "overdraft_policy"
        "Overdraft policy"
      when "statement_profile"
        "Statement profile"
      end
    end
  end
end
