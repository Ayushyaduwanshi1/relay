require 'net/http'
require 'uri'
require 'json'

class ResendDeliveryMethod
  RESEND_URL = URI('https://api.resend.com/emails')

  def initialize(settings = {})
    @api_key = settings[:api_key] || ENV['RESEND_API_KEY']
  end

  def deliver!(mail)
    raise 'RESEND_API_KEY is missing' if @api_key.blank?

    payload = {
      from: mail.from.join(', '),
      to: mail.to,
      subject: mail.subject,
      html: mail.html_part&.body&.decoded || mail.body.decoded
    }

    payload[:text] = mail.text_part.body.decoded if mail.text_part
    payload[:cc] = mail.cc if mail.cc.present?
    payload[:bcc] = mail.bcc if mail.bcc.present?

    request = Net::HTTP::Post.new(RESEND_URL)
    request['Authorization'] = "Bearer #{@api_key}"
    request['Content-Type'] = 'application/json'
    request.body = payload.to_json

    response = Net::HTTP.start(
      RESEND_URL.hostname,
      RESEND_URL.port,
      use_ssl: true
    ) do |http|
      http.request(request)
    end

    unless response.is_a?(Net::HTTPSuccess)
      raise "Resend API error: #{response.code} #{response.body}"
    end

    response
  end
end