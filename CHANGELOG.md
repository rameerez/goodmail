## [0.3.0] - 2025-05-15
- Add Goodmail.render for custom mailers

## [0.2.0] - 2025-05-02

### Added

- **New DSL Methods:** Added `code_box` and `price_row` for displaying formatted content like license keys or simple line items.
- **Configuration Validation:** Added validation to ensure required config keys (`company_name`, `brand_color`) are set on application startup.
- **Clickable Logo:** Added `config.company_url` to make the header logo clickable.
- **Preheader Text:** Added support for hidden preheader text via `config.default_preheader` and `headers[:preheader]`.
- **Schema.org Microdata:** Included basic Schema.org (`EmailMessage`, `ConfirmAction`) markup in the layout template for potential enhancements in email clients (like Gmail action buttons).

### Fixed

- Resolved Action Mailer errors related to template lookups and `deliver_later` safety checks.
- Correctly added `.html_safe` to MSO conditional comment wrappers in Builder to prevent Rails from escaping them.
- Corrected plaintext generation issues related to image alt text and signatures.

## [0.1.0] - 2025-05-02

- Initial release
