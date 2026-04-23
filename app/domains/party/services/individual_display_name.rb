# frozen_string_literal: true

module Party
  module Services
    # ADR-0009 §2.3 — display `party_records.name` for individuals (not preferred_* fields).
    class IndividualDisplayName
      def self.build(first_name:, last_name:, middle_name: nil, name_suffix: nil)
        parts = [ first_name, middle_name.presence, last_name ].compact
        base = parts.join(" ")
        name_suffix.present? ? "#{base}, #{name_suffix}" : base
      end
    end
  end
end
