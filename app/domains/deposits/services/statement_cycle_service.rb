# frozen_string_literal: true

module Deposits
  module Services
    class StatementCycleService
      Period = Data.define(:period_start_on, :period_end_on)

      def self.due_periods(profile:, account:, generated_on:, last_statement: nil)
        last_complete = last_completed_period(generated_on: generated_on, cycle_day: profile.cycle_day)
        return [] if last_complete.nil?

        start_on = if last_statement
          last_statement.period_end_on + 1.day
        else
          first_period_start_on(account: account, profile: profile)
        end

        periods = []
        while start_on <= last_complete.period_end_on
          period = period_for(date: start_on, cycle_day: profile.cycle_day)
          periods << period
          start_on = period.period_end_on + 1.day
        end
        periods
      end

      def self.last_completed_period(generated_on:, cycle_day:)
        return nil if generated_on.blank?

        current_period = period_for(date: generated_on, cycle_day: cycle_day)
        period_for(date: current_period.period_start_on - 1.day, cycle_day: cycle_day)
      end

      def self.period_for(date:, cycle_day:)
        anchor = anchor_on(date.year, date.month, cycle_day)
        start_on = date < anchor ? previous_anchor(anchor, cycle_day) : anchor
        Period.new(period_start_on: start_on, period_end_on: next_anchor(start_on, cycle_day) - 1.day)
      end

      def self.first_period_start_on(account:, profile:)
        opened_on = account.created_at.to_date
        first_activity_on = [ opened_on, profile.effective_on ].compact.max
        period_for(date: first_activity_on, cycle_day: profile.cycle_day).period_start_on
      end
      private_class_method :first_period_start_on

      def self.anchor_on(year, month, cycle_day)
        Date.new(year, month, [ cycle_day.to_i, Time.days_in_month(month, year) ].min)
      end
      private_class_method :anchor_on

      def self.previous_anchor(anchor, cycle_day)
        prev_month = anchor.prev_month
        anchor_on(prev_month.year, prev_month.month, cycle_day)
      end
      private_class_method :previous_anchor

      def self.next_anchor(anchor, cycle_day)
        next_month = anchor.next_month
        anchor_on(next_month.year, next_month.month, cycle_day)
      end
      private_class_method :next_anchor
    end
  end
end
