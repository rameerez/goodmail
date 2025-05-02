# Goodmail
[![Gem Version](https://badge.fury.io/rb/pay.svg)](https://badge.fury.io/rb/pay)

Send beautiful, simple transactional emails with zero HTML hell.

Goodmail turns your ugly, default, text-only emails into SaaS-ready emails. It's an opinionated, minimal, expressive Ruby DSL for sending beautiful, production-grade transactional emails in Rails apps — no templates, no partials, no HTML hell. The template works well and looks nice across email clients.

Here's the catch: there's only one template. You can't change it. You're guaranteed you'll send good emails, but the cost is you don't have much flexibility. If you're okay with this, welcome to `goodmail`! You'll be shipping decent emails that look great everywhere in no time.

(And you can still use Action Mailer for all other template-intensive emails – Goodmail doesn't replace Action Mailer, just builds on top of it!)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "goodmail"
```

And then execute:

```bash
bundle install
```

## Configuration

You can (and should!) edit the default strings in the Goodmail initializer.

Create an initializer file at `config/initializers/goodmail.rb`:

```ruby
# config/initializers/goodmail.rb

Goodmail.configure do |config|
  # The main accent color used for buttons and links in the email body.
  # Default: "#348eda"
  config.brand_color = "#E62F17" # Your brand's primary color

  # The company name displayed in the email footer and used by the default `sign` helper.
  # Default: "Example Inc."
  config.company_name = "MyApp Inc."

  # Optional: URL to your company logo. If set, it will appear centered in the header.
  # Recommended size: max-height 30px.
  # Default: nil
  config.logo_url = "https://cdn.myapp.com/images/email_logo.png"

  # Optional: Custom text displayed in the footer below the copyright.
  # Use this to explain why the user received the email.
  # Default: nil
  config.footer_text = "You are receiving this email because you signed up for an account at MyApp."

  # Optional: Global default URL for unsubscribe links (both the List-Unsubscribe
  # header and the optional visible link in the footer).
  # Goodmail *does not* handle the unsubscribe logic; you must provide a valid URL.
  # Can be overridden per email via headers[:unsubscribe_url].
  # Default: nil
  config.unsubscribe_url = "https://myapp.com/emails/unsubscribe"

  # Optional: Whether to show a visible unsubscribe link in the footer.
  # Requires an unsubscribe URL to be set (globally or per-email).
  # Default: false
  config.show_footer_unsubscribe_link = true

  # Optional: The text for the visible footer unsubscribe link.
  # Default: "Unsubscribe"
  config.footer_unsubscribe_link_text = "Click here to unsubscribe"
end
```

Make sure to restart your Rails server after creating or modifying the initializer.

## Quick start

Use the `Goodmail.compose` method to compose emails using the DSL, then call `.deliver_now` or `.deliver_later` on it (your usual standard Action Mailer methods)

### Basic Example (Deliver Now)

```ruby
# In a controller action, background job, or service object

recipient = User.find(params[:user_id])

mail = Goodmail.compose(
  to: recipient.email,
  from: ""MyApp Support" <support@myapp.com>",
  subject: "Welcome to MyApp!"
  # No unsubscribe header or link for this email
) do
  h1 "Welcome aboard, #{recipient.name}!"
  text "We're thrilled to have you join the MyApp community."
  # You can include safe inline links directly in text blocks:
  text "Here are a few things to get you started: Check the <a href=\"/help\">Help Center</a>."
  text "- Complete your profile\n- Explore the dashboard\n- Invite your team"
  button "Go to Dashboard", user_dashboard_url(recipient) # Use Rails URL helpers
  space # Adds default vertical space
  text "Need help? Just reply to this email."
  sign # Adds "– #{Goodmail.config.company_name}"
end

mail.deliver_now
```

### Deliver Later (Background Job)

```ruby
mail = Goodmail.compose(
  to: @user.email,
  from: ..., # etc.
  subject: "Your password has been reset"
) do
  # ... DSL content ...
end

mail.deliver_later
```

*(Requires Active Job configured.)*

### Available DSL Methods

Inside the `Goodmail.compose` block, you have access to these methods:

*   `h1(text)`, `h2(text)`, `h3(text)`: Styled heading tags.
*   `text(string)`: A paragraph of text. Handles `\n` for line breaks. Allows simple inline `<a>` tags with `href` attributes; other HTML is stripped for safety.
*   `button(link_text, url)`: A prominent, styled call-to-action button.
*   `image(src, alt = "", width: nil, height: nil)`: Embeds an image, centered by default.
*   `space(pixels = 16)`: Adds vertical whitespace.
*   `line`: Adds a horizontal rule (`<hr>`).
*   `center { ... }`: Centers the content generated within the block.
*   `sign(name = Goodmail.config.company_name)`: Adds a standard closing signature line.
*   `html(raw_html_string)`: **Use with extreme caution.** Allows embedding raw, *un-sanitized* HTML. Only use this if you absolutely trust the source of the string.

### Adding Unsubscribe Functionality

Goodmail helps you add the `List-Unsubscribe` header and an optional visible link, but **you must provide the actual URL** where users can unsubscribe. Goodmail does not generate unsubscribe URLs or handle the logic.

1.  **Provide the URL:** You have two options:
    *   **Globally:** Set `config.unsubscribe_url = "your_global_url"` in the initializer (`config/initializers/goodmail.rb`).
    *   **Per-Email:** Pass `unsubscribe_url: "your_specific_url"` in the headers hash when calling `Goodmail.compose`. This overrides the global setting for that email.

    ```ruby
    # Example using per-email override
    mail = Goodmail.compose(
      to: recipient.email,
      # ... other headers ...
      unsubscribe_url: manage_subscription_url(recipient) # Your app's URL helper
    ) do
      # ... email content ...
    end
    ```
    *If an `unsubscribe_url` is provided (either globally or per-email), Goodmail will automatically add the standard `List-Unsubscribe` header.*

2.  **Optionally Show Footer Link:**
    *   To show a visible link in the email footer, set `config.show_footer_unsubscribe_link = true` in the initializer.
    *   You can customize the link text with `config.footer_unsubscribe_link_text` (default: "Unsubscribe").
    *   *Note: The footer link only appears if an `unsubscribe_url` was provided (step 1) AND `config.show_footer_unsubscribe_link` is true.* 

    ```ruby
    # config/initializers/goodmail.rb
    Goodmail.configure do |config|
      # ... other settings
      config.unsubscribe_url = "https://myapp.com/preferences"
      config.show_footer_unsubscribe_link = true
      config.footer_unsubscribe_link_text = "Manage email preferences"
    end
    ```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/goodmail. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).