# Local design tools

Debug builds have Card lab and Color lab switches in Settings. Values stay on
this device, in separate app preferences. These tools do not write clinic data.
Hide closes a panel and keeps its values. Reset restores the source defaults.
Release builds have no lab controls and do not load saved lab values.

Both panels appear only on the Schedule screen and share the same visibility
rule. Hide them while a sheet or another destination is open. Color lab values
still apply across app screens and sheets. Drag the header to move it. Collapse keeps its
header available. Each color starts in Hex mode and also supports the native
palette and RGB or HSL channels. Opacity is available in every mode, including
Hex. Hex accepts six RGB digits with an optional # prefix. Named system colors
are also available. Numeric fields and sliders edit the same value.
The Today selected controls switch the date strip text between accent, white,
and black and set its accent glass tint opacity. The defaults are accent and 20%.
These values persist when the panel is hidden and reset with Reset all.
Unselected today text always uses the full-opacity accent.
Editing a channel converts a system color to a fixed sRGB color. A system choice
stays semantic until a channel or palette edit replaces it.

App-owned colors use the shared palette. Keep new fills, text, symbols, and
borders on that path so the lab can reach them. Accent-derived draft fills and
outlines follow the accent until they have their own override. Card lab opacity
still applies after color selection. The panel uses its own native colors so it
stays readable when a test palette has low contrast.

Native navigation, tab bars, and plain controls keep their system tint when the
app accent changes. Liquid Glass keeps its native materials and state effects.
The widget uses source defaults; app preferences do not change its process.

An empty palette must preserve the original appearance. Never install the app
accent as a root tint, even after an explicit color edit: native toolbar buttons
and other controls can use a different color. Only existing app accent roles
follow the Accent control. Keep primary, secondary, and tertiary foreground styles
as inherited styles rather than fixed label colors. Tests compare every default
against the PR #13 source styles in both light and dark mode.

Prominent buttons already use the app accent. Use `.appGlassProminent` or
`.appBorderedProminent` to keep their color rule in one shared style. Each style
wraps the native button style and reads the palette. No separate tint modifier
is needed at each button. Keep this tint off shared containers and navigation
so adjacent plain and standard glass buttons keep their original colors.
