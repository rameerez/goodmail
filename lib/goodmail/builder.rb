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
      # Use a class for easier styling via layout CSS
      parts << %(<div class="goodmail-button" style="text-align: center; margin: 24px 0;"><a href="#{h url}"><span style=\"color:#ffffff;\">#{h text}</span></a></div>)
    end

    def image(src, alt = "", width: nil, height: nil)
      style = "max-width:100%; height:auto;"
      style += " width:#{width}px;" if width
      style += " height:#{height}px;" if height
      # Use a class for easier styling via layout CSS
      parts << %(<img class="goodmail-image" src="#{h src}" alt="#{h alt}" style="#{style}">)
    end

    def space(px = 16)
      # Rely on CSS height for spacing, avoid &nbsp; if possible
      parts << %(<div style="height:#{Integer(px)}px; line-height: #{Integer(px)}px; font-size: 1px;"></div>)
    end

    def sign(name = Goodmail.config.company_name)
      # Directly add the paragraph with the raw styled span
      # Name is escaped using h() to prevent injection if config is compromised
      parts << %(<p style="margin:16px 0; line-height: 1.6;"><span style="color: #888;">– #{h name}</span></p>)
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
