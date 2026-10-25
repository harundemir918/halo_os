# Design files

- `screens/` : PNG exports of every screen. Put them here (see below).
- `source/` : the original `.dc.html` sources. Each file is one screen. All colors, sizes, fonts, and copy are written as inline styles, so values can be read directly. The files need the design canvas runtime to render in a browser, so use the PNGs for visual checks and these files for exact numbers.

Screen files:

| File | Screen | Size |
|---|---|---|
| `Main.dc.html` | Lock | 390 x 844 |
| `Home.dc.html` | Home Arc | 390 x 844 |
| `Switcher.dc.html` | Recents (slats) | 390 x 844 |
| `Control.dc.html` | Switchboard | 390 x 844 |
| `Notifications.dc.html` | Stream | 390 x 844 |
| `Settings.dc.html` | System | 390 x 844 |
| `Language.dc.html` | Design language sheet | 1280 x 520 |

Export names to use for the PNGs: `lock.png`, `home.png`, `recents.png`, `switchboard.png`, `stream.png`, `system.png`, `language.png`.
