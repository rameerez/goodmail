## [0.4.0] - 2026-05-08

A polish-and-correctness release. Adds five new DSL helpers, a comprehensive Minitest 6 test suite (100% line coverage), and fixes nine real-world bugs that surfaced after running every email shape through Mailcatcher and inspecting the rendered HTML, plaintext, headers, and attachments end-to-end. The bug fixes are the headline — most of them silently degraded plaintext quality, deliverability, or accessibility before; downstream apps inherit the fixes for free on upgrade.

### Added

#### DSL helpers
- **`link(text, url)`** — inline styled text link rendered in the configured `brand_color`. Cleaner than hand-writing `<a>` tags inside `text` blocks when the whole paragraph is the link.
- **`small(text)`** — small grey paragraph for fine print, legal disclaimers, and "you are receiving this because…" footers. Sanitization mirrors `text` (allows `<a>` / `<strong>` / `<em>` / `<b>` / `<i>`).
- **`info_row(label, value)`** — label/value row using the email-safe two-column table pattern Stripe / Linear / Square / Resend converge on for transactional info cards: muted label on the left, dark right-aligned value on the right, 1px hairline at the bottom. Use this when the LABEL is supporting context and the VALUE is the primary content (`Plan - Pro`, `Status - Active`). The existing `price_row` (centered, both sides equal weight) stays the right tool for receipt-style line items.
- **`attach(filename, content, mime_type:, inline:)`** — adds a binary attachment to the outgoing message. `content` accepts raw bytes OR a filesystem path (when the string matches an existing file, it's read for you). Pass `inline: true` to send the part with `Content-Disposition: inline`; prefer `inline_image` when you also want Goodmail to emit the matching `cid:` image tag.
- **`inline_image(filename, content, alt:, width:, height:, mime_type:)`** — convenience helper that registers an inline-disposition attachment AND emits the matching `<img src="cid:...">` tag at that point in the email body. Use when you need the image to travel with the email (no public hosting, offline reading, archival contexts); when you have a public URL prefer `image(src, alt)` — it's lighter on the wire.

#### Inline emphasis tags allowed in `text`
- `<strong>`, `<em>`, `<b>`, and `<i>` now pass through the `text(string)` sanitizer alongside `<a>`. Previously these were silently stripped, so copy like `text "<strong>Important:</strong> read the receipt"` rendered as plain `Important: read the receipt`. All four tags are universally supported in every modern email client and add no layout risk to the table-based template.

#### `Goodmail.render` parts struct
- `EmailParts` now carries an `attachments` field (in addition to `html` and `text`) populated with everything the DSL block registered via `attach` / `inline_image`. Inline descriptors include the generated `content_id` that matches the `cid:` URL emitted into the HTML.

#### Action Mailer integration helpers
- **Zero-include Action Mailer helpers.** When Goodmail loads, it installs private `goodmail_mail(...) { ... }`, `goodmail_render_parts(...) { ... }`, and `goodmail_mail_parts(parts, headers, unsubscribe_url:)` helpers on `ActionMailer::Base`. Custom mailers, Devise mailers, Pay mailers, and app-specific wrappers can use them without per-class include boilerplate. The helpers keep mailer instance variables/private helpers available inside DSL blocks, support render-only `locale:`, fan attachments into Action Mailer, pin inline Content-IDs, strip Goodmail-only headers before `mail()`, and add RFC 8058-correct unsubscribe headers.
- **Per-render configuration overrides.** `Goodmail.compose`, `Goodmail.render`, `goodmail_mail`, and `goodmail_render_parts` accept `config: { ... }` for tenant / product whitelabel emails. Overrides are scoped to the current render via a thread-local config and do not mutate process-wide `Goodmail.config`, so concurrent mail deliveries cannot bleed one product's branding into another's email.
- **Action Mailer header passthrough.** `Goodmail.compose` and the auto-installed mailer helpers now forward Action Mailer's normal header surface (`date:`, `return_path:`, delivery options, custom `"X-..."` headers, etc.) after stripping only Goodmail render options. This follows Rails' own `mail` behavior instead of maintaining a narrow Goodmail whitelist.

#### Test suite
- **252 tests, 907 assertions, 100% line coverage** across the Ruby source. The gem previously had no tests of its own; the README's `rake spec` instruction was aspirational. Run with `rake test`; gate SimpleCov instrumentation on `COVERAGE=1 rake test`.

### Fixed

#### Deliverability + headers
- **RFC 8058 one-click unsubscribe.** Goodmail now sets `List-Unsubscribe-Post: List-Unsubscribe=One-Click` alongside the existing `List-Unsubscribe` header when the unsubscribe URL is HTTPS, matching RFC 8058's HTTPS URI requirement. Non-HTTPS unsubscribe URLs still get the classic `List-Unsubscribe` header, but Goodmail no longer advertises one-click POST support for URLs that are not eligible. Gmail's and Yahoo's [Feb 2024 sender requirements](https://support.google.com/mail/answer/81126) treat missing one-click support as a spam signal for eligible bulk senders. Existing applications with HTTPS unsubscribe URLs inherit the fix on upgrade; make sure the final sender/provider DKIM-signs these headers, since Goodmail can only set them before delivery.

#### Plaintext quality
The plaintext part of every multipart message had four classes of artifact that surfaced after running real emails through Mailcatcher. Each one would silently degrade quality for recipients on text-only clients (CLI mail, accessibility tooling, spam filters that judge from the plaintext part):

- **Preheader no longer leaks as a phantom first line.** The layout's hidden inbox-preview `<span style="display:none">` was being extracted to plaintext by Premailer (which doesn't honor `display:none`), opening every email with a duplicate intro the recipient was never supposed to see in the body. The preheader span is now stripped from the source HTML before plaintext extraction, matched by its specific `display:none + font-size:1px` signature so legitimate hidden spans elsewhere are preserved.
- **Button labels no longer appear twice.** `button` emits both a `<v:roundrect>` (Outlook VML, inside `<!--[if mso]>...<![endif]-->`) AND a regular `<a>`. Premailer ignores conditional comments and was extracting text from BOTH, so plaintext got the label twice (once bare from the VML's `<center>label</center>`, once with the URL from `<a href>label</a>`). The MSO conditional blocks are now stripped from the source HTML before plaintext extraction.
- **Stray `CompanyName` line from inline image alt is gone.** `image` / `inline_image` calls without an explicit alt fall back to `config.company_name` (so screen readers have something to read). Premailer extracted that alt verbatim into plaintext, leaving a bare-company-name line floating next to every embedded image. The cleanup pass now strips standalone lines that exactly match the company name; legitimate uses embedded in sentences are preserved untouched.
- **`info_row` flattens to the conventional `Label: Value` shape in plaintext.** A two-cell `<table>` previously extracted as two separate lines (`Label\nValue`) — correct table extraction, but a worse plaintext UX than the colon-form every modern transactional sender uses. The HTML side keeps the visible two-cell table.

#### Encoding
- **HTML + plaintext: accented characters / Unicode no longer get double-encoded.** Premailer's libxml2 backend was defaulting to Latin-1 when no `<meta charset>` tag was present in the source HTML, mangling every UTF-8 character (`Duración` → `DuraciÃ³n`, `€` → `â¬`). All Premailer calls now pin `input_encoding: "UTF-8"`. The shipped layout already declares the meta charset; this fix protects custom `layout_path:` callers that don't.

#### Inline images
- **`inline_image` now produces an `<img>` that actually renders.** Mail gem auto-generates a globally-unique Content-ID (`<longhash@host.tld.mail>`) for every attachment, but the DSL must write the `<img src="cid:...">` before Action Mailer materializes the attachment. Goodmail now generates an RFC 2392-shaped Content-ID in the Builder, emits that exact `cid:` URL in the HTML, and pins the inline Mail part to the same ID so the body's reference resolves.
- **`attach` / `inline_image` no longer crash on binary content.** The path-or-bytes resolver was calling `File.file?` on the string unconditionally, and `File.file?` raises `ArgumentError: path name contains null byte` on any String containing `\0` — exactly what binary file content (PNG / PDF / .ics) routinely contains. The resolver now short-circuits when the string contains a NUL byte or exceeds typical PATH_MAX (4096 bytes), so the documented `inline_image("logo.png", png_bytes)` shape works as advertised.
- **Duplicate inline filenames raise `Goodmail::Error` at registration time.** Inline descriptors are still keyed by filename when custom `Goodmail.render` callers fan them into Action Mailer's attachments hash, so duplicate inline filenames are ambiguous even though Goodmail generates distinct Content-IDs. We now fail loud at the DSL with an actionable error. Non-inline `attach` with duplicate filenames is still allowed (it's a UX wart but not a rendering bug — recipients see two files with the same name).

#### Visual tweak
- **Buttons no longer force `text-transform: capitalize`.** The default styling now preserves the EXACT casing the caller wrote — a button labeled `view receipt` renders as `view receipt`, not `View Receipt`; `OPEN` stays `OPEN`. The previous default was opinionated and broke acronyms, all-lowercase casual copy, and i18n cases where capitalization rules differ from English (German nouns, Spanish proper nouns following articles).

### Internal
- Replaced the `case heading_tag` style lookup inside `Builder`'s `define_method` heading definer with a frozen `HEADING_STYLES` constant. The previous shape carried an unreachable `else` clause that no test could cover by construction; the replacement is shorter, faster (one hash lookup per heading), and exhaustive by definition.
- Extracted plaintext generation into `Goodmail::Plaintext`. Both `Goodmail::Email.render` and `Goodmail::Mailer#compose_message` previously had their own copies of the cleanup pipeline; consolidating into one module makes plaintext quality testable in one place and prevents future drift between the two paths.
- `ostruct` declared as an explicit runtime dependency. Goodmail requires it directly (configuration is backed by `OpenStruct`); Ruby 3.4 prints a deprecation warning when ostruct is loaded from the standard library, and Ruby 3.5 removes it from the default gems set entirely.

### Meta
- Standardized the testing scaffolding to match the convention shared with the sibling gems (`pricing_plans`, `profitable`, `usage_credits`):
  - `.simplecov` config file (auto-loaded; SimpleFormatter, branch coverage enabled, minimum thresholds, custom at_exit summary).
  - `Gemfile` with `:development` / `:development, :test` groups (minitest ~> 6.0, minitest-mock, minitest-reporters, simplecov, rubocop + rubocop-minitest + rubocop-performance).
  - `Rakefile` using `bundler/gem_tasks` + `Rake::TestTask`; `rake test` runs the suite with the canonical Minitest::Reporters output and emits the coverage summary at the end.
  - `.rubocop.yml` shared cop set + thresholds (style/layout/metrics overrides matching the other gems).
  - `.github/workflows/test.yml` matrix tests across Ruby 3.3, 3.4, and 4.0.
  - `.github/workflows/claude.yml` and `.github/workflows/claude-code-review.yml` for Claude Code automation parity.
  - `goodmail.gemspec` no longer carries development dependencies — they all live in the Gemfile groups, same as the sibling gems.

## [0.3.1] - 2026-02-25
- Maintenance release. Documentation alignment (example mailers
  follow the `Goodmailer` suffix convention) and a configuration
  alias (`Goodmail.configuration` ≡ `Goodmail.config`). No public
  API changes.

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
