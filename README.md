# Goodmail
[![Gem Version](https://badge.fury.io/rb/pay.svg)](https://badge.fury.io/rb/pay)

Send beautiful, simple transactional emails with zero HTML hell.

Goodmail is an opinionated, minimal, expressive Ruby DSL for sending beautiful, production-grade transactional emails in Rails apps — no templates, no partials, no HTML hell.

There's only one template. You can't change it. It turns your ugly, default, text-only emails into SaaS-ready emails.

Drop it in, call `Goodmail.compose`, and ship decent emails that look great everywhere.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "goodmail"
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install goodmail
```

## Configuration

Goodmail comes with sensible defaults, but you can customize its appearance and behavior.

Create an initializer file at `config/initializers/goodmail.rb`:

```ruby
# config/initializers/goodmail.rb

Goodmail.configure do |config|
  # The main accent color used for buttons and links in the email.
  # Default: "#348eda"
  config.brand_color = "#E62F17" # Your brand's primary color

  # The company name displayed in the email footer and used by the default `sign` helper.
  # Default: "Example Inc."
  config.company_name = "MyApp Inc."

  # Optional: URL to your company logo. If set, it will appear centered in the header.
  # Recommended size: max-height 30px.
  # Default: nil
  config.logo_url = "https://cdn.myapp.com/images/email_logo.png"

  # Optional: Fallback base URL for generated unsubscribe links if Rails URL helpers
  # are unavailable or not configured correctly. Usually handled by Action Mailer's
  # default_url_options.
  # Default: "http://localhost:3000"
  # config.base_url = "https://myapp.com"
end
```

Make sure to restart your Rails server after creating or modifying the initializer.

## Usage

The primary way to use Goodmail is via the `Goodmail.compose` method. It builds and returns a `Mail::Message` object, which you can then deliver using standard Action Mailer methods.

### Basic Example (Deliver Now)

```ruby
# In a controller action, background job, or service object

recipient = User.find(params[:user_id])

mail = Goodmail.compose(
  to: recipient.email,
  from: ""MyApp Support" <support@myapp.com>",
  subject: "Welcome to MyApp!"
) do
  h1 "Welcome aboard, #{recipient.name}!"
  text "We're thrilled to have you join the MyApp community."
  text "Here are a few things to get you started:"
  # You can use simple lists within text blocks:
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
*   `text(string)`: A paragraph of text. Handles `\n` for line breaks within the paragraph.
*   `button(link_text, url)`: A prominent, styled call-to-action button.
*   `image(src, alt = "", width: nil, height: nil)`: Embeds an image, centered by default.
*   `space(pixels = 16)`: Adds vertical whitespace.
*   `line`: Adds a horizontal rule (`<hr>`).
*   `center { ... }`: Centers the content generated within the block.
*   `sign(name = Goodmail.config.company_name)`: Adds a standard closing signature line.
*   `html(raw_html_string)`: **Use with caution.** Allows embedding raw HTML. Useful for complex cases or escaping the DSL, but bypasses standard formatting.

### Unsubscribe Link

To automatically add a `List-Unsubscribe` header when building the email:

1.  **Set `unsubscribe: true` in the headers:**

    ```ruby
    mail = Goodmail.compose(
      to: recipient.email,
      # ... other headers ...
      unsubscribe: true
    ) do
      # ... email content ...
    end
    ```

2.  **Ensure Rails URL helpers work OR configure `base_url`:**
    *   **Recommended:** Define an unsubscribe route in your `config/routes.rb` named `unsubscribe_email` that accepts the recipient's email (properly constrained), and ensure `config.action_mailer.default_url_options` is set in your environment files.
    ```ruby
    # config/routes.rb
    get 'emails/unsubscribe/:email', to: 'email_unsubscribes#destroy', as: :unsubscribe_email, constraints: { email: /.+@.+\..+/ }
    ```
    *   **Fallback:** If URL helpers aren't set up, Goodmail uses `Goodmail.config.base_url` combined with `/emails/unsubscribe/:email` (recipient email will be URL-escaped).

3.  **Provide a specific URL:** You can also pass a full URL string directly:

    ```ruby
    mail = Goodmail.compose(
      # ... headers ...
      unsubscribe: generate_custom_unsubscribe_url(recipient)
    ) do
      # ...
    end
    ```

## Testing

Run the test suite with `bundle exec rake spec` (assuming RSpec is used).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/goodmail. Our code of conduct is: just be nice and make your mom proud of what you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).