# frozen_string_literal: true

module Party
  module Commands
    class UpdateContactPoint
      class Error < StandardError; end
      class InvalidRequest < Error; end

      CONTACT_TYPES = %w[email phone address].freeze

      def self.call(party_record_id:, contact_type:, purpose:, idempotency_key:, actor_id:, channel: "branch",
        effective_on: nil, value: nil, attributes: {})
        ch = normalize_channel!(channel)
        type = normalize_contact_type!(contact_type)
        business_date = current_business_date
        on_date = normalize_date(effective_on.presence || business_date, "effective_on")
        validate_not_backdated!(on_date, business_date, "effective_on")

        Models::PartyRecord.transaction(requires_new: true) do
          existing = Models::PartyContactAudit.lock.find_by(channel: ch, idempotency_key: idempotency_key)
          if existing
            return replay(existing, party_record_id, type, purpose)
          end

          party = Models::PartyRecord.lock.find_by(id: party_record_id)
          raise InvalidRequest, "party_record_id not found" if party.nil?

          actor = authorize_actor!(actor_id)
          model = model_for(type)
          normalized_attrs = attributes_for(type, purpose, value, attributes, on_date)
          previous_contacts = model.active.where(party_record_id: party.id, purpose: normalized_attrs.fetch(:purpose)).to_a
          previous_contacts.each do |contact|
            contact.update!(status: "inactive", ended_on: on_date)
            create_audit!(
              party: party,
              contact: contact,
              action: Models::PartyContactAudit::ACTION_SUPERSEDED,
              channel: ch,
              idempotency_key: "superseded:#{idempotency_key}:#{contact.id}",
              business_date: business_date,
              actor: actor,
              old_summary: contact.summary,
              new_summary: nil
            )
          end

          contact = model.create!(normalized_attrs.merge(party_record: party))
          audit = create_audit!(
            party: party,
            contact: contact,
            action: Models::PartyContactAudit::ACTION_ADDED,
            channel: ch,
            idempotency_key: idempotency_key,
            business_date: business_date,
            actor: actor,
            old_summary: previous_contacts.map(&:summary).join(" | ").presence,
            new_summary: contact.summary
          )
          { outcome: :created, contact: contact, audit: audit }
        end
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidRequest, e.record.errors.full_messages.to_sentence
      rescue Workspace::Authorization::Forbidden,
        Core::BusinessDate::Errors::InvalidPostingBusinessDate,
        Core::BusinessDate::Errors::NotSet => e
        raise InvalidRequest, e.message
      end

      def self.normalize_channel!(channel)
        return "branch" if channel.to_s == "branch"

        raise InvalidRequest, "channel must be branch"
      end
      private_class_method :normalize_channel!

      def self.normalize_contact_type!(contact_type)
        type = contact_type.to_s
        return type if CONTACT_TYPES.include?(type)

        raise InvalidRequest, "contact_type must be one of: #{CONTACT_TYPES.join(', ')}"
      end
      private_class_method :normalize_contact_type!

      def self.current_business_date
        Core::BusinessDate::Services::CurrentBusinessDate.call.tap do |business_date|
          Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: business_date)
        end
      end
      private_class_method :current_business_date

      def self.normalize_date(value, field)
        value.to_date
      rescue ArgumentError, TypeError, NoMethodError
        raise InvalidRequest, "#{field} must be a valid date"
      end
      private_class_method :normalize_date

      def self.validate_not_backdated!(date, business_date, field)
        return if date >= business_date

        raise InvalidRequest, "#{field} cannot be before the current business date"
      end
      private_class_method :validate_not_backdated!

      def self.authorize_actor!(actor_id)
        Workspace::Authorization::Authorizer.require_capability!(
          actor_id: actor_id,
          capability_code: Workspace::Authorization::CapabilityRegistry::PARTY_CONTACT_UPDATE
        )
      end
      private_class_method :authorize_actor!

      def self.model_for(contact_type)
        {
          "email" => Models::PartyEmail,
          "phone" => Models::PartyPhone,
          "address" => Models::PartyAddress
        }.fetch(contact_type)
      end
      private_class_method :model_for

      def self.attributes_for(contact_type, purpose, value, attrs, effective_on)
        case contact_type
        when "email"
          { email: required(value, "email"), purpose: required(purpose, "purpose"), effective_on: effective_on }
        when "phone"
          { phone_number: required(value, "phone_number"), purpose: required(purpose, "purpose"), effective_on: effective_on }
        when "address"
          hash = attrs.with_indifferent_access
          {
            line1: required(hash[:line1], "line1"),
            line2: hash[:line2].presence,
            city: required(hash[:city], "city"),
            region: required(hash[:region], "region"),
            postal_code: required(hash[:postal_code], "postal_code"),
            country: hash[:country].presence || "US",
            purpose: required(purpose, "purpose"),
            effective_on: effective_on
          }
        end
      end
      private_class_method :attributes_for

      def self.required(value, field_name)
        normalized = value.to_s.strip
        raise InvalidRequest, "#{field_name} is required" if normalized.blank?

        normalized
      end
      private_class_method :required

      def self.create_audit!(party:, contact:, action:, channel:, idempotency_key:, business_date:, actor:, old_summary:, new_summary:)
        Models::PartyContactAudit.create!(
          party_record: party,
          contact_table: contact.class.table_name,
          contact_id: contact.id,
          action: action,
          channel: channel,
          idempotency_key: idempotency_key,
          business_date: business_date,
          actor: actor,
          old_summary: old_summary,
          new_summary: new_summary
        )
      end
      private_class_method :create_audit!

      def self.replay(existing, party_record_id, contact_type, purpose)
        raise InvalidRequest, "idempotency replay mismatch" unless existing.party_record_id == party_record_id.to_i
        raise InvalidRequest, "idempotency replay mismatch" unless existing.contact_table == model_for(contact_type).table_name

        contact = model_for(contact_type).find(existing.contact_id)
        raise InvalidRequest, "idempotency replay mismatch" unless contact.purpose == purpose.to_s

        { outcome: :replay, contact: contact, audit: existing }
      end
      private_class_method :replay
    end
  end
end
