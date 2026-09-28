# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'base64'

class ResendDeliveryMethod
  RESEND_URL = URI('https://api.resend.com/emails').freeze
  DEFAULT_OPEN_TIMEOUT = 15
  DEFAULT_READ_TIMEOUT = 30

  class DeliveryError < StandardError; end

  attr_accessor :settings

  def initialize(settings = {})
    @settings = settings || {}
    @api_key = @settings[:api_key].presence || ENV.fetch('RESEND_API_KEY', nil)
    @open_timeout = (@settings[:open_timeout] || ENV['RESEND_OPEN_TIMEOUT'] || DEFAULT_OPEN_TIMEOUT).to_i
    @read_timeout = (@settings[:read_timeout] || ENV['RESEND_READ_TIMEOUT'] || DEFAULT_READ_TIMEOUT).to_i
  end

  def deliver!(mail)
    raise DeliveryError, 'RESEND_API_KEY is missing. Please configure RESEND_API_KEY in your environment or settings.' if @api_key.blank?

    payload = PayloadBuilder.new(mail).build
    send_request(payload, mail)
  end

  private

  def send_request(payload, mail)
    request = Net::HTTP::Post.new(RESEND_URL)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    request['User-Agent'] = 'Chatwoot-Resend/1.0'
    request.body = payload.to_json

    response = execute_http_request(request)
    handle_response(response, mail)
  end

  def execute_http_request(request)
    Net::HTTP.start(
      RESEND_URL.hostname,
      RESEND_URL.port,
      use_ssl: true,
      open_timeout: @open_timeout,
      read_timeout: @read_timeout
    ) do |http|
      http.request(request)
    end
  rescue StandardError => e
    raise DeliveryError, "Network error while connecting to Resend: #{e.message}"
  end

  def handle_response(response, mail)
    data = parse_json(response.body)

    unless response.is_a?(Net::HTTPSuccess)
      error_message = data['message'] || response.body
      error_name = data['name'] || "HTTP #{response.code}"
      raise DeliveryError, "Resend API error [#{error_name}]: #{error_message}"
    end

    if data['id'].present?
      mail.message_id = "<#{data['id']}@resend.dev>" if mail.message_id.blank?
      Rails.logger.info { "Resend successfully delivered email [#{data['id']}]" }
    end

    response
  end

  def parse_json(body)
    return {} if body.blank?

    JSON.parse(body)
  rescue StandardError
    {}
  end

  class PayloadBuilder
    IGNORED_HEADERS = %w[
      from
      to
      cc
      bcc
      subject
      reply-to
      content-type
      content-transfer-encoding
      mime-version
      date
      message-id
    ].freeze

    def initialize(mail)
      @mail = mail
    end

    def build
      payload = {
        from: sender_address,
        to: recipient_addresses,
        subject: @mail.subject.to_s
      }

      add_optional_fields(payload)
      payload
    end

    private

    def sender_address
      from = @mail[:from]&.to_s.presence || @mail.from&.join(', ')
      raise DeliveryError, 'Email sender (from) is missing' if from.blank?

      from
    end

    def recipient_addresses
      to = extract_recipients(@mail.to.presence || @mail[:to]&.to_s)
      raise DeliveryError, 'Email recipient (to) is missing' if to.empty?

      to
    end

    def add_optional_fields(payload)
      add_recipients(payload)
      add_content(payload)
      add_metadata(payload)
    end

    def add_recipients(payload)
      add_reply_to(payload)
      add_cc_bcc(payload)
    end

    def add_reply_to(payload)
      reply_to = extract_reply_to
      payload[:reply_to] = reply_to if reply_to.present?
    end

    def add_cc_bcc(payload)
      cc = extract_recipients(@mail.cc.presence || @mail[:cc]&.to_s)
      payload[:cc] = cc if cc.present?

      bcc = extract_recipients(@mail.bcc.presence || @mail[:bcc]&.to_s)
      payload[:bcc] = bcc if bcc.present?
    end

    def add_content(payload)
      html, text = extract_body
      payload[:html] = html if html.present?
      payload[:text] = text if text.present?
      payload[:text] = '' if payload[:html].blank? && payload[:text].blank?
    end

    def add_metadata(payload)
      headers = extract_headers
      payload[:headers] = headers if headers.present?

      attachments = extract_attachments
      payload[:attachments] = attachments if attachments.present?
    end

    def extract_recipients(recipients)
      return [] if recipients.blank?

      Array(recipients).flat_map { |r| r.to_s.split(',') }.map(&:strip).reject(&:blank?)
    end

    def extract_reply_to
      return @mail[:reply_to].to_s if @mail[:reply_to].present?
      return if @mail.reply_to.blank?

      recipients = Array(@mail.reply_to).map(&:strip).reject(&:blank?)
      recipients.one? ? recipients.first : recipients
    end

    def extract_body
      html, text = @mail.multipart? ? extract_multipart_body : extract_singlepart_body
      return [html, text] if html.present? || text.present?

      fallback_body(@mail.body&.decoded)
    end

    def extract_multipart_body
      html = @mail.html_part&.body&.decoded
      text = @mail.text_part&.body&.decoded
      return [html, text] if html.present? || text.present?

      extract_parts_body
    end

    def extract_parts_body
      html = @mail.parts.find { |p| p.mime_type == 'text/html' }&.body&.decoded
      text = @mail.parts.find { |p| p.mime_type == 'text/plain' }&.body&.decoded
      [html, text]
    end

    def extract_singlepart_body
      if @mail.mime_type == 'text/html'
        [@mail.body&.decoded, nil]
      else
        [nil, @mail.body&.decoded]
      end
    end

    def fallback_body(decoded)
      return [nil, nil] if decoded.blank?

      decoded.match?(/<[a-z][\s\S]*>/i) ? [decoded, nil] : [nil, decoded]
    end

    def extract_headers
      headers = {}
      append_in_reply_to(headers)
      append_references(headers)
      append_custom_headers(headers)
      headers
    end

    def append_in_reply_to(headers)
      raw = @mail['In-Reply-To']&.value || @mail.in_reply_to
      return if raw.blank?

      cleaned = raw.to_s.strip
      headers['In-Reply-To'] = cleaned.start_with?('<') && cleaned.end_with?('>') ? cleaned : "<#{cleaned}>"
    end

    def append_references(headers)
      raw = @mail['References']&.value || (Array(@mail.references).join(' ') if @mail.references.present?)
      return if raw.blank?

      headers['References'] = raw.to_s.gsub(/\r?\n\s*/, ' ').strip
    end

    def append_custom_headers(headers)
      @mail.header.fields.each do |field|
        name = field.name
        next if IGNORED_HEADERS.include?(name.downcase)
        next if name.casecmp?('in-reply-to') || name.casecmp?('references')

        headers[name] = field.value.to_s.gsub(/\r?\n\s*/, ' ').strip
      end
    end

    def extract_attachments
      return [] if @mail.attachments.blank?

      @mail.attachments.map { |part| format_attachment(part) }
    end

    def format_attachment(part)
      attachment = {
        filename: part.filename.presence || 'attachment',
        content: Base64.strict_encode64(part.body ? part.body.decoded.to_s : '')
      }
      attachment[:content_type] = part.mime_type if part.mime_type.present?
      attachment[:content_id] = part.cid.to_s.gsub(/[<>]/, '') if part.inline? && part.cid.present?
      attachment
    end
  end
end
