# RothDevLib UI → Blizzard Native Rewrite

## Status Overview
Date: 2026-02-21 (updated after verification pass)

### ✅ DONE — Rewritten to v3 Blizzard-native
- [x] **Skin.lua** — Updated palette, preserved ALL public API (StyledButton, TabButton, BlizzButton, DarkFrame, DarkInset, ApplyWindow, ApplyInset, Badge, SearchBox, frame state persistence). Backward compatible.
- [x] **MainFrame.lua** — Full rewrite. ButtonFrameTemplate with portrait (bug icon), native title, PanelTemplates tabs (Errors/Monitor/Log), compact status line, SearchBox, splitter, resize grip, Blizzard-style status bar buttons.
- [x] **DetailView.lua** — v3 rewrite. Sub-tabs → UIPanelButtonTemplate toggle buttons. Action buttons → Skin:BlizzButton. Content area → Skin:ApplyInset. Occur nav → Skin:BlizzButton. All logic unchanged.
- [x] **ExportFrame.lua** — v3 rewrite. ButtonFrameTemplate dialog with portrait, native title/close. Blizzard buttons for Select All/Copy/Close. Body uses Skin:ApplyInset. Resize grip via PanelResizeButtonTemplate.

### ✅ DONE — Verified compatible (no changes needed)
- [x] **GroupGrid.lua** — Uses Skin.C palette for row colors. All referenced colors (rowAlt, rowSelected, bg, titleBg, textBright) exist in v3 Skin.lua. WowStyle1FilterDropdownTemplate + legacy UIDropDownMenu fallback both work. RothDevLibGroupRowTemplate in Templates.xml present.
- [x] **Monitor.lua** — Uses Skin:DarkInset, Skin:DarkFrame, Skin:StyledButton, Skin:SearchBox, Skin:CreateResizeGrip, Skin:SavePaneState/GetPaneState — all exist in v3 Skin.lua. RothDevLibMonitorRowTemplate in Templates.xml present.
- [x] **Table.lua** — Generic table widget used by Monitor. No Skin-breaking changes.
- [x] **Templates.xml** — Both row templates (GroupRow + MonitorRow) present and unchanged.

### 📋 NO CHANGES NEEDED
- [x] **Menu.lua** — Context menus, independent of theme
- [x] **MinimapButton.lua** — Independent
- [x] **AddonCompartment.lua** — Independent
- [x] **Hyperlink.lua** — Independent
- [x] **Report.lua** — Independent
- [x] **Slash.lua** — Independent

### 🎯 Testing Checklist (in-game)
- [ ] ButtonFrameTemplate renders correctly with bug portrait
- [ ] PanelTabs switch between Errors/Monitor/Log
- [ ] Splitter drag works (Errors mode left/right split)
- [ ] Search filters GroupGrid rows
- [ ] Status bar buttons functional (Export, Ignore Sig, Ignore Addon, Clear All)
- [ ] DetailView sub-tabs switch content (Message/Stack/Locals/Doctor/Occur)
- [ ] DetailView action buttons work (Copy, Ignore Sig, Ignore Addon)
- [ ] ExportFrame opens as proper Blizzard dialog with portrait
- [ ] GroupGrid row selection/colors readable on Blizzard Inset bg
- [ ] GroupGrid zebra stripes visible
- [ ] GroupGrid column resize handles work
- [ ] Monitor embedded panels display CPU/Mem/Alerts/Bus stats
- [ ] Monitor splitter between CPU and Mem panels works
- [ ] Frame state persistence (position, size saved/restored on reload)
- [ ] Split ratio persistence (pane states saved)
- [ ] No Lua errors on load
- [ ] No taint issues in combat
- [ ] Resize grip works (bottom-right corner)
- [ ] Close button (X) properly hides window via UI:Toggle()
- [ ] Tab badge shows error count on Errors tab
- [ ] Double-click on GroupGrid row opens export

### 📝 Notes
- Bug portrait: `Interface\AddOns\!RothDevLib\Media\bug` (TGA file must exist)
- PanelTemplates tabs use CharacterFrameTabButtonTemplate (retail) or PanelTabButtonTemplate (fallback)
- Compact status line format: "ErrorHandler: owned|not owned +fallback_chain +N new"
- All Skin.C colors maintained for backward compat even though main window is now Blizzard-native
