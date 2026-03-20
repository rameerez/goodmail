# Pay + Goodmail Testing Guide

Complete guide for testing all Pay gem email notifications with Goodmail.

## Table of Contents

- [Setup](#setup)
- [Viewing Emails in Development](#viewing-emails-in-development)
- [Testing All Email Types](#testing-all-email-types)
  - [1. Receipt Email](#1-receipt-email)
  - [2. Refund Email](#2-refund-email)
  - [3. Subscription Renewing Email](#3-subscription-renewing-email)
  - [4. Payment Action Required Email](#4-payment-action-required-email)
  - [5. Subscription Trial Will End Email](#5-subscription-trial-will-end-email)
  - [6. Subscription Trial Ended Email](#6-subscription-trial-ended-email)
  - [7. Payment Failed Email](#7-payment-failed-email)
- [Quick Test Script](#quick-test-script)
- [Tips & Tricks](#tips--tricks)

---

## Setup

### 1. Install and Configure Goodmail

```ruby
# Gemfile
gem 'goodmail'
```

```bash
bundle install
```

```ruby
# config/initializers/goodmail.rb
Goodmail.configure do |config|
  config.company_name = "Your App Name"
  config.brand_color = "#E62F17"
  config.logo_url = "https://your-cdn.com/logo.png"
  config.company_url = "https://yourapp.com"
end
```

### 2. Copy the PayGoodmailer

Copy `examples/pay_goodmailer.rb` to your app:

```bash
cp examples/pay_goodmailer.rb app/mailers/pay_goodmailer.rb
```

### 3. Configure Pay to Use the Mailer

```ruby
# config/initializers/pay.rb
Pay.setup do |config|
  config.parent_mailer = "ApplicationMailer"
  config.mailer = "PayGoodmailer"

  # Enable all email notifications
  config.send_emails = true
  config.emails.receipt = true
  config.emails.refund = true
  config.emails.subscription_renewing = true
  config.emails.payment_action_required = true
  config.emails.subscription_trial_will_end = true
  config.emails.subscription_trial_ended = true
  config.emails.payment_failed = true
end
```

### 4. Customize URL Helpers

Edit the URL helper methods at the bottom of `pay_goodmailer.rb`:

```ruby
def billing_url
  # Change this to match your app:
  billing_path # or account_billing_url, etc.
end

def dashboard_url
  dashboard_path # or root_url, etc.
end

def receipt_url(pay_charge)
  receipt_path(pay_charge) # or charge_url(pay_charge), etc.
end
```

---

## Viewing Emails in Development

### Option 1: Letter Opener (Recommended)

Opens emails in your browser automatically:

```ruby
# Gemfile
group :development do
  gem 'letter_opener'
end

# config/environments/development.rb
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.perform_deliveries = true
```

### Option 2: Mailer Previews

Visit `http://localhost:3000/rails/mailers` to see previews (requires creating preview classes).

### Option 3: Check Logs

Emails are logged in `log/development.log` when using the default `:test` delivery method.

---

## Testing All Email Types

Open your Rails console:

```bash
rails console
```

### Setup Test User and Fake Processor

```ruby
# Get or create a user
user = User.first || User.create!(
  email: 'test@example.com',
  password: 'password123'
  # ... other required fields
)

# Set up the fake processor (for testing without real payments)
user.set_payment_processor(:fake_processor, allow_fake: true)
```

---

### 1. Receipt Email

**Triggered when:** A payment is successfully processed (charge.succeeded webhook)

```ruby
# Create a test charge
charge = user.payment_processor.charge(2999)  # $29.99

# Send receipt email
Pay.mailer.with(
  pay_customer: user.payment_processor,
  pay_charge: charge
).receipt.deliver_now
```

**Expected email content:**
- ✅ Payment confirmation GIF
- ✅ Amount charged
- ✅ Payment method details
- ✅ Transaction date and ID

---

### 2. Refund Email

**Triggered when:** A charge is refunded (charge.refunded webhook)

```ruby
# Create a charge first
charge = user.payment_processor.charge(4999)  # $49.99

# Simulate a refund (full refund)
charge.update!(amount_refunded: 4999)

# Send refund email
Pay.mailer.with(
  pay_customer: user.payment_processor,
  pay_charge: charge
).refund.deliver_now
```

**For a partial refund:**

```ruby
charge.update!(amount_refunded: 2000)  # $20.00 refund on $49.99 charge
Pay.mailer.with(
  pay_customer: user.payment_processor,
  pay_charge: charge
).refund.deliver_now
```

**Expected email content:**
- ✅ Refund confirmation GIF
- ✅ Refund amount
- ✅ Original charge amount
- ✅ Processing timeline (5-10 business days)

---

### 3. Subscription Renewing Email

**Triggered when:** Annual subscription will renew soon (invoice.upcoming webhook)

```ruby
# Create a subscription
subscription = user.payment_processor.subscribe(
  name: "Pro Plan",
  trial_ends_at: nil
)

# Send renewal notice (with renewal date)
Pay.mailer.with(
  pay_customer: user.payment_processor,
  pay_subscription: subscription,
  date: 30.days.from_now
).subscription_renewing.deliver_now
```

**Expected email content:**
- ✅ Renewal reminder
- ✅ Subscription plan name
- ✅ Next billing date
- ✅ Days until renewal

---

### 4. Payment Action Required Email

**Triggered when:** Payment needs additional authentication (invoice.payment_action_required webhook)

```ruby
# Create a subscription (or use existing)
subscription = user.payment_processor.subscriptions.last ||
               user.payment_processor.subscribe(name: "Pro Plan")

# Send payment action required email
Pay.mailer.with(
  pay_subscription: subscription,
  payment_intent_id: "pi_test_123"  # Optional
).payment_action_required.deliver_now
```

**Expected email content:**
- ✅ Action needed alert
- ✅ Security verification explanation
- ✅ "Complete Payment" button
- ✅ Urgency message

---

### 5. Subscription Trial Will End Email

**Triggered when:** Trial period ending in 3 days (customer.subscription.trial_will_end webhook)

```ruby
# Create a subscription with trial
subscription = user.payment_processor.subscribe(
  name: "Pro Plan",
  trial_ends_at: 7.days.from_now
)

# Send trial ending email
Pay.mailer.with(
  pay_subscription: subscription
).subscription_trial_will_end.deliver_now
```

**Expected email content:**
- ✅ Trial ending reminder
- ✅ Days remaining
- ✅ Trial end date
- ✅ What happens after trial

---

### 6. Subscription Trial Ended Email

**Triggered when:** Trial period has ended

#### Active Subscription (payment successful):

```ruby
# Create active subscription (trial just ended)
subscription = user.payment_processor.subscribe(
  name: "Pro Plan",
  trial_ends_at: 1.day.ago,
  status: "active"
)

# Send trial ended email
Pay.mailer.with(
  pay_subscription: subscription
).subscription_trial_ended.deliver_now
```

**Expected email content:**
- ✅ Trial completion notice
- ✅ Active subscription confirmation
- ✅ Thank you message

#### Inactive Subscription (payment failed):

```ruby
# Create inactive subscription
subscription = user.payment_processor.subscribe(
  name: "Pro Plan",
  trial_ends_at: 1.day.ago
)
subscription.update!(status: "incomplete")

# Send trial ended email
Pay.mailer.with(
  pay_subscription: subscription
).subscription_trial_ended.deliver_now
```

**Expected email content:**
- ✅ Trial ended notice
- ✅ Payment failure message
- ✅ "Update Payment Method" button

---

### 7. Payment Failed Email

**Triggered when:** Subscription payment fails (invoice.payment_failed webhook)

```ruby
# Create a subscription
subscription = user.payment_processor.subscribe(name: "Pro Plan")

# Send payment failed email
Pay.mailer.with(
  pay_subscription: subscription
).payment_failed.deliver_now
```

**Expected email content:**
- ✅ "Uh-oh!" GIF
- ✅ Payment failure notice
- ✅ Common failure reasons
- ✅ "Update Payment Info" button
- ✅ Urgency message

---

## Quick Test Script

Run all email tests at once:

```ruby
# rails console

# Setup
user = User.first
user.set_payment_processor(:fake_processor, allow_fake: true)

# Test all emails
puts "Testing Receipt..."
charge = user.payment_processor.charge(2999)
Pay.mailer.with(pay_customer: user.payment_processor, pay_charge: charge).receipt.deliver_now

puts "Testing Refund..."
charge.update!(amount_refunded: 2999)
Pay.mailer.with(pay_customer: user.payment_processor, pay_charge: charge).refund.deliver_now

puts "Testing Subscription Renewing..."
subscription = user.payment_processor.subscribe(name: "Pro Plan")
Pay.mailer.with(pay_subscription: subscription, date: 30.days.from_now).subscription_renewing.deliver_now

puts "Testing Payment Action Required..."
Pay.mailer.with(pay_subscription: subscription).payment_action_required.deliver_now

puts "Testing Trial Will End..."
subscription.update!(trial_ends_at: 7.days.from_now)
Pay.mailer.with(pay_subscription: subscription).subscription_trial_will_end.deliver_now

puts "Testing Trial Ended (Active)..."
subscription.update!(trial_ends_at: 1.day.ago, status: "active")
Pay.mailer.with(pay_subscription: subscription).subscription_trial_ended.deliver_now

puts "Testing Payment Failed..."
Pay.mailer.with(pay_subscription: subscription).payment_failed.deliver_now

puts "✅ All emails sent! Check your browser (Letter Opener) or logs."
```

---

## Tips & Tricks

### Testing with Stripe CLI (Most Realistic)

For end-to-end testing with real webhook events:

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Forward webhooks to local server
stripe listen --forward-to localhost:3000/pay/webhooks/stripe

# In another terminal, trigger events
stripe trigger payment_intent.succeeded
stripe trigger charge.refunded
stripe trigger customer.subscription.updated
```

### Customizing GIF Images

Replace the GIF URLs in `pay_goodmailer.rb`:

```ruby
# Change from:
image("https://assets.rameerez.com/mailers/ok.gif", "Payment confirmed!", width: 250)

# To your own:
image("https://your-cdn.com/success.gif", "Payment confirmed!", width: 250)
```

### Adding i18n Translations

Create `config/locales/pay.en.yml`:

```yaml
en:
  pay:
    mailer:
      receipt:
        subject: "Your payment receipt from %{application_name}"
        title: "Payment Received!"
        message: "Thanks for your payment!"
      refund:
        subject: "Refund processed"
        title: "Refund Processed"
      # ... etc
```

### Testing Email Delivery

Verify emails are actually being sent:

```ruby
# Check ActionMailer deliveries
ActionMailer::Base.deliveries.count
ActionMailer::Base.deliveries.last.subject
ActionMailer::Base.deliveries.last.to

# Clear deliveries
ActionMailer::Base.deliveries.clear
```

### Debugging

If emails aren't sending:

1. Check Pay configuration: `Pay.send_emails` should be `true`
2. Check individual email settings: `Pay.emails.receipt` etc.
3. Check mailer is configured: `Pay.mailer` should return `"PayGoodmailer"`
4. Check logs for errors: `tail -f log/development.log`
5. Verify Goodmail is configured: `Goodmail.config.company_name`

### Production Testing Checklist

Before deploying to production:

- [ ] Customize all URL helper methods
- [ ] Replace GIF URLs with your own (or remove them)
- [ ] Add i18n translations (optional)
- [ ] Configure Goodmail with your branding
- [ ] Test with real Stripe test mode webhooks
- [ ] Verify emails look good in Gmail, Outlook, Apple Mail
- [ ] Check spam score (use mail-tester.com)
- [ ] Set up proper SMTP/email delivery service
- [ ] Configure SPF, DKIM, DMARC records

---

## Need Help?

- **Goodmail Issues:** https://github.com/rameerez/goodmail/issues
- **Pay Gem Issues:** https://github.com/pay-rails/pay/issues
- **Email not sending?** Check that `config.action_mailer.perform_deliveries = true` in your environment
- **Emails look wrong?** Verify Goodmail configuration in `config/initializers/goodmail.rb`

---

**Happy testing!** 🎉

If you find this guide helpful, please star the [Goodmail repository](https://github.com/rameerez/goodmail)!
