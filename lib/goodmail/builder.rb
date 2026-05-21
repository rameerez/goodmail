# frozen_string_literal: true
require "erb"
require "rails-html-sanitizer" # Require the sanitizer
require "securerandom"

module Goodmail
  # Builds the HTML content string based on DSL method calls.
  class Builder
    include ERB::Util # For the h() helper
    # The h helper, included from ERB::Util, stands for html_escape.
    # It converts special characters (&, <, >, ", ') into their HTML entity equivalents (&amp;, &lt;, &gt;, &quot;, &#39;). This prevents Cross-Site Scripting (XSS) by ensuring dynamic content is displayed as literal text rather than being interpreted as HTML.

    # Initialize a basic sanitizer allowing inline emphasis (<a>, <strong>,
    # <em>, <b>, <i>) — the formatting tags every email client renders
    # consistently and that don't add layout risk to the table-based template.
    #
    # Why these specific tags:
    #   - `a[href]`: clickable links, basic.
    #   - `strong` / `em`: semantic emphasis. Both are universally supported
    #     in email clients (including Outlook 2007+ which famously drops
    #     more exotic tags). Source: https://www.caniemail.com/features/html-strong/
    #   - `b` / `i`: legacy non-semantic equivalents that some translation
    #     workflows still emit. Allowed for symmetry — they render identically
    #     to `strong` / `em` in every modern client.
    #
    # Anything more (h1/h2 inside text, ul/li, span/div) belongs in dedicated
    # DSL helpers (`h1`, `h2`, `h3`, `code_box`, …) that compose proper
    # styled blocks with table-safe markup, not in inline text.
    HTML_SANITIZER = Rails::Html::SafeListSanitizer.new
    ALLOWED_TAGS = %w(a strong em b i).freeze
    ALLOWED_ATTRIBUTES = %w(href).freeze
    # RFC 2606 / RFC 6761 reserve `.invalid` for names that should not collide
    # with real DNS. Goodmail only needs a stable addr-spec domain for generated
    # Content-IDs; it should never imply a routable host.
    # Sources:
    #   - https://www.rfc-editor.org/rfc/rfc2606#section-2
    #   - https://www.rfc-editor.org/rfc/rfc6761#section-6.4
    INLINE_CONTENT_ID_DOMAIN = "inline.goodmail.invalid"

    attr_reader :parts, :attachments

    INTERNAL_INSTANCE_VARIABLES = %i[@parts @attachments @goodmail_context].freeze

    def initialize(context: nil)
      copy_context_instance_variables(context)
      @goodmail_context = context
      @parts = []
      # Email-level attachments collected via the `attach` DSL method. Stored as
      # `[{ filename:, content:, mime_type: }, ...]` and consumed by the
      # internal `Goodmail::Mailer` (via `Goodmail::Dispatcher`) before the
      # `mail()` call so they are forwarded on the outgoing message. We collect
      # here (rather than calling `attachments[]=` directly on a mailer
      # instance) because the DSL block is `instance_eval`'d on the Builder
      # — it has no Mailer context and can't reach into ActionMailer's
      # attachments hash. See `Mailer#compose_message` for how these are
      # applied.
      @attachments = []
    end

    # DSL Methods

    # Adds a paragraph of text. Handles newline characters for <br> tags.
    # Allows safe inline <a> tags with href attributes; strips other HTML.
    def text(str)
      # Sanitize first, allowing only safe tags like <a>
      sanitized_content = HTML_SANITIZER.sanitize(
        str.to_s, # Ensure input is a string
        tags: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES
      )
      # Then handle newlines and wrap in paragraph
      parts << tag(:p, sanitized_content.gsub(/\n/, "<br>"), style: "margin:16px 0; line-height: 1.6;")
    end

    def button(text, url)
      # Standard HTML button link
      button_html = %(<a href="#{h url}" class="goodmail-button-link" style="color:#ffffff;">#{h text}</a>)
      # VML fallback for Outlook
      vml_button = <<~VML
        <v:roundrect xmlns:v="urn:schemas-microsoft-com:vml" xmlns:w="urn:schemas-microsoft-com:office:word" href="#{h url}" style="height:44px; v-text-anchor:middle; width:200px;" arcsize="10%" stroke="f" fillcolor="#{Goodmail.config.brand_color}">
          <w:anchorlock/>
          <center style="color:#ffffff; font-family:sans-serif; font-size:14px; font-weight:bold;">
            #{h text}
          </center>
        </v:roundrect>
      VML
      # MSO conditional wrapper
      mso_wrapper = <<~MSO
        <!--[if mso]>
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="border-spacing: 0; border-collapse: collapse; mso-table-lspace:0pt; mso-table-rspace:0pt;"><tr><td style="padding: 10px 0;" align="center">
        #{vml_button.strip}
        </td></tr></table>
        <![endif]-->
        <!--[if !mso]><!-->
        #{button_html}
        <!--<![endif]-->
      MSO
      # Final container div with class for primary CSS styling
      parts << %(<div class="goodmail-button" style="text-align: center; margin: 24px 0;">#{mso_wrapper.strip.html_safe}</div>)
    end

    def image(src, alt = "", width: nil, height: nil)
      alt_text = alt.present? ? alt : Goodmail.config.company_name # Default alt text
      style = "max-width:100%; height:auto; display: block; margin: 0 auto;"
      style += " width:#{width}px;" if width
      style += " height:#{height}px;" if height
      # Standard image tag
      img_tag = %(<img class="goodmail-image" src="#{h src}" alt="#{h alt_text}" style="#{style}">)
      # MSO conditional wrapper for centering
      mso_wrapper = <<~MSO
        <!--[if mso]>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-spacing:0; border-collapse:collapse; mso-table-lspace:0pt; mso-table-rspace:0pt;"><tr><td style="padding: 20px 0;" align="center">
        <![endif]-->
        #{img_tag}
        <!--[if mso]>
        </td></tr></table>
        <![endif]-->
      MSO
      parts << mso_wrapper.strip.html_safe
    end

    # Adds a simple price row as a styled paragraph.
    # NOTE: This does not create a table structure. The visual is bold,
    # centered, and separator-bordered — designed for receipt-style line
    # items where the LABEL and the AMOUNT carry equal weight ("Premium
    # plan - $49.00", "Tax - $4.90"). For label/value rows where the
    # label is supporting context and the value is the primary content
    # ("Plan - Pro", "Status - Active"), prefer `info_row` below.
    def price_row(name, price)
      parts << %(<p style="font-family: 'Helvetica Neue',Helvetica,Arial,sans-serif; font-size: 14px; font-weight:bold; text-align:center; border-top:1px solid #eaeaea; padding:14px 0; margin: 0;">#{h name} &nbsp; &ndash; &nbsp; #{h price}</p>)
    end

    # Adds a label/value row using the two-column table pattern that
    # Stripe / Linear / Square / Resend all converge on for transactional
    # info cards: muted label on the left, dark right-aligned value on
    # the right, 1px hairline at the bottom for visual separation.
    #
    # Why a TWO-CELL TABLE (and not a flexbox/grid div):
    #   - Outlook on Windows uses Word's HTML rendering engine (no
    #     `display: flex` / `grid`, no `gap`). Tables are the only
    #     layout primitive that renders consistently across every modern
    #     and legacy client. Source: https://www.caniemail.com/features/css-display-flex/
    #   - `cellpadding=0 cellspacing=0 border=0` + `border-collapse:
    #     collapse` neutralizes the historical browser defaults and
    #     gives us pixel control via the inline `padding`.
    #   - `role="presentation"` tells screen readers to skip the table
    #     semantics — this is layout, not data. Source: WAI-ARIA 1.2
    #     `presentation` / `none` role:
    #     https://www.w3.org/TR/wai-aria-1.2/#presentation
    #
    # Why two SEPARATE tables per call (vs. one table with many rows):
    #   - The block-level DSL emits each call as a self-contained unit,
    #     same as `price_row` / `text` / `button`. Mixing rows from
    #     different DSL calls into one shared table would require a
    #     `Builder` flush phase that mutates earlier output — complex
    #     and surprising. Adjacent two-cell tables visually collapse
    #     into one continuous list when their bottom border meets the
    #     next row's top edge, so the user sees a single list anyway.
    #
    # Sources on email-safe table-row patterns:
    #   - https://www.cerberusemail.com/templates (responsive table patterns)
    #   - https://www.litmus.com/blog/the-ultimate-guide-to-css/
    #   - https://htmlemail.io/blog/responsive-html-emails-creating-a-simple-responsive-email/
    def info_row(label, value)
      label_html = h(label.to_s)
      value_html = h(value.to_s)
      # The `class="goodmail-info-row"` hook is the marker
      # `Goodmail::Plaintext` looks for to flatten this two-cell table
      # into a single `Label: Value` line in the plaintext part. HTML
      # email clients render the visible table; text-only clients see
      # the readable colon-form. Without the marker, Premailer would
      # emit the cells on two separate lines:
      #
      #     Label
      #     Value
      #
      # which is correct table-extraction behavior but a worse
      # plaintext UX than the conventional `Label: Value` shape every
      # other transactional sender uses.
      parts << <<~HTML.strip
        <table class="goodmail-info-row" role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse; width:100%; margin:0;">
          <tr>
            <td valign="top" style="padding:12px 0; border-bottom:1px solid #eaeaea; color:#6b7280; font-size:14px; line-height:1.4; font-family:'Helvetica Neue',Helvetica,Arial,sans-serif; font-weight:400; vertical-align:top;">#{label_html}</td>
            <td valign="top" align="right" style="padding:12px 0; border-bottom:1px solid #eaeaea; color:#111827; font-size:14px; line-height:1.4; font-family:'Helvetica Neue',Helvetica,Arial,sans-serif; font-weight:600; text-align:right; vertical-align:top;">#{value_html}</td>
          </tr>
        </table>
      HTML
    end

    # Adds a simple code box with background styling.
    def code_box(text)
      # Re-added background/padding; content is simple, should survive Premailer plain text.
      parts << %(<p style="background:#F8F8F8; padding:20px; font-style:italic; text-align:center; color:#404040; margin:16px 0; border-radius: 4px;"><strong>#{h text}</strong></p>)
    end

    def space(px = 16)
      # Rely on CSS height for spacing, avoid &nbsp; if possible
      parts << %(<div style="height:#{Integer(px)}px; line-height: #{Integer(px)}px; font-size: 1px;"></div>)
    end

    def sign(name = Goodmail.config.company_name)
      # Use #777 for better contrast than #888
      parts << %(<p style="margin:16px 0; line-height: 1.6;"><span style="color: #777;">– #{h name}</span></p>)
    end

    # Inline styled link as a paragraph. Wraps `button` for cases where a full
    # call-to-action button is too heavy — e.g. "View receipt", "Open the
    # account", "Read the full policy". The link is rendered in the
    # configured brand color and underlined, matching the layout's `a {}` rule
    # so the visual stays consistent in clients that strip inline styles.
    #
    # Both `text` and `url` are HTML-escaped to prevent any accidental injection
    # from interpolated user content (e.g. a customer name in a label, a
    # URL with arbitrary query strings).
    def link(text, url)
      parts << %(<p style="margin:16px 0; line-height: 1.6;"><a href="#{h url}" style="color:#{Goodmail.config.brand_color}; text-decoration:underline;">#{h text}</a></p>)
    end

    # Small/disclaimer text. Designed for legal language, fine print, "you
    # received this because…", and similar secondary content. Uses the same
    # neutral grey as the footer (`#777`) and a slightly smaller font size.
    # Newlines become <br>, mirroring `text` so callers don't have to think
    # about which helper handles which.
    def small(str)
      sanitized_content = HTML_SANITIZER.sanitize(
        str.to_s,
        tags: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES
      )
      parts << %(<p style="margin:12px 0; line-height: 1.5; font-size: 12px; color: #777;">#{sanitized_content.gsub(/\n/, "<br>")}</p>)
    end

    # Adds an email attachment (file) to the outgoing message. Use for PDFs,
    # .ics calendar invites, .csv exports, summary images you want stored on
    # the recipient's machine, etc.
    #
    # Sources:
    #   - ActionMailer attachments docs:
    #     https://guides.rubyonrails.org/action_mailer_basics.html#sending-emails-with-attachments
    #   - RFC 2392 (Content-ID URLs for inline images):
    #     https://www.rfc-editor.org/rfc/rfc2392
    #
    # Parameters:
    #   filename  — the name the recipient sees (e.g. "receipt.pdf").
    #   content   — either the raw bytes (String, IO) or a filesystem path
    #               (String). Strings that point at an existing file path are
    #               read from disk; otherwise the String is used as-is.
    #   mime_type — optional Content-Type override. When omitted, Action Mailer
    #               infers it from the filename via Mime::Type.lookup_by_extension.
    #   inline    — when true, the attachment is marked as `inline` so the
    #               email body can reference it via `cid:`. Useful for
    #               embedding logos / maps when you can't (or don't want to)
    #               host them publicly. Prefer `inline_image` below when you
    #               also want Goodmail to emit the matching <img> tag.
    def attach(filename, content, mime_type: nil, inline: false)
      filename = filename.to_s

      # Inline attachments are referenced from the email body via `cid:`.
      # Duplicate filenames are ambiguous in custom `Goodmail.render`
      # fan-out code because Action Mailer's attachment hash is keyed by
      # filename, so keep the documented "one inline filename per message"
      # contract even though Goodmail generates distinct Content-IDs.
      # Source: https://guides.rubyonrails.org/action_mailer_basics.html#sending-emails-with-attachments
      #
      # Non-inline attachments don't have the same problem — they're
      # downloaded by the recipient by filename, so a duplicate
      # produces two files with the same name (annoying UX but not a
      # rendering bug). We allow those.
      if inline && attachments.any? { |a| a[:inline] && a[:filename] == filename }
        raise Goodmail::Error, "duplicate inline filename #{filename.inspect}. Use a distinct filename per inline_image call."
      end

      descriptor = {
        filename: filename,
        content: resolve_attachment_content(content),
        mime_type: mime_type,
        inline: inline,
        content_id: (generate_inline_content_id(filename) if inline)
      }
      attachments << descriptor
      descriptor
    end

    # Embeds an inline image and emits the matching <img> tag at this point in
    # the email body, referencing the attachment via `cid:`. Goodmail assigns
    # a globally unique RFC 2392-shaped Content-ID and pins the Mail part to
    # that same ID when the message is materialized.
    # Sources:
    #   - RFC 2392 `cid:` URL / Content-ID mapping:
    #     https://www.rfc-editor.org/rfc/rfc2392
    #   - Rails inline attachment pattern:
    #     https://guides.rubyonrails.org/action_mailer_basics.html#making-inline-attachments
    #
    # `inline_image` is the right tool when:
    #   - the image must travel WITH the email so it renders in offline /
    #     end-of-cache scenarios (e.g. an Outlook user reading three months
    #     later when the public URL has expired),
    #   - or when you don't have a public URL to point at (private S3
    #     bucket, dev environment with localhost URLs, etc).
    #
    # When the asset already has a public URL you control, prefer the regular
    # `image(src, alt)` helper — it's lighter on the wire and avoids attaching
    # binary parts to every send.
    def inline_image(filename, content, alt: "", width: nil, height: nil, mime_type: nil)
      attachment = attach(filename, content, mime_type: mime_type, inline: true)
      image("cid:#{attachment[:content_id]}", alt, width: width, height: height)
    end

    # The `case` only ever sees the three keys we iterate over below, so
    # the inline lookup is exhaustive by construction — no defensive
    # `else` clause needed.
    HEADING_STYLES = {
      h1: "margin: 40px 0 10px; font-size: 32px; font-weight: 500; line-height: 1.2em;",
      h2: "margin: 40px 0 10px; font-size: 24px; font-weight: 400; line-height: 1.2em;",
      h3: "margin: 40px 0 10px; font-size: 18px; font-weight: 400; line-height: 1.2em;"
    }.freeze

    HEADING_STYLES.each do |heading_tag, style|
      define_method(heading_tag) do |str|
        # Headings still escape their content — only the surrounding tag
        # markup is trusted.
        parts << tag(heading_tag, h(str), style: style)
      end
    end

    def center(&block)
      wrap("div", "text-align:center;", &block)
    end

    def line
      # Use a class for easier styling via layout CSS
      parts << %(<hr class="goodmail-hr">)
    end

    # Allows inserting raw, *trusted* HTML. Use with extreme caution.
    def html(raw_html_string)
      parts << raw_html_string.to_s
    end

    # Returns the collected HTML parts joined together.
    def html_output
      parts.join("\n")
    end

    private

    # Loads file contents when `content` is a path to an existing file,
    # otherwise returns it unchanged so callers can pass raw bytes / IO
    # streams transparently. Paths win over byte-strings that happen to
    # match a filename: this is intentional — the README's documented
    # contract is "pass a path, we'll read it for you".
    #
    # Defensive checks before reaching `File.file?`:
    #
    #   1. NUL bytes — `File.file?` raises `ArgumentError: path name
    #      contains null byte` on any String containing `\0`, and that's
    #      exactly what binary file content (PNG / PDF / .ics) looks
    #      like. Treat NUL-containing Strings as "definitely not a
    #      path" so callers can pass `inline_image("logo.png", png_bytes)`
    #      without us blowing up trying to look up `png_bytes` as a path.
    #   2. PATH_MAX — most filesystems cap paths at 4096 bytes (Linux
    #      `PATH_MAX`); macOS HFS+ at 1024. A String longer than that is
    #      structurally not a path and almost certainly file contents.
    #      We pick 4096 as the cutoff to be the most generous to legit
    #      paths while still cheaply screening out anything bigger.
    #
    # Source on `File.file?` and the NUL byte error:
    # https://docs.ruby-lang.org/en/3.4/File.html#method-c-file-3F
    def resolve_attachment_content(content)
      return content unless content.is_a?(String)
      return content if content.include?("\0")
      return content if content.bytesize > 4096
      return content unless File.file?(content)

      File.binread(content)
    end

    # RFC 2392 maps `cid:` URLs to Content-ID headers using an addr-spec and
    # says Content-IDs should be globally unique. Use a random local part plus
    # a reserved `.invalid` domain rather than the filename itself; filenames
    # can contain spaces/non-URL characters and are often reused across emails.
    # Sources:
    #   - https://www.rfc-editor.org/rfc/rfc2392
    #   - https://www.rfc-editor.org/rfc/rfc6761#section-6.4
    def generate_inline_content_id(filename)
      safe_filename = filename.gsub(/[^A-Za-z0-9._+-]/, "-")
      safe_filename = "attachment" if safe_filename.empty?
      safe_filename = safe_filename[0, 64]

      "#{SecureRandom.hex(12)}.#{safe_filename}@#{INLINE_CONTENT_ID_DOMAIN}"
    end

    # Helper for creating simple HTML tags with optional style
    # Assumes content is already appropriately escaped or marked safe.
    def tag(name, content, style: nil)
      style_attr = style ? " style=\"#{h style}\"" : ""
      "<#{name}#{style_attr}>#{content}</#{name}>"
    end

    # Temporarily captures parts generated within a block into a wrapped tag.
    def wrap(tag_name, style, &block)
      original_parts = @parts
      @parts = []
      yield # Execute the block, collecting parts into the temporary @parts
      inner_html = @parts.join("\n")
      @parts = original_parts # Restore original parts array
      @parts << tag(tag_name, inner_html, style: style)
    ensure
      # Ensure parts are restored even if the block raises an error
      @parts = original_parts if defined?(original_parts)
    end

    # Prevent external modification of the parts array directly
    attr_writer :parts

    def copy_context_instance_variables(context)
      return unless context

      # Goodmail evaluates DSL blocks with `instance_eval` so calls like
      # `text "..."` remain terse. That changes `self` from the mailer to the
      # builder, which would normally hide mailer ivars such as `@user`.
      # Snapshot public mailer state onto the transient builder so Action
      # Mailer users can write the same instance-variable style Rails
      # documents for mailer views/actions while Goodmail still owns the DSL
      # receiver.
      # Sources:
      #   - Action Mailer actions assign instance variables for templates:
      #     https://github.com/rails/rails/blob/097017cd861e4fc57fb7b2612a409538ff2677fc/actionmailer/README.rdoc#L36-L45
      #   - Ruby `instance_eval` changes the block receiver:
      #     https://docs.ruby-lang.org/en/3.4/BasicObject.html#method-i-instance_eval
      context.instance_variables.each do |ivar|
        next if internal_instance_variable?(ivar)

        instance_variable_set(ivar, context.instance_variable_get(ivar))
      end
    end

    def internal_instance_variable?(ivar)
      INTERNAL_INSTANCE_VARIABLES.include?(ivar) || ivar.to_s.start_with?("@_")
    end

    def method_missing(method_name, *args, **kwargs, &block)
      context = @goodmail_context
      if context.respond_to?(method_name, true)
        return context.__send__(method_name, *args, **kwargs, &block)
      end

      super
    end

    def respond_to_missing?(method_name, include_private = false)
      @goodmail_context.respond_to?(method_name, true) || super
    end
  end
end
