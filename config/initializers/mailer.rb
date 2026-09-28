require Rails.root.join('lib/resend_delivery_method')

Rails.application.configure do
  #########################################
  # Configuration Related to Action Mailer
  #########################################

  # Frontend URL used in confirmation/password reset emails
  config.action_mailer.default_url_options = {
    host: ENV['FRONTEND_URL']
  } if ENV['FRONTEND_URL'].present?

  config.action_mailer.perform_caching = false
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true

  #########################################
  # Resend / SMTP Delivery
  #########################################

  ActionMailer::Base.add_delivery_method(
    :resend,
    ResendDeliveryMethod,
    api_key: ENV['RESEND_API_KEY']
  )

  config.action_mailer.delivery_method =
    ENV.fetch('MAIL_DELIVERY_METHOD', 'smtp').to_sym unless Rails.env.test?

  #########################################
  # SMTP Configuration
  # Kept as fallback
  #########################################

  smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', 'localhost'),
    port: ENV.fetch('SMTP_PORT', 587)
  }

  smtp_settings[:authentication] =
    ENV.fetch('SMTP_AUTHENTICATION', 'login').to_sym if ENV['SMTP_AUTHENTICATION'].present?

  smtp_settings[:domain] =
    ENV['SMTP_DOMAIN'] if ENV['SMTP_DOMAIN'].present?

  smtp_settings[:user_name] =
    ENV.fetch('SMTP_USERNAME', nil)

  smtp_settings[:password] =
    ENV.fetch('SMTP_PASSWORD', nil)

  smtp_settings[:enable_starttls_auto] =
    ActiveModel::Type::Boolean.new.cast(
      ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO', true)
    )

  smtp_settings[:openssl_verify_mode] =
    ENV['SMTP_OPENSSL_VERIFY_MODE'] if ENV['SMTP_OPENSSL_VERIFY_MODE'].present?

  smtp_settings[:ssl] =
    ActiveModel::Type::Boolean.new.cast(ENV['SMTP_SSL']) if ENV['SMTP_SSL']

  smtp_settings[:tls] =
    ActiveModel::Type::Boolean.new.cast(ENV['SMTP_TLS']) if ENV['SMTP_TLS']

  smtp_settings[:open_timeout] =
    ENV['SMTP_OPEN_TIMEOUT'].to_i if ENV['SMTP_OPEN_TIMEOUT'].present?

  smtp_settings[:read_timeout] =
    ENV['SMTP_READ_TIMEOUT'].to_i if ENV['SMTP_READ_TIMEOUT'].present?

  config.action_mailer.smtp_settings = smtp_settings

  #########################################
  # Sendmail / Letter Opener
  #########################################

  config.action_mailer.delivery_method = :sendmail if ENV['SMTP_ADDRESS'].blank?

  config.action_mailer.delivery_method = :letter_opener if
    Rails.env.development? && ENV['LETTER_OPENER']

  #########################################
  # Action Mailbox
  #########################################

  config.action_mailbox.ingress =
    ENV.fetch('RAILS_INBOUND_EMAIL_SERVICE', 'relay').to_sym

  config.action_mailbox.ses.subscribed_topic =
    ENV['ACTION_MAILBOX_SES_SNS_TOPIC'] if
      ENV['ACTION_MAILBOX_SES_SNS_TOPIC'].present?
end