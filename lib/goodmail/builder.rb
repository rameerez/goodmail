# frozen_string_literal: true
require "erb"
require "rails-html-sanitizer" # Require the sanitizer

module Goodmail
  # Builds the HTML content string based on DSL method calls.
  class Builder
    include ERB::Util # For the h() helper

    # Initialize a basic sanitizer allowing only <a> tags with href
    HTML_SANITIZER = Rails::Html::SafeListSanitizer.new
    ALLOWED_TAGS = %w(a).freeze
    ALLOWED_ATTRIBUTES = %w(href).freeze

    attr_reader :parts

    def initialize
      @parts = []
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
    # NOTE: This does not create a table structure.
    def price_row(name, price)
      parts << %(<p style="font-weight:bold; text-align:center; border-top:1px solid #eaeaea; padding:20px 0; margin: 0;">#{h name} &ndash; #{h price}</p>)
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

    %i[h1 h2 h3].each do |heading_tag|
      define_method(heading_tag) do |str|
        # Added basic heading styles, consistent with layout.erb
        style = case heading_tag
                when :h1 then "margin: 40px 0 10px; font-size: 32px; font-weight: 500; line-height: 1.2em;"
                when :h2 then "margin: 40px 0 10px; font-size: 24px; font-weight: 400; line-height: 1.2em;"
                when :h3 then "margin: 40px 0 10px; font-size: 18px; font-weight: 400; line-height: 1.2em;"
                else "margin: 16px 0; line-height: 1.6;"
                end
        # Headings should still have their content escaped
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
  end
end
