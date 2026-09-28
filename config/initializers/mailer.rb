require Rails.root.join('lib/resend_delivery_method')

Rails.application.configure do
  #########################################
  # Configuration Related to Action Mailer
  #########################################

  # Frontend URL used in confirmation/password reset emails
  if ENV['FRONTEND_URL'].present?
    config.action_mailer.default_url_options = {
      host: ENV['FRONTEND_URL']
    }
  end

  config.action_mailer.perform_caching = false
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  #########################################
  # Resend Delivery Method Registration
  #########################################

  ActionMailer::Base.add_delivery_method(
    :resend,
    ResendDeliveryMethod,
    api_key: ENV.fetch('RESEND_API_KEY', nil)
  )

  #########################################
  # SMTP Configuration
  # Kept as fallback or primary
  #########################################

  smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', 'localhost'),
    port: ENV.fetch('SMTP_PORT', 587)
  }

  if ENV['SMTP_AUTHENTICATION'].present?
    smtp_settings[:authentication] =
      ENV.fetch('SMTP_AUTHENTICATION', 'login').to_sym
  end

  if ENV['SMTP_DOMAIN'].present?
    smtp_settings[:domain] =
      ENV['SMTP_DOMAIN']
  end

  smtp_settings[:user_name] =
    ENV.fetch('SMTP_USERNAME', nil)

  smtp_settings[:password] =
    ENV.fetch('SMTP_PASSWORD', nil)

  smtp_settings[:enable_starttls_auto] =
    ActiveModel::Type::Boolean.new.cast(
      ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO', true)
    )

  if ENV['SMTP_OPENSSL_VERIFY_MODE'].present?
    smtp_settings[:openssl_verify_mode] =
      ENV['SMTP_OPENSSL_VERIFY_MODE']
  end

  if ENV['SMTP_SSL']
    smtp_settings[:ssl] =
      ActiveModel::Type::Boolean.new.cast(ENV['SMTP_SSL'])
  end

  if ENV['SMTP_TLS']
    smtp_settings[:tls] =
      ActiveModel::Type::Boolean.new.cast(ENV['SMTP_TLS'])
  end

  if ENV['SMTP_OPEN_TIMEOUT'].present?
    smtp_settings[:open_timeout] =
      ENV['SMTP_OPEN_TIMEOUT'].to_i
  end

  if ENV['SMTP_READ_TIMEOUT'].present?
    smtp_settings[:read_timeout] =
      ENV['SMTP_READ_TIMEOUT'].to_i
  end

  config.action_mailer.smtp_settings = smtp_settings

  #########################################
  # Delivery Method Selection
  #########################################

  delivery_method = ENV.fetch('MAIL_DELIVERY_METHOD', nil)&.to_sym

  # Auto-select delivery method if not explicitly set:
  # - If RESEND_API_KEY is present and SMTP_ADDRESS is blank, prefer :resend.
  # - Otherwise default to :smtp.
  delivery_method ||= if ENV['RESEND_API_KEY'].present? && ENV['SMTP_ADDRESS'].blank?
                        :resend
                      else
                        :smtp
                      end

  delivery_method = :sendmail if delivery_method == :smtp && ENV['SMTP_ADDRESS'].blank?

  delivery_method = :letter_opener if Rails.env.development? && ENV['LETTER_OPENER']

  config.action_mailer.delivery_method = delivery_method unless Rails.env.test?

  #########################################
  # Action Mailbox
  #########################################

  config.action_mailbox.ingress =
    ENV.fetch('RAILS_INBOUND_EMAIL_SERVICE', 'relay').to_sym

  if ENV['ACTION_MAILBOX_SES_SNS_TOPIC'].present?
    config.action_mailbox.ses.subscribed_topic =
      ENV['ACTION_MAILBOX_SES_SNS_TOPIC']
  end
end
