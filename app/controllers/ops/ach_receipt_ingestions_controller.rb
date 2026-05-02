# frozen_string_literal: true

module Ops
  class AchReceiptIngestionsController < ApplicationController
    SAMPLE_INPUT = {
      file_id: "file-20260425-001",
      batches: [
        {
          batch_id: "batch-1",
          items: [
            {
              item_id: "trace-091000019-000001",
              account_number: "126040000013",
              amount_minor_units: 12_500,
              currency: "USD"
            }
          ]
        }
      ]
    }.freeze

    def new
      @structured_input = JSON.pretty_generate(SAMPLE_INPUT)
      @business_date = current_business_date
    end

    def create
      @preview = params[:mode].to_s != "ingest"
      payload = parse_structured_input
      @structured_input = JSON.pretty_generate(payload)
      @business_date = business_date_param.presence || payload["business_date"].presence

      @result = Integration::Ach::Commands::IngestReceiptFile.call(
        file_id: payload.fetch("file_id"),
        batches: payload.fetch("batches"),
        business_date: @business_date.presence,
        preview: @preview
      )
      render :show, status: @preview ? :ok : :created
    rescue KeyError => e
      @error_message = "missing required field: #{e.key}"
      render_new_with_error
    rescue JSON::ParserError => e
      @error_message = "structured input must be valid JSON: #{e.message}"
      render_new_with_error
    rescue Integration::Ach::Commands::IngestReceiptFile::InvalidRequest,
           Core::OperationalEvents::Commands::RecordEvent::InvalidRequest => e
      @error_message = e.message
      render_new_with_error
    end

    private

    def parse_structured_input
      raw = uploaded_file_contents.presence || ingestion_params[:structured_input].to_s
      raise JSON::ParserError, "empty input" if raw.blank?

      parsed = JSON.parse(raw)
      unless parsed.is_a?(Hash)
        raise JSON::ParserError, "top-level JSON value must be an object"
      end

      parsed
    end

    def uploaded_file_contents
      upload = ingestion_params[:receipt_file]
      return nil if upload.blank?

      upload.read
    end

    def ingestion_params
      params.fetch(:ach_receipt_ingestion, {}).permit(:receipt_file, :structured_input, :business_date)
    end

    def business_date_param
      ingestion_params[:business_date].to_s.strip
    end

    def render_new_with_error
      @structured_input ||= ingestion_params[:structured_input].presence || JSON.pretty_generate(SAMPLE_INPUT)
      @business_date ||= business_date_param.presence || current_business_date
      render :new, status: :unprocessable_entity
    end

    def current_business_date
      Core::BusinessDate::Services::CurrentBusinessDate.call
    rescue Core::BusinessDate::Errors::NotSet
      nil
    end
  end
end
