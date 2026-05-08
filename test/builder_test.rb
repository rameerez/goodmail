# frozen_string_literal: true

require "test_helper"

# Tests for `Goodmail::Builder` — the DSL evaluator that backs every
# `Goodmail.compose { ... }` and `Goodmail.render { ... }` block.
#
# We exercise the Builder directly (`Builder.new.instance_eval { ... }`)
# so each DSL helper is checked in isolation, with its raw HTML output
# inspected before Premailer has a chance to mutate it. End-to-end tests
# (compose / render) live in their own files.
class BuilderTest < Minitest::Test
  def setup
    super # GoodmailTestConfig.configure — gives us a Test Co. + #111827
    @builder = Goodmail::Builder.new
  end

  # ── parts / attachments / html_output ────────────────────────────────

  def test_a_fresh_builder_starts_empty
    assert_equal [], @builder.parts
    assert_equal [], @builder.attachments
    assert_equal "", @builder.html_output
  end

  def test_html_output_joins_parts_with_newlines
    @builder.instance_eval do
      text "first"
      text "second"
    end
    assert_equal 2, @builder.parts.length
    assert_match(/<p[^>]*>first<\/p>\n<p[^>]*>second<\/p>/, @builder.html_output)
  end

  def test_parts_attr_writer_is_private_to_block_external_mutation
    refute_respond_to @builder, :parts=,
                       "external code shouldn't be able to swap out the collected parts wholesale"
  end

  # ── text ─────────────────────────────────────────────────────────────

  def test_text_wraps_content_in_a_paragraph_tag
    @builder.instance_eval { text "hello" }
    assert_equal 1, @builder.parts.length
    assert_match(/\A<p [^>]*>hello<\/p>\z/, @builder.parts.first)
  end

  def test_text_applies_inline_paragraph_style
    @builder.instance_eval { text "hi" }
    assert_match(/style="margin:16px 0; line-height: 1\.6;"/, @builder.parts.first)
  end

  def test_text_preserves_safe_inline_anchor_tags
    @builder.instance_eval { text 'visit <a href="https://example.com">our site</a>' }
    assert_match(/<a href="https:\/\/example\.com">our site<\/a>/, @builder.parts.first)
  end

  def test_text_preserves_strong_em_b_i_inline_emphasis
    # 0.4.1 expanded the allowed-tags list. This locks the contract so a
    # future contributor doesn't silently shrink it again.
    @builder.instance_eval { text "<strong>bold</strong> <em>italic</em> <b>also</b> <i>also</i>" }
    output = @builder.parts.first
    assert_includes output, "<strong>bold</strong>"
    assert_includes output, "<em>italic</em>"
    assert_includes output, "<b>also</b>"
    assert_includes output, "<i>also</i>"
  end

  def test_text_strips_unsafe_tags_silently
    # `Rails::Html::SafeListSanitizer` strips disallowed TAGS but keeps
    # their text content as-is. That's the canonical sanitizer contract:
    # an attacker can't break the document structure via injected tags,
    # but the text body of a stripped tag survives as a literal string
    # (no script execution, since there's no `<script>` element left).
    @builder.instance_eval do
      text '<script>alert("xss")</script>safe content'
    end
    output = @builder.parts.first
    refute_includes output, "<script>"
    refute_includes output, "</script>"
    assert_includes output, "safe content"
  end

  def test_text_strips_disallowed_attributes
    # `class` and `onclick` are not in `ALLOWED_ATTRIBUTES`. The sanitizer
    # drops them but keeps the tag.
    @builder.instance_eval do
      text '<a href="https://x.co" class="evil" onclick="bad()">click</a>'
    end
    output = @builder.parts.first
    assert_includes output, '<a href="https://x.co">click</a>'
    refute_includes output, "class="
    refute_includes output, "onclick"
  end

  def test_text_converts_newlines_to_br_tags
    @builder.instance_eval { text "line one\nline two\nline three" }
    output = @builder.parts.first
    assert_includes output, "line one<br>line two<br>line three"
  end

  def test_text_coerces_non_strings_via_to_s
    @builder.instance_eval { text 12_345 }
    assert_match(/<p[^>]*>12345<\/p>/, @builder.parts.first)
  end

  def test_text_is_safe_against_amp_and_quote_injection_when_no_html_present
    # Plain & gets passed through as-is by SafeListSanitizer when there's no
    # HTML to escape. What matters is that injected HTML structure cannot
    # break out — covered by the script-strip test above.
    @builder.instance_eval { text "Q&A: who?" }
    assert_includes @builder.parts.first, "Q&amp;A: who?"
  end

  # ── h1 / h2 / h3 ─────────────────────────────────────────────────────

  def test_h1_h2_h3_render_with_distinct_inline_styles
    @builder.instance_eval do
      h1 "Big"
      h2 "Mid"
      h3 "Small"
    end
    assert_match(/<h1[^>]*font-size: 32px[^>]*>Big<\/h1>/, @builder.parts[0])
    assert_match(/<h2[^>]*font-size: 24px[^>]*>Mid<\/h2>/, @builder.parts[1])
    assert_match(/<h3[^>]*font-size: 18px[^>]*>Small<\/h3>/, @builder.parts[2])
  end

  def test_h1_html_escapes_content_so_user_input_cannot_inject
    @builder.instance_eval { h1 "<script>alert(1)</script>" }
    output = @builder.parts.first
    assert_includes output, "&lt;script&gt;alert(1)&lt;/script&gt;"
    refute_includes output, "<script>"
  end

  def test_h2_and_h3_also_escape_content
    @builder.instance_eval do
      h2 "<b>two</b>"
      h3 "<b>three</b>"
    end
    assert_includes @builder.parts[0], "&lt;b&gt;two&lt;/b&gt;"
    assert_includes @builder.parts[1], "&lt;b&gt;three&lt;/b&gt;"
  end

  # ── button ───────────────────────────────────────────────────────────

  def test_button_emits_anchor_with_url_and_label
    @builder.instance_eval { button "Open it", "https://example.com/open" }
    output = @builder.parts.first
    assert_includes output, 'href="https://example.com/open"'
    assert_includes output, "Open it"
  end

  def test_button_includes_outlook_vml_fallback
    @builder.instance_eval { button "CTA", "https://x.co" }
    output = @builder.parts.first
    assert_includes output, "<v:roundrect"
    assert_includes output, "<![endif]-->"
    assert_includes output, "<!--[if !mso]><!-->"
  end

  def test_button_uses_brand_color_in_VML_fillcolor
    GoodmailTestConfig.configure(brand_color: "#abcdef")
    @builder.instance_eval { button "CTA", "https://x.co" }
    assert_includes @builder.parts.first, "fillcolor=\"#abcdef\""
  end

  def test_button_html_escapes_label_to_block_xss
    @builder.instance_eval { button "<script>x</script>", "https://x.co" }
    output = @builder.parts.first
    refute_includes output, "<script>x</script>"
    assert_includes output, "&lt;script&gt;x&lt;/script&gt;"
  end

  def test_button_html_escapes_url_so_query_string_cant_inject
    @builder.instance_eval { button "View", 'https://x.co/?q="><script>x</script>' }
    output = @builder.parts.first
    refute_match(/<script>/, output)
    assert_includes output, "&quot;&gt;&lt;script&gt;"
  end

  def test_button_styling_does_not_capitalize_label_casing
    # Default styling preserves the EXACT casing the caller wrote — no
    # `text-transform: capitalize`. A button labeled "view receipt"
    # renders as "view receipt", not "View Receipt"; "OPEN" stays
    # "OPEN". The previous default was opinionated and broke acronyms,
    # all-lowercase casual copy, and i18n cases where capitalization
    # rules differ from English (German nouns, Spanish "el iPhone").
    @builder.instance_eval { button "view receipt", "https://x.co/r/1" }
    full_html = Goodmail::Layout.render(@builder.html_output, "S")
    refute_match(/text-transform:\s*capitalize/, full_html,
                 "default button styling must not force any text-transform")
  end

  # ── image ────────────────────────────────────────────────────────────

  def test_image_emits_img_tag_with_src_and_alt
    @builder.instance_eval { image "https://cdn.example.com/x.png", "A photo" }
    output = @builder.parts.first
    assert_includes output, 'src="https://cdn.example.com/x.png"'
    assert_includes output, 'alt="A photo"'
  end

  def test_image_falls_back_to_company_name_for_alt_when_blank
    GoodmailTestConfig.configure(company_name: "Acme")
    @builder.instance_eval { image "https://cdn.example.com/x.png" }
    assert_includes @builder.parts.first, 'alt="Acme"'
  end

  def test_image_inlines_width_when_provided
    @builder.instance_eval { image "https://cdn.example.com/x.png", "alt", width: 600 }
    assert_includes @builder.parts.first, "width:600px"
  end

  def test_image_inlines_height_when_provided
    @builder.instance_eval { image "https://cdn.example.com/x.png", "alt", height: 400 }
    assert_includes @builder.parts.first, "height:400px"
  end

  def test_image_includes_mso_outlook_table_wrapper
    @builder.instance_eval { image "https://cdn.example.com/x.png" }
    output = @builder.parts.first
    assert_includes output, "<!--[if mso]>"
    assert_match(/role="presentation"/, output)
  end

  def test_image_html_escapes_src_attribute
    @builder.instance_eval { image '"><script>x</script>', "alt" }
    output = @builder.parts.first
    refute_match(/<script>/, output)
    assert_includes output, "&quot;&gt;&lt;script&gt;"
  end

  # ── price_row ────────────────────────────────────────────────────────

  def test_price_row_emits_centered_bold_paragraph_with_separator
    @builder.instance_eval { price_row "Premium plan", "$49.00" }
    output = @builder.parts.first
    assert_includes output, "Premium plan"
    assert_includes output, "$49.00"
    assert_includes output, "&ndash;"
    assert_includes output, "text-align:center"
    assert_includes output, "font-weight:bold"
  end

  def test_price_row_html_escapes_both_sides
    @builder.instance_eval { price_row "<b>Premium</b>", "<script>x</script>" }
    output = @builder.parts.first
    refute_match(/<b>Premium<\/b>/, output)
    refute_match(/<script>/, output)
    assert_includes output, "&lt;b&gt;Premium&lt;/b&gt;"
    assert_includes output, "&lt;script&gt;x&lt;/script&gt;"
  end

  # ── info_row ─────────────────────────────────────────────────────────

  def test_info_row_emits_a_two_cell_presentation_table
    @builder.instance_eval { info_row "Distance", "18 km" }
    output = @builder.parts.first
    assert_match(/<table[^>]*role="presentation"/, output)
    assert_match(/<td[^>]*>Distance<\/td>/, output)
    assert_match(/<td[^>]*>18 km<\/td>/, output)
  end

  def test_info_row_label_uses_muted_grey
    @builder.instance_eval { info_row "Distance", "18 km" }
    output = @builder.parts.first
    # First <td> is the label cell.
    label_cell = output[/<td[^>]*?>Distance<\/td>/]
    assert_includes label_cell, "color:#6b7280"
    assert_includes label_cell, "font-weight:400"
  end

  def test_info_row_value_uses_dark_text_and_email_safe_align_attribute
    @builder.instance_eval { info_row "Distance", "18 km" }
    output = @builder.parts.first
    # Email clients vary on whether `text-align: right` (CSS) survives
    # Premailer + their own renderer; the `align="right"` HTML attribute
    # is the email-safe fallback. We intentionally emit both.
    value_cell = output[/<td[^>]*?>18 km<\/td>/]
    assert_includes value_cell, 'align="right"'
    assert_includes value_cell, "font-weight:600"
    assert_includes value_cell, "color:#111827"
  end

  def test_info_row_html_escapes_both_label_and_value
    @builder.instance_eval { info_row "<b>Distance</b>", "<script>x</script>" }
    output = @builder.parts.first
    refute_match(/<b>Distance<\/b>/, output)
    refute_match(/<script>/, output)
    assert_includes output, "&lt;b&gt;Distance&lt;/b&gt;"
    assert_includes output, "&lt;script&gt;x&lt;/script&gt;"
  end

  def test_info_row_coerces_non_string_label_and_value
    @builder.instance_eval { info_row :seats, 3 }
    output = @builder.parts.first
    assert_match(/<td[^>]*>seats<\/td>/, output)
    assert_match(/<td[^>]*>3<\/td>/, output)
  end

  def test_info_row_includes_bottom_hairline_for_visual_separation
    @builder.instance_eval { info_row "Foo", "Bar" }
    output = @builder.parts.first
    assert_includes output, "border-bottom:1px solid #eaeaea"
  end

  # ── code_box ─────────────────────────────────────────────────────────

  def test_code_box_emits_a_styled_paragraph_with_centered_bold_content
    @builder.instance_eval { code_box "ABC-123" }
    output = @builder.parts.first
    assert_includes output, "<strong>ABC-123</strong>"
    assert_includes output, "background:#F8F8F8"
    assert_includes output, "text-align:center"
  end

  def test_code_box_html_escapes_content
    @builder.instance_eval { code_box "<script>x</script>" }
    output = @builder.parts.first
    refute_match(/<script>x<\/script>/, output)
    assert_includes output, "&lt;script&gt;x&lt;/script&gt;"
  end

  # ── space ────────────────────────────────────────────────────────────

  def test_space_emits_a_div_with_default_height_of_16px
    @builder.instance_eval { space }
    output = @builder.parts.first
    assert_includes output, "height:16px"
    assert_includes output, "line-height: 16px"
  end

  def test_space_accepts_a_custom_height
    @builder.instance_eval { space 32 }
    assert_includes @builder.parts.first, "height:32px"
  end

  def test_space_coerces_string_integers_via_Integer
    @builder.instance_eval { space "24" }
    assert_includes @builder.parts.first, "height:24px"
  end

  def test_space_raises_ArgumentError_on_non_integer_input_so_typos_surface
    assert_raises(ArgumentError) { @builder.instance_eval { space "twenty" } }
  end

  # ── line ─────────────────────────────────────────────────────────────

  def test_line_emits_a_styled_horizontal_rule
    @builder.instance_eval { line }
    assert_equal '<hr class="goodmail-hr">', @builder.parts.first
  end

  # ── center ───────────────────────────────────────────────────────────

  def test_center_wraps_block_output_in_a_centered_div
    @builder.instance_eval do
      center { text "in the middle" }
    end
    assert_equal 1, @builder.parts.length
    output = @builder.parts.first
    assert_match(/\A<div style="text-align:center;">/, output)
    assert_includes output, "in the middle"
    assert output.end_with?("</div>")
  end

  def test_center_block_can_emit_multiple_parts_that_get_joined
    @builder.instance_eval do
      center do
        text "first line"
        text "second line"
      end
    end
    output = @builder.parts.first
    # Two paragraphs survive INSIDE the center wrapper, joined by \n.
    assert_equal 2, output.scan("<p ").length
  end

  def test_center_restores_outer_parts_when_block_raises
    assert_raises(RuntimeError) do
      @builder.instance_eval do
        text "before"
        center do
          text "inside"
          raise "boom"
        end
      end
    end
    # The `before` part should still be there, untouched. The `inside` part
    # should NOT — we never finished the center wrap, so we don't bake
    # the half-built block into the final output.
    assert_equal 1, @builder.parts.length
    assert_includes @builder.parts.first, "before"
  end

  # ── sign ─────────────────────────────────────────────────────────────

  def test_sign_defaults_to_company_name
    GoodmailTestConfig.configure(company_name: "Hola Co.")
    @builder.instance_eval { sign }
    assert_includes @builder.parts.first, "Hola Co."
  end

  def test_sign_accepts_an_explicit_name_override
    @builder.instance_eval { sign "The Support Team" }
    assert_includes @builder.parts.first, "The Support Team"
  end

  def test_sign_html_escapes_the_name
    @builder.instance_eval { sign "<b>Team</b>" }
    refute_match(/<b>Team<\/b>/, @builder.parts.first)
    assert_includes @builder.parts.first, "&lt;b&gt;Team&lt;/b&gt;"
  end

  # ── link ─────────────────────────────────────────────────────────────

  def test_link_emits_a_paragraph_anchor_styled_with_brand_color
    GoodmailTestConfig.configure(brand_color: "#deadbeef")
    @builder.instance_eval { link "Open the receipt", "https://example.com/r/1" }
    output = @builder.parts.first
    assert_match(/<p[^>]*><a href="https:\/\/example\.com\/r\/1"[^>]*>Open the receipt<\/a><\/p>/, output)
    assert_includes output, "color:#deadbeef"
    assert_includes output, "text-decoration:underline"
  end

  def test_link_html_escapes_label_and_url
    @builder.instance_eval do
      link '<script>x</script>', 'javascript:alert(1)'
    end
    output = @builder.parts.first
    # Label content is escaped.
    refute_includes output, "<script>x</script>"
    assert_includes output, "&lt;script&gt;x&lt;/script&gt;"
    # URL is HTML-escaped (Goodmail does NOT enforce a scheme allow-list — the
    # gem is for trusted-content transactional emails, not arbitrary input.
    # If callers need scheme-validation, that's a host-app concern). What we
    # DO check is that the URL can't break out of the `href=""` attribute.
    refute_match(/<script/, output[%r{href="[^"]*"}])
  end

  # ── small ────────────────────────────────────────────────────────────

  def test_small_emits_grey_low_emphasis_paragraph
    @builder.instance_eval { small "Fine print." }
    output = @builder.parts.first
    assert_match(/<p[^>]*>Fine print\.<\/p>/, output)
    assert_includes output, "color: #777"
    assert_includes output, "font-size: 12px"
  end

  def test_small_runs_through_the_same_sanitizer_as_text
    @builder.instance_eval { small "<strong>read</strong> <script>x</script>" }
    output = @builder.parts.first
    assert_includes output, "<strong>read</strong>"
    refute_match(/<script>/, output)
  end

  def test_small_handles_newlines_via_br
    @builder.instance_eval { small "first\nsecond" }
    assert_includes @builder.parts.first, "first<br>second"
  end

  # ── attach ───────────────────────────────────────────────────────────

  def test_attach_records_a_non_inline_attachment_descriptor
    @builder.instance_eval { attach "receipt.pdf", "PDF_BYTES", mime_type: "application/pdf" }
    assert_equal 1, @builder.attachments.length
    a = @builder.attachments.first
    assert_equal "receipt.pdf", a[:filename]
    assert_equal "PDF_BYTES", a[:content]
    assert_equal "application/pdf", a[:mime_type]
    assert_equal false, a[:inline]
  end

  def test_attach_accepts_a_filesystem_path_and_reads_the_file
    Tempfile.create(["attach_test", ".txt"]) do |f|
      f.write("hello from disk")
      f.flush
      @builder.instance_eval { attach "data.txt", f.path, mime_type: "text/plain" }
    end
    a = @builder.attachments.first
    assert_equal "hello from disk", a[:content]
  end

  def test_attach_treats_NUL_byte_strings_as_binary_content_not_paths
    # Regression guard for the 0.4.2 fix: `File.file?` raises ArgumentError
    # on Strings containing `\0`, and PNG / PDF / .ics bytes routinely
    # contain NUL bytes (PNG IHDR chunk length, PDF cross-reference
    # offsets, .ics produced through binary-safe transports, etc).
    # The resolver short-circuits before `File.file?` so these don't
    # crash the gem.
    binary = "\x89PNG\r\n\x1A\n\x00\x00\x00\rIHDR".b
    assert_includes binary, "\x00", "test setup precondition: binary should contain a NUL byte"
    @builder.instance_eval { attach "logo.png", binary }
    assert_equal binary, @builder.attachments.first[:content]
  end

  def test_attach_treats_strings_longer_than_PATH_MAX_as_content_not_paths
    # Many filesystems cap PATH_MAX at 4096; a 5KB String is structurally
    # not a path. The resolver short-circuits to avoid an unnecessary
    # disk syscall + a confusing fallthrough that would otherwise return
    # the bytes anyway.
    long_content = "x" * 5_000
    @builder.instance_eval { attach "big.txt", long_content }
    assert_equal long_content, @builder.attachments.first[:content]
  end

  def test_attach_returns_non_string_content_unchanged
    io = StringIO.new("from io")
    @builder.instance_eval { attach "x.txt", io }
    assert_same io, @builder.attachments.first[:content]
  end

  def test_attach_mime_type_defaults_to_nil_when_omitted
    @builder.instance_eval { attach "x.txt", "bytes" }
    assert_nil @builder.attachments.first[:mime_type]
  end

  def test_attach_inline_flag_defaults_to_false
    @builder.instance_eval { attach "x.txt", "bytes" }
    assert_equal false, @builder.attachments.first[:inline]
  end

  def test_attach_records_inline_when_requested
    @builder.instance_eval { attach "logo.png", "bytes", inline: true }
    assert_equal true, @builder.attachments.first[:inline]
  end

  def test_attach_coerces_filename_to_string
    @builder.instance_eval { attach :receipt, "bytes" }
    assert_equal "receipt", @builder.attachments.first[:filename]
  end

  # ── inline_image ─────────────────────────────────────────────────────

  def test_inline_image_records_an_inline_attachment
    @builder.instance_eval { inline_image "logo.png", "PNG_BYTES" }
    assert_equal 1, @builder.attachments.length
    a = @builder.attachments.first
    assert_equal "logo.png", a[:filename]
    assert_equal "PNG_BYTES", a[:content]
    assert_equal true, a[:inline]
  end

  def test_inline_image_emits_an_img_tag_with_a_cid_reference
    @builder.instance_eval { inline_image "logo.png", "PNG_BYTES" }
    output = @builder.parts.first
    assert_includes output, 'src="cid:logo.png"'
  end

  def test_inline_image_uses_company_name_alt_when_no_alt_passed
    GoodmailTestConfig.configure(company_name: "Acme")
    @builder.instance_eval { inline_image "logo.png", "PNG_BYTES" }
    assert_includes @builder.parts.first, 'alt="Acme"'
  end

  def test_inline_image_passes_explicit_alt_through
    @builder.instance_eval { inline_image "logo.png", "PNG_BYTES", alt: "Hello" }
    assert_includes @builder.parts.first, 'alt="Hello"'
  end

  def test_inline_image_passes_width_and_height_to_the_img_tag
    @builder.instance_eval { inline_image "logo.png", "PNG_BYTES", width: 600, height: 200 }
    output = @builder.parts.first
    assert_includes output, "width:600px"
    assert_includes output, "height:200px"
  end

  def test_inline_image_propagates_mime_type_to_the_attachment_descriptor
    @builder.instance_eval { inline_image "logo.png", "PNG_BYTES", mime_type: "image/png" }
    assert_equal "image/png", @builder.attachments.first[:mime_type]
  end

  def test_inline_image_raises_on_duplicate_filename
    # Two `inline_image` calls with the same filename produce broken
    # output: both body refs point at `cid:FILENAME`, but Mail gem's
    # CID resolution returns the first matching part — the second
    # attachment has no addressable CID and renders as a broken icon.
    # Better to fail loud at registration time than silently ship a
    # broken image to recipients.
    error = assert_raises(Goodmail::Error) do
      @builder.instance_eval do
        inline_image "logo.png", "FIRST"
        inline_image "logo.png", "SECOND"
      end
    end
    assert_match(/duplicate inline filename/, error.message)
    assert_match(/logo\.png/, error.message)
    assert_match(/cid:logo\.png/, error.message,
                 "error message should explicitly mention the broken cid: reference")
  end

  def test_attach_allows_duplicate_filenames_for_non_inline_attachments
    # Non-inline attachments aren't referenced from the body via cid:
    # so a duplicate filename is just a UX wart (recipient sees two
    # files with the same name) rather than a rendering bug. We allow
    # it — users may have legit reasons (two CSV exports, two PDFs).
    @builder.instance_eval do
      attach "data.csv", "alpha,bytes"
      attach "data.csv", "beta,bytes"
    end
    assert_equal 2, @builder.attachments.length
    assert_equal ["data.csv", "data.csv"], @builder.attachments.map { |a| a[:filename] }
  end

  def test_attach_with_inline_then_non_inline_same_filename_is_allowed
    # Pathological corner — inline + non-inline with the same name.
    # The inline one gets the cid: reference, the non-inline one is
    # an attachment download. Different surfaces, no conflict.
    @builder.instance_eval do
      inline_image "logo.png", "INLINE_BYTES"
      attach "logo.png", "DOWNLOAD_BYTES"
    end
    assert_equal 2, @builder.attachments.length
  end

  # ── html (raw passthrough) ───────────────────────────────────────────

  def test_html_passes_raw_string_through_without_escaping
    @builder.instance_eval { html "<custom-thing data-x=\"1\">hi</custom-thing>" }
    assert_equal '<custom-thing data-x="1">hi</custom-thing>', @builder.parts.first
  end

  def test_html_coerces_non_string_via_to_s
    @builder.instance_eval { html 42 }
    assert_equal "42", @builder.parts.first
  end

  # ── DSL composition (smoke that everything plays together) ───────────

  def test_complex_block_composes_into_correct_part_count_and_order
    @builder.instance_eval do
      h1 "Hello"
      text "Body 1"
      space 24
      info_row "Distance", "18 km"
      info_row "Duration", "25 min"
      button "CTA", "https://x.co"
      line
      sign
    end
    assert_equal 8, @builder.parts.length
    # First part must be the h1, last must be the sign.
    assert_match(/<h1[^>]*>Hello<\/h1>/, @builder.parts.first)
    assert_match(/Test Co\./, @builder.parts.last)
  end
end
