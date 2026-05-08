# frozen_string_literal: true
require "premailer"
require "nokogiri"

module Goodmail
  # Plain-text generator for the `text/plain` part of every Goodmail
  # multipart message. Single source of truth shared by
  # `Goodmail::Email.render` and `Goodmail::Mailer#compose_message` —
  # before this consolidation, both code paths had a copy of the
  # same gsub cleanup pipeline and the same Premailer call, which
  # made it easy for plaintext quality to drift between them.
  #
  # Why we DO NOT just hand the raw HTML to Premailer:
  # ────────────────────────────────────────────────────────────────
  # The Goodmail layout is built for HTML email clients that
  # respect display:none, conditional comments, and inline alt
  # attributes — none of which Premailer's `to_plain_text` honors.
  # If we feed it the layout HTML directly, the plaintext part has
  # three artifacts that look like rendering bugs to a recipient
  # using a text-only client:
  #
  #   1. Preheader leak — the layout's hidden inbox-preview
  #      `<span style="display:none">` is rendered as a phantom
  #      first line of the message body.
  #   2. Button text duplication — the `button` DSL helper emits
  #      both a `<v:roundrect>` (Outlook VML, wrapped in
  #      `<!--[if mso]>...<![endif]-->`) AND a regular `<a>`.
  #      Premailer ignores the conditional comment and extracts
  #      text from BOTH, so the button label appears twice in
  #      plaintext.
  #   3. Image alt-text leak — `image` / `inline_image` calls
  #      with no explicit alt fall back to `config.company_name`.
  #      That alt is fine in HTML (screen readers read it) but
  #      shows up as a stray "CompanyName" line in plaintext
  #      since Premailer extracts alt attributes verbatim.
  #
  # We pre-process the HTML to neutralize each of these BEFORE
  # plaintext extraction, then apply a small post-extraction
  # cleanup pass for the residual artifacts (logo alt line,
  # standalone URL lines from logo links, blank-line compaction).
  #
  # Sources:
  #   - Premailer to_plain_text:
  #     https://github.com/premailer/premailer/blob/master/lib/premailer/premailer.rb
  #   - MSO conditional comments syntax:
  #     https://www.litmus.com/blog/a-guide-to-rendering-differences-in-microsoft-outlook-clients
  module Plaintext
    extend self

    # Matches the `<!--[if mso]>...<![endif]-->` blocks Outlook reads
    # exclusively. The `m` flag lets `.*?` span newlines (these blocks
    # are usually multi-line). The non-greedy quantifier ensures we
    # don't eat past the first matching `<![endif]-->`.
    MSO_CONDITIONAL_BLOCK = /<!--\[if mso\]>.*?<!\[endif\]-->/m

    # Generates the plaintext part for a multipart message.
    #
    # @param raw_html [String] The full layout-rendered HTML body.
    # @param preheader [String, nil] The preheader text (the value
    #   we wrote into the hidden inbox-preview span). Passed in so
    #   we can strip it specifically from plaintext rather than
    #   guessing at a generic heuristic.
    # @return [String] The cleaned plaintext, ready for the text/plain
    #   part of the outgoing message.
    def generate(raw_html, preheader: nil)
      premailer_html = strip_mso_only_markup(raw_html)
      premailer = Premailer.new(
        premailer_html,
        with_html_string: true,
        adapter: :nokogiri,
        preserve_styles: false,
        remove_ids: true,
        remove_comments: false,
        # Goodmail outputs UTF-8 end-to-end. Without this, Premailer's
        # libxml2 backend defaults to Latin-1 when no `<meta charset>`
        # tag is present in the source, double-encoding every accented
        # character ("Duración" → "DuraciÃ³n", "€" → "â¬"). The shipped
        # layout DOES include the meta tag, but custom `layout_path:`
        # callers might not — pinning here makes us robust to either.
        input_encoding: "UTF-8"
      )
      text = premailer.to_plain_text

      text = strip_preheader_line(text, preheader)
      text = strip_logo_alt_line(text)
      text = strip_company_name_alt_line(text)
      text = strip_standalone_url_lines(text)
      text = compact_blank_lines(text)
      text.strip
    end

    private

    # Removes everything Outlook-only from the source HTML before it's
    # handed to Premailer's plaintext extractor:
    #
    #   - The `<!--[if mso]>...<![endif]-->` blocks themselves (Premailer
    #     doesn't honor conditional comments and would otherwise extract
    #     text from the VML button INSIDE the block — duplicating every
    #     button label in plaintext).
    #   - The hidden preheader span (display:none in HTML, but Premailer
    #     ignores CSS visibility and would otherwise emit the preheader
    #     as a phantom first line).
    def strip_mso_only_markup(html)
      cleaned = html.gsub(MSO_CONDITIONAL_BLOCK, "")
      cleaned = strip_hidden_preheader(cleaned)
      flatten_info_rows(cleaned)
    end

    # Replaces every `<table class="goodmail-info-row">` (the markup
    # `Builder#info_row` emits) with a single-line `Label: Value`
    # paragraph. Two-cell tables otherwise extract as two separate
    # lines (Premailer renders each `<td>` on its own line) — the
    # colon-form is the conventional plaintext shape every modern
    # transactional sender uses for label/value pairs.
    #
    # Why we Nokogiri-parse rather than regex-match: tables can be
    # nested inside other layout chrome (the layout's `.main` table,
    # the content-wrap cell, the data-row table itself). Trying to
    # match nested tables with a regex is the canonical case study
    # for "don't parse HTML with regex".
    #
    # We parse as a FULL DOCUMENT, not a fragment. `Nokogiri::HTML.fragment`
    # would strip the `<head>` wrapper and expose the `<title>` text as
    # body content — Premailer's plaintext extractor would then leak the
    # subject as a phantom first line.
    #
    # We pin the encoding to UTF-8 explicitly. Without that, Nokogiri's
    # libxml2 backend falls back to Latin-1 when no `<meta charset>` tag
    # is present, which mangles every accented character in the layout
    # ("Duración" → "DuraciÃ³n", "€" → "â¬"). The shipped layout
    # DOES declare `<meta http-equiv="Content-Type" content=".../UTF-8">`,
    # but downstream apps may use a custom `layout_path:` that doesn't,
    # and the API contract is "Goodmail outputs UTF-8 end-to-end" — so
    # we don't depend on the meta tag for correctness.
    # Source: https://nokogiri.org/rdoc/Nokogiri/HTML4.html#method-c-parse
    def flatten_info_rows(html)
      doc = Nokogiri::HTML.parse(html, nil, "UTF-8")
      doc.css("table.goodmail-info-row").each do |table|
        cells = table.css("td")
        next if cells.length < 2

        label = cells[0].text.strip
        value = cells[1].text.strip
        replacement = Nokogiri::XML::Node.new("p", doc)
        replacement.content = "#{label}: #{value}"
        table.replace(replacement)
      end
      doc.to_html
    rescue StandardError => error
      # If Nokogiri ever chokes (truncated HTML, malformed input from a
      # custom layout), preserve the original behavior — the table
      # cells still get emitted as two lines, which is ugly but not
      # broken. We only log so the failure is visible without crashing
      # the whole email pipeline.
      warn "[Goodmail::Plaintext] info-row flatten failed: #{error.class}: #{error.message}"
      html
    end

    # The layout emits the preheader inside a `<span>` with a strong
    # signature: `display:none !important; font-size:1px; color:#ffffff;
    # line-height:1px; ...`. We use a regex anchored on `display:none`
    # AND `font-size:1px` to avoid stripping any legit hidden span a
    # downstream caller might emit via the raw `html` DSL helper.
    #
    # The non-greedy `.*?` between the opening tag and `</span>`, plus
    # the `m` flag, lets the match span the whitespace and the
    # interpolated preheader text inside the tag.
    HIDDEN_PREHEADER_SPAN = /
      <span\s[^>]*
        style="[^"]*
          display:\s*none[^"]*
          font-size:\s*1px[^"]*
        "[^>]*>
        .*?
      <\/span>
    /xm

    def strip_hidden_preheader(html)
      html.gsub(HIDDEN_PREHEADER_SPAN, "")
    end

    # Belt-and-suspenders for the preheader: if the caller passed an
    # explicit preheader and it happens to land at the top of the
    # plaintext anyway (e.g. a custom layout that doesn't use the
    # hidden-span pattern, or a preheader that ALSO appears as visible
    # body content), strip the leading occurrence so the plaintext
    # doesn't open with a duplicate.
    def strip_preheader_line(text, preheader)
      return text if preheader.to_s.strip.empty?

      escaped = Regexp.escape(preheader.to_s.strip)
      text.sub(/\A\s*#{escaped}\s*\n+/, "")
    end

    # Removes the historical "CompanyName Logo (https://company.url/...)"
    # line generated by the layout's clickable header logo. The opening
    # `<a href=...><img alt="CompanyName Logo">...</a>` extracts as
    # `CompanyName Logo ( https://... )` in plaintext.
    def strip_logo_alt_line(text)
      return text unless Goodmail.config.logo_url.present? &&
                         Goodmail.config.company_url.present? &&
                         Goodmail.config.company_name.present?

      company_name = Regexp.escape(Goodmail.config.company_name)
      company_url = Regexp.escape(Goodmail.config.company_url)
      pattern = /^\s*#{company_name}\s+Logo\s*\(.*?#{company_url}.*?\).*\n?/i
      text.gsub(pattern, "")
    end

    # Builder's `image` / `inline_image` DSL helpers fall back to
    # `config.company_name` for the alt attribute when the caller
    # doesn't pass one. That's reasonable in HTML (screen readers
    # need SOMETHING). In plaintext, Premailer extracts the alt
    # verbatim — leaving a stray "CompanyName" line on its own
    # next to wherever the image landed.
    #
    # We strip standalone lines that EXACTLY match the company name.
    # This is conservative: a message with the company name embedded
    # in a sentence ("Welcome to CarHey, where we share rides")
    # is preserved verbatim — only lines that are nothing but the
    # bare company name are removed.
    def strip_company_name_alt_line(text)
      return text unless Goodmail.config.company_name.present?

      company_name = Regexp.escape(Goodmail.config.company_name)
      text.gsub(/^\s*#{company_name}\s*$\n?/, "")
    end

    # Removes lines that consist *only* of an http(s) URL — those
    # almost always come from an image link the layout renders that
    # extracts as a standalone footnote-style URL in plaintext. URLs
    # inside a sentence (`visit https://x.co for more`) are preserved
    # because the regex requires the URL to be the entire line.
    def strip_standalone_url_lines(text)
      text.gsub(/^\s*https?:\/\/\S+\s*$\n?/i, "")
    end

    # Compacts runs of 3+ newlines down to exactly 2 (one blank line
    # between paragraphs is the canonical readable shape; more is
    # visual noise from cumulative gsubs above).
    def compact_blank_lines(text)
      text.gsub(/\n{3,}/, "\n\n")
    end
  end
end
