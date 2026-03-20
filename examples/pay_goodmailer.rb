# frozen_string_literal: true

# PayGoodmailer - Production-ready Pay gem + Goodmail integration
#
# This mailer provides beautiful, i18n-ready transactional emails for all
# Pay gem notifications with a centralized approach and comprehensive features.
#
# FEATURES:
# - All 7 Pay notification types (receipt, refund, subscriptions, etc.)
# - Full i18n support with sensible English defaults
# - Centralized email rendering logic
# - Automatic List-Unsubscribe header handling
# - Receipt PDF attachment support
# - Extra billing info support
# - Customer name personalization
# - URL helper integration
#
# SETUP INSTRUCTIONS:
#
# 1. Copy this file to your Rails app:
#    app/mailers/pay_goodmailer.rb
#
# 2. Configure Pay to use this mailer in config/initializers/pay.rb:
#
#    Pay.setup do |config|
#      config.parent_mailer = "ApplicationMailer"
#      config.mailer = "PayGoodmailer"
#      # ... other Pay configuration
#    end
#
# 3. Ensure Goodmail is configured in config/initializers/goodmail.rb
#
# 4. (Optional) Add i18n translations to config/locales/pay.en.yml
#
# 5. Customize URL helpers and email content to match your app
#
# SOURCES:
# - Pay::UserMailer: https://github.com/pay-rails/pay/blob/main/app/mailers/pay/user_mailer.rb
# - Charge webhooks: https://github.com/pay-rails/pay/blob/main/lib/pay/stripe/webhooks/charge_succeeded.rb
# - Subscription webhooks: https://github.com/pay-rails/pay/tree/main/lib/pay/stripe/webhooks
# - Pay::Charge model: https://github.com/pay-rails/pay/blob/main/app/models/pay/charge.rb
# - Pay configuration: https://github.com/pay-rails/pay/blob/main/docs/2_configuration.md
#
class PayGoodmailer < Pay.parent_mailer.constantize
  include Rails.application.routes.url_helpers

  # Sends a payment receipt email
  #
  # Triggered by: charge.succeeded webhook
  # Params: params[:pay_customer], params[:pay_charge]
  def receipt
    pay_customer = params[:pay_customer]
    pay_charge = params[:pay_charge]

    # Get recipient details
    recipient_name = customer_display_name(pay_customer)
    formatted_date = localize_date(pay_charge.created_at)

    # Capture URLs before the block
    # receipt_link = receipt_url(pay_charge) # Uncomment and customize

    send_pay_goodmail(:receipt) do
      # Add a friendly GIF (customize the URL to your own!)
      image("https://assets.rameerez.com/mailers/ok.gif", "Payment confirmed!", width: 250)

      h1 t('pay.mailer.receipt.title', default: 'Payment Received!')

      text t('pay.mailer.receipt.message',
        application_name: app_name,
        default: "Thanks for your payment! We received your #{app_name} subscription payment. We appreciate your business!"
      )

      space
      h3 t('pay.mailer.receipt.details_title', default: 'Payment Details')
      price_row t('pay.mailer.receipt.amount', default: 'Amount'), pay_charge.amount_with_currency
      price_row t('pay.mailer.receipt.charged_to', default: 'Charged to'), pay_charge.charged_to
      price_row t('pay.mailer.receipt.date', default: 'Date'), formatted_date

      # Optional: Add extra billing info if your users have it
      if pay_charge.customer.owner.respond_to?(:extra_billing_info?) && pay_charge.customer.owner.extra_billing_info?
        space
        text pay_charge.customer.owner.extra_billing_info
      end

      space
      text t('pay.mailer.receipt.reference_info',
        transaction_id: pay_charge.id,
        formatted_date: formatted_date,
        default: "For your records: this payment was processed on #{formatted_date} (Transaction ID: #{pay_charge.id})."
      )

      # Optional: Add a button to view receipt
      # space
      # button t('pay.mailer.receipt.view_button', default: 'View Receipt'), receipt_link

      space
      text t('pay.mailer.receipt.questions', default: 'Questions? Just reply to this email — we\'re here to help!')

      sign
    end
  end

  # Sends a refund notification email
  #
  # Triggered by: charge.refunded webhook
  # Params: params[:pay_customer], params[:pay_charge]
  def refund
    pay_customer = params[:pay_customer]
    pay_charge = params[:pay_charge]

    recipient_name = customer_display_name(pay_customer)
    formatted_date = localize_date(pay_charge.created_at)

    send_pay_goodmail(:refund) do
      # Add a friendly GIF (customize the URL to your own!)
      image("https://assets.rameerez.com/mailers/ok.gif", "Refund confirmed!", width: 250)

      h1 t('pay.mailer.refund.title', default: 'Refund Processed')

      text t('pay.mailer.refund.message',
        application_name: app_name,
        default: "We've processed your refund. The money should be back in your account soon!"
      )

      space
      h3 t('pay.mailer.refund.details_title', default: 'Refund Details')
      price_row t('pay.mailer.refund.amount', default: 'Refund Amount'), pay_charge.amount_refunded_with_currency
      price_row t('pay.mailer.refund.original_charge', default: 'Original Charge'), pay_charge.amount_with_currency
      price_row t('pay.mailer.refund.date', default: 'Date'), formatted_date

      space
      text t('pay.mailer.refund.reference_info',
        transaction_id: pay_charge.id,
        default: "Transaction ID: #{pay_charge.id}"
      )

      space
      text t('pay.mailer.refund.processing_time',
        default: 'The refund will show up on your statement within 5-10 business days, depending on your bank.'
      )
      text t('pay.mailer.refund.questions', default: 'Questions? Just reply to this email!')

      sign
    end
  end

  # Sends a subscription renewal reminder
  # (Used for annual subscriptions that will renew soon)
  #
  # Triggered by: invoice.upcoming webhook (for annual subscriptions)
  # Params: params[:pay_customer], params[:pay_subscription], params[:date]
  def subscription_renewing
    pay_subscription = params[:pay_subscription]
    pay_customer = params[:pay_customer] || pay_subscription.customer
    renewal_date = params[:date]

    recipient_name = customer_display_name(pay_customer)
    formatted_renewal_date = renewal_date ? localize_date(renewal_date) : nil
    days_until_renewal = renewal_date ? (renewal_date.to_date - Date.current).to_i : nil

    # Capture URLs before the block
    billing_link = billing_url

    send_pay_goodmail(:subscription_renewing) do
      h1 t('pay.mailer.subscription_renewing.title', default: 'Your Subscription Renews Soon')

      text t('pay.mailer.subscription_renewing.message',
        application_name: app_name,
        days: days_until_renewal,
        default: "Just a heads up — your #{app_name} subscription will renew in #{days_until_renewal} days."
      )

      space
      h3 t('pay.mailer.subscription_renewing.details_title', default: 'Subscription Details')
      price_row t('pay.mailer.subscription_renewing.plan', default: 'Plan'), pay_subscription.name
      price_row t('pay.mailer.subscription_renewing.status', default: 'Status'), pay_subscription.status.humanize

      if formatted_renewal_date
        price_row t('pay.mailer.subscription_renewing.next_billing', default: 'Next Billing Date'), formatted_renewal_date
      end

      space
      text t('pay.mailer.subscription_renewing.auto_renewal',
        default: 'No action needed — everything will renew automatically. We\'ll charge your payment method on file.'
      )

      # Optional: Add manage subscription button
      # space
      # button t('pay.mailer.subscription_renewing.manage_button', default: 'Manage Subscription'), billing_link

      space
      text t('pay.mailer.subscription_renewing.questions', default: 'Questions? Just reply to this email!')

      sign
    end
  end

  # Sends a notification when payment action is required
  # (e.g., 3D Secure authentication, expired card)
  #
  # Triggered by: invoice.payment_action_required webhook
  # Params: params[:pay_customer], params[:pay_subscription], params[:payment_intent_id]
  def payment_action_required
    pay_subscription = params[:pay_subscription]
    pay_customer = params[:pay_customer] || pay_subscription.customer
    payment_intent_id = params[:payment_intent_id]

    recipient_name = customer_display_name(pay_customer)

    # Capture URLs before the block
    billing_link = billing_url

    send_pay_goodmail(:payment_action_required) do
      h1 t('pay.mailer.payment_action_required.title', default: 'Quick Action Needed')

      text t('pay.mailer.payment_action_required.message',
        subscription_name: pay_subscription.name,
        default: "We need your help! Your payment for #{pay_subscription.name} needs additional verification."
      )

      space
      text t('pay.mailer.payment_action_required.description',
        default: 'This is a security thing (it happens!) — just verify your payment to keep everything running smoothly.'
      )

      space
      button t('pay.mailer.payment_action_required.action_button', default: 'Complete Payment'), billing_link

      space
      text t('pay.mailer.payment_action_required.urgency',
        default: 'Try to do this within the next few days so your service doesn\'t get interrupted.'
      )
      text t('pay.mailer.payment_action_required.questions', default: 'Need help? Just reply to this email!')

      sign
    end
  end

  # Sends a reminder that the trial period is ending soon
  #
  # Triggered by: customer.subscription.trial_will_end webhook (3 days before trial ends)
  # Params: params[:pay_customer], params[:pay_subscription]
  def subscription_trial_will_end
    pay_subscription = params[:pay_subscription]
    pay_customer = params[:pay_customer] || pay_subscription.customer

    recipient_name = customer_display_name(pay_customer)
    formatted_trial_end = pay_subscription.trial_ends_at ? localize_date(pay_subscription.trial_ends_at) : nil
    days_remaining = pay_subscription.trial_ends_at ? (pay_subscription.trial_ends_at.to_date - Date.current).to_i : nil

    # Capture URLs before the block
    billing_link = billing_url

    send_pay_goodmail(:subscription_trial_will_end) do
      h1 t('pay.mailer.subscription_trial_will_end.title', default: 'Your Trial Ends Soon')

      text t('pay.mailer.subscription_trial_will_end.message',
        application_name: app_name,
        days: days_remaining,
        default: "Quick reminder — your #{app_name} trial wraps up in #{days_remaining} days."
      )

      space
      h3 t('pay.mailer.subscription_trial_will_end.details_title', default: 'Trial Details')
      price_row t('pay.mailer.subscription_trial_will_end.plan', default: 'Plan'), pay_subscription.name

      if formatted_trial_end
        price_row t('pay.mailer.subscription_trial_will_end.trial_ends', default: 'Trial Ends'), formatted_trial_end
      end

      space
      text t('pay.mailer.subscription_trial_will_end.continue_message',
        default: 'After your trial, your subscription will continue automatically. Just make sure your payment info is current!'
      )

      # Optional: Add manage subscription button
      # space
      # button t('pay.mailer.subscription_trial_will_end.manage_button', default: 'Manage My Subscription'), billing_link

      space
      text t('pay.mailer.subscription_trial_will_end.questions', default: 'Questions? Just reply!')

      sign
    end
  end

  # Sends a notification that the trial period has ended
  #
  # Triggered by: When trial_ends_at passes (triggered by trial_will_end webhook if trial already ended)
  # Params: params[:pay_customer], params[:pay_subscription]
  def subscription_trial_ended
    pay_subscription = params[:pay_subscription]
    pay_customer = params[:pay_customer] || pay_subscription.customer

    recipient_name = customer_display_name(pay_customer)

    # Capture URLs before the block
    billing_link = billing_url
    # dashboard_link = dashboard_url

    send_pay_goodmail(:subscription_trial_ended) do
      h1 t('pay.mailer.subscription_trial_ended.title', default: 'Your Trial Just Ended')

      text t('pay.mailer.subscription_trial_ended.message',
        application_name: app_name,
        default: "Your #{app_name} trial period is now complete."
      )

      space
      h3 t('pay.mailer.subscription_trial_ended.details_title', default: 'Subscription Details')
      price_row t('pay.mailer.subscription_trial_ended.plan', default: 'Plan'), pay_subscription.name
      price_row t('pay.mailer.subscription_trial_ended.status', default: 'Status'), pay_subscription.status.humanize

      space

      if pay_subscription.active?
        text t('pay.mailer.subscription_trial_ended.continue_message',
          default: 'Thanks for sticking with us! Your subscription is now active and billing normally.'
        )

        # Optional: Add dashboard button
        # space
        # button t('pay.mailer.subscription_trial_ended.dashboard_button', default: 'Go to My Dashboard'), dashboard_link
      else
        text t('pay.mailer.subscription_trial_ended.inactive_message',
          default: 'Looks like we couldn\'t activate your subscription. Update your payment method to keep going!'
        )

        space
        button t('pay.mailer.subscription_trial_ended.update_button', default: 'Update Payment Info'), billing_link
      end

      space
      text t('pay.mailer.subscription_trial_ended.questions', default: 'Need help? Just reply to this email!')

      sign
    end
  end

  # Sends a notification when a payment has failed
  #
  # Triggered by: invoice.payment_failed webhook
  # Params: params[:pay_customer], params[:pay_subscription]
  def payment_failed
    pay_subscription = params[:pay_subscription]
    pay_customer = params[:pay_customer] || pay_subscription.customer

    recipient_name = customer_display_name(pay_customer)

    # Capture URLs before the block
    billing_link = billing_url

    send_pay_goodmail(:payment_failed) do
      # Add a friendly "uh-oh" GIF (customize the URL to your own!)
      image("https://assets.rameerez.com/mailers/uh-oh.gif", "Uh-oh!", width: 150)

      h1 t('pay.mailer.payment_failed.title', default: 'Uh-oh! Payment Issue')

      text t('pay.mailer.payment_failed.message',
        application_name: app_name,
        subscription_name: pay_subscription.name,
        default: "We tried to charge your payment method for #{pay_subscription.name}, but it didn't go through."
      )

      space
      h3 t('pay.mailer.payment_failed.details_title', default: 'Subscription Details')
      price_row t('pay.mailer.payment_failed.subscription', default: 'Subscription'), pay_subscription.name

      space
      text t('pay.mailer.payment_failed.reasons_title', default: 'This usually happens because:')
      text t('pay.mailer.payment_failed.reasons',
        default: "• Not enough funds in the account\n• Expired card\n• Your bank declined it\n• Wrong billing address"
      )

      space
      text t('pay.mailer.payment_failed.action_message',
        default: 'No worries — just update your payment info and you\'re good to go!'
      )

      space
      button t('pay.mailer.payment_failed.update_button', default: 'Update Payment Info'), billing_link

      space
      text t('pay.mailer.payment_failed.urgency',
        default: 'Please update it in the next few days so we don\'t have to pause your subscription.'
      )
      text t('pay.mailer.payment_failed.questions', default: 'Need help? Just reply to this email!')

      sign
    end
  end

  private

  # Centralized method to send Pay emails with Goodmail
  # This method:
  # - Gets mail arguments from Pay's configuration
  # - Sets up i18n subject and preheader
  # - Renders email content using Goodmail
  # - Adds List-Unsubscribe header if configured
  # - Attaches receipts for receipt emails
  # - Sends the email via ActionMailer
  def send_pay_goodmail(action_sym, &dsl_block)
    # Ensure pay_customer is set in params (get from subscription if needed)
    # This is necessary because Pay.mail_arguments expects params[:pay_customer] to exist
    if params[:pay_customer].nil? && params[:pay_subscription].present?
      params[:pay_customer] = params[:pay_subscription].customer
    end

    # Get the mail arguments from Pay's configuration (same as Pay::UserMailer does)
    pay_mail_arguments = instance_exec(&Pay.mail_arguments)

    # Construct subject with i18n support
    custom_subject = t(
      "pay.mailer.#{action_sym}.subject",
      application_name: app_name,
      default: pay_mail_arguments[:subject] || default_subject_for(action_sym)
    )

    # Update subject in mail arguments
    pay_mail_arguments[:subject] = custom_subject

    # Prepare Goodmail render options
    goodmail_options = {
      subject: custom_subject,
      preheader: t(
        "pay.mailer.#{action_sym}.preheader",
        application_name: app_name,
        default: custom_subject
      )
    }

    # Add unsubscribe URL if configured
    if Goodmail.config.unsubscribe_url.present?
      goodmail_options[:unsubscribe_url] = Goodmail.config.unsubscribe_url
    end

    # Render email using Goodmail
    parts = Goodmail.render(goodmail_options, &dsl_block)

    # Add List-Unsubscribe header if unsubscribe URL is present
    if goodmail_options[:unsubscribe_url].present?
      pay_mail_arguments["List-Unsubscribe"] = "<#{goodmail_options[:unsubscribe_url]}>"
    end

    # Attach receipt PDF if this is a receipt email and one exists
    if action_sym == :receipt && params[:pay_charge]&.respond_to?(:receipt)
      attachments[params[:pay_charge].filename] = params[:pay_charge].receipt
    end

    # Send the email
    mail(pay_mail_arguments) do |format|
      format.text { render plain: parts.text }
      format.html { render html: parts.html.html_safe }
    end
  end

  # Get customer display name with fallback to email
  def customer_display_name(pay_customer)
    if pay_customer.respond_to?(:customer_name) && pay_customer.customer_name.present?
      pay_customer.customer_name
    else
      pay_customer.owner.email
    end
  end

  # Localize date using i18n
  def localize_date(date)
    I18n.l(date, format: :long)
  rescue
    date.strftime("%B %d, %Y at %I:%M %p")
  end

  # Get application name from Goodmail config
  def app_name
    Goodmail.config.company_name
  end

  # i18n helper (delegate to I18n.t)
  def t(key, **options)
    I18n.t(key, **options)
  end

  # Default subjects for each email type
  def default_subject_for(action_sym)
    {
      receipt: "Receipt for your payment",
      refund: "Refund processed",
      subscription_renewing: "Your subscription will renew soon",
      payment_action_required: "Action required for your payment",
      subscription_trial_will_end: "Your trial is ending soon",
      subscription_trial_ended: "Your trial has ended",
      payment_failed: "Payment failed"
    }[action_sym] || "Notification from #{app_name}"
  end

  # ============================================================================
  # URL HELPERS - CUSTOMIZE THESE TO MATCH YOUR APP
  # ============================================================================

  # Generates URL for billing/payment method management
  # CUSTOMIZE THIS to match your app's routing
  def billing_url
    # Example implementations:
    # - billing_url (if you have a billing route)
    # - account_billing_url
    # - edit_user_registration_url(anchor: 'billing')
    # - "https://yourdomain.com/billing"

    # Default placeholder:
    root_url
  end

  # Generates URL for dashboard
  # CUSTOMIZE THIS to match your app's routing
  def dashboard_url
    # Example implementations:
    # - dashboard_url
    # - root_url
    # - "https://yourdomain.com/dashboard"

    # Default placeholder:
    root_url
  end

  # Generates URL for viewing a receipt
  # CUSTOMIZE THIS to match your app's routing
  def receipt_url(pay_charge)
    # Example implementations:
    # - receipt_url(pay_charge)
    # - charge_url(pay_charge)
    # - "https://yourdomain.com/receipts/#{pay_charge.id}"

    # Default placeholder:
    root_url
  end
end
