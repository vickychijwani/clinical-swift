# Local design tools

Debug builds have Card lab and Color lab switches in Settings. Values stay on
this device, in separate app preferences. These tools do not write clinic data.
Hide closes a panel and keeps its values. Reset restores the source defaults.
Release builds have no lab controls and do not load saved lab values.

Color lab shows live changes across app screens and the details, patient edit,
and appointment message sheets. Drag the header to move it. Collapse keeps its
header available. Each color supports the native palette, RGB or HSL channels,
opacity, and named system colors. Numeric fields and sliders edit the same value.
Editing a channel converts a system color to a fixed sRGB color. A system choice
stays semantic until a channel or palette edit replaces it.

App-owned colors use the shared palette. Keep new fills, text, symbols, and
borders on that path so the lab can reach them. Accent-derived draft fills and
outlines follow the accent until they have their own override. Card lab opacity
still applies after color selection. The panel uses its own native colors so it
stays readable when a test palette has low contrast.

Native navigation, tab bars, controls, and Liquid Glass keep their system
materials and state effects. The lab changes their app tint. The widget uses the
source defaults; app preference changes do not change its separate process.
