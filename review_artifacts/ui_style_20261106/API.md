# Design system API — published for concurrent UI owners

Import `res://scripts/ui/design_system/widgets.gd` as `UI` and `res://scripts/ui/design_system/theme.gd` as `Skin`.

Stable API being implemented in these exclusive directories:
- `Skin.create() -> Theme`; assign to an owned screen root, never project/global theme.
- `Skin.card_style(rarity: String, selected: bool = false) -> StyleBoxFlat`.
- `UI.action(label: String, icon: String, callback: Callable, primary: bool = false) -> Button`.
- `UI.header(title: String, subtitle: String, close_callback: Callable) -> VBoxContainer`; close only, no station switching.
- `UI.card(title: String, detail: String, icon: String, rarity: String = "Common") -> PanelContainer`; named children `Content/Icon`, `Content/Copy/Title`, `Content/Copy/Detail`, `Content/Copy/Rarity`.
- `UI.field(label: String, placeholder: String, hint: String = "") -> VBoxContainer`; named `Input` LineEdit and `Feedback` Label. `UI.field_error(field, message)` toggles error styling; validation/parsing remains with caller.
- `UI.badge(text: String, icon: String = "info") -> HBoxContainer`.
- `UI.icon(name: String) -> Texture2D`; original SVGs, unknown -> component fallback.
- `responsive_grid.gd`: GridContainer, `minimum_card_width`, `maximum_columns`; changes columns only.
- `dialog.gd`: Control; `configure(title, subtitle)`, `body: VBoxContainer`, `actions: HFlowContainer`, `open()`, `dismiss()`, `dismissed` signal. No game/session/capture calls.

Known icon keys: resistor, capacitor, inductor, diode, chip, led, switch, component, cart, search, close, back, check, warning, info, settings, inventory, circuit, course, home, palette, network, play, plus, minus, save, lock.

Rarity is presentation text supplied by the existing catalog. No catalog/schema, rating parser, balance, ownership, purchase, or authority logic belongs here. Theme variants: `PrimaryButton`, `QuietButton`, `DangerButton`, `ErrorLineEdit`, `CardPanel`, `TitleLabel`, `SubtitleLabel`, `MutedLabel`, `ErrorLabel`.

Fixture will be additive, not attached to the running scene. Integration remains staged; no engine or runtime validation during playtest.

API readiness: version 1 is implemented now. `widgets.gd.API_VERSION == 1`. Existing signatures above are stable. Additional opt-in helpers: `text(value, variant="Label")`, `style_button(existing_button, icon_key="component", primary=false)` (keeps all callbacks), `action_icon(label)` (presentation hint, caller can explicitly override), `section(title, subtitle="", icon_key="component")` (caller adds controls to named `Body`), `status(message, severity="info")`, `empty_state(title, detail, icon_key="inventory")`.

Additional implemented icon keys: chat, user, map, clock, trade, meter, scope, code, folder, upload, download, refresh, trash, volume, keyboard. 42 original SVG assets total. All icons retain visible labels in control factories.

Direct-file owners are now assigned to every remaining screen group. Treat `adoption.patch` and `adoption_patches.json` as a review/staging artifact only. Main may take its shared electronics helper hunk after exact preimage checks; all other owners can consume the equivalent changes while implementing their substantive redesign. Never apply these patches over new owner work.
