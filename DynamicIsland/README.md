<p align="center">
  <img src="Screenshots/icon.png" width="128" alt="Dynamic Island app icon">
</p>

<h1 align="center">Dynamic Island for Mac</h1>

<p align="center">
  A native Dynamic Island that grows out of your MacBook's notch.<br>
  Now Playing from any app, sound, brightness and Apple Home, animated with real SwiftUI springs.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-native-0A84FF" alt="SwiftUI">
  <a href="../LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center">
  <img src="Screenshots/hero.png" alt="The island open under the menu bar, playing a song">
</p>

## Highlights

- **Now Playing from any app.** Music, Spotify, Podcasts, Safari, Chrome and anything else that reports to Control Center. Artwork, title, artist, scrubbing, play/pause and skip.
- **Live activities.** While music plays, the artwork and an equalizer tinted by the album art sit on either side of the notch. A new song gets a short peek.
- **Sound and display.** Volume, mute, brightness and a one-click audio output switcher for speakers, AirPods and AirPlay, like Control Center.
- **HUDs in the notch.** Volume, brightness and output changes appear in the island. It can also replace the system's volume and brightness overlay.
- **Apple Home.** Tap tiles to run your Home scenes and accessories through Shortcuts.
- **Acord Hub.** Tasks, meetings, approvals and scheduled posts from Acord Hub in their own tab, alerts in the notch when something needs you, a countdown to your next meeting, and a quick way to add tasks.
- **Tray.** Drop files, images, links or text on the notch; drag them out again into any app.
- **Temperature and battery.** CPU, GPU, battery and SSD temperatures with a short history, battery level and time left, a warning when the Mac runs hot, and an optional live activity beside the notch.
- **Updates itself.** Checks GitHub every couple of minutes, builds the new version on the Mac and relaunches.
- **Posture companion.** With the [Posture](../Hallning) app running, the island shows your posture and nudges you when you slouch.
- **Feels like a Mac.** Spring animations, blur-and-scale transitions, rubber-band sliders, SF Symbols and trackpad haptics. It never steals focus from the app you're using.

## Gallery

| | |
|:---:|:---:|
| <img src="Screenshots/live-activity.png" alt="Live activity with artwork and equalizer"><br>**Live activity** while music plays | <img src="Screenshots/track-change.png" alt="Track change peek"><br>**Track change** peek |
| <img src="Screenshots/volume-hud.png" alt="Volume HUD"><br>**Volume** HUD in the notch | <img src="Screenshots/output-device.png" alt="Audio output changed"><br>**Audio output** changed |
| <img src="Screenshots/sound-and-display.png" alt="Sound and display controls"><br>**Sound and display** controls | <img src="Screenshots/home.png" alt="Home tiles"><br>**Home** scenes and accessories |
| <img src="Screenshots/posture.png" alt="Posture tab"><br>**Posture** tab | <img src="Screenshots/posture-reminder.png" alt="Posture reminder"><br>**Posture** reminder |

## Requirements

- A Mac with Apple silicon. It's designed for MacBooks with a notch. Other displays get a virtual notch at the top center (untested).
- macOS 14 Sonoma or later. Developed and tested on macOS 26 Tahoe.
- Xcode 16 or later, or just the Command Line Tools (`xcode-select --install`).

## Install

There's no prebuilt download yet. Building from source takes a minute or two:

```bash
git clone https://github.com/Emsurenar/mac-appar.git
cd mac-appar/DynamicIsland
./build.sh --run
```

This builds `build/Dynamic Island.app` and launches it. Move it to `/Applications` if you want to keep it, then turn on **Launch at login** in its settings.

The script signs the app with the first code-signing identity in your keychain, or ad hoc if there is none. A stable identity keeps the Accessibility permission across rebuilds. Choose one with `SIGN_IDENTITY="Your Identity" ./build.sh`.

## Using it

- **Hover** over the notch to open the island. Move the pointer away to close it. If you prefer clicking, turn off hover in settings.
- **Tabs** in the top-left corner switch between Now Playing, Home, Sound and display, and Posture.
- **Click the artwork** to bring the playing app to the front. Click the output icon to jump to the output picker.
- **Right-click** the island, or use the gear, for **Settings** and **Quit**. The app has no Dock icon.

### Apple Home

Native Mac apps can't use HomeKit. It's only available to Mac Catalyst apps with a paid developer entitlement. So the island runs your **Shortcuts** instead:

1. In **Shortcuts**, create a folder named **Home**. You can pick another name in settings.
2. Add shortcuts that use the **Control Home** action, for example *Living Room Lights On* or a *Good Night* scene.
3. They appear as tiles in the Home tab. A leading emoji becomes the tile's icon. Otherwise an SF Symbol is picked from the name: light, lamp, lock, door, heat, fan, blinds, TV, night, morning and more, in English or Swedish.
4. To make a tile show **On/Off**, end the shortcut by outputting the text `on` or `off`.

<img src="Screenshots/home-setup.png" width="480" alt="Home tab before any shortcuts exist">

### Acord Hub

The Hub tab reads Acord Hub through its MCP server, the same tools Claude uses, so the Hub needs no extra API.

1. Open **Settings → Acord Hub** and enter the MCP server address (for example `https://hub.acordmedia.com/api/mcp`) and your token. The token is stored in the keychain.
2. Click **Test Connection**, then choose yourself under **You are** so the island knows which tasks are yours.
3. The tab shows **Tasks**, **Calendar**, **Approvals**, **Content** and **Notifications**. Turn sections on or off, reorder them, and filter tasks by assignee, status, priority and due date.
4. Click **+** to add a task (title, due date, project, assignee). Click a row or **↗** to open the Hub in the browser; set the paths under **Advanced**.

**Notifications.** The Hub has no notification feed, so the island compares each refresh with the last: new tasks for you, tasks due or overdue, meetings and posts about to start, and approvals that are requested or answered. Each item notifies once. Alerts drop out of the notch; you can add a sound, keep them to work hours or turn on Do Not Disturb.

**Live activity.** While the island is closed it can show the next meeting or post with a countdown, the time left of a meeting in progress, or the number of overdue tasks. Meetings can take priority over music.

**Working on tasks.** Today's (and overdue) tasks show as cards styled like the Hub, coloured by priority. Tick the circle to finish one (with undo), click it to open its description and checklist, change status, due date and priority, edit it or delete it. Right-click for everything.

**Time.** ▶ on a card starts the Hub's own timer – the same one as in Att göra – and the notch shows it while it runs; pause, resume, stop and log, or stop and mark done. The clock icon logs time without a timer (15 min to 2 h, or any amount like `1:30` with a note). Today's logged total sits in the toolbar.

**Google Calendar.** Meetings come through the Hub: connect Google there once (the Calendar section has a **Connect** button) and they show in the calendar, the countdown and reminders; **Join** opens the Meet link near the start.

The Hub side of this lives in `acord-hub` (`lib/mcp/`): the timer, time, meetings and `dashboard_snapshot` tools.

### Tray

Drag files, images, links or text onto the notch – the island opens on the tray and keeps a copy. Drag them out into any app; double-click opens, right-click shows them in Finder. Settings can empty the tray automatically after a day, a week or a month.

### Temperature and battery

Sound and display shows the CPU temperature with a short graph, GPU, battery and SSD temperatures, and the battery level. Turn on **Show temperature and battery beside the notch** to see them on either side of the camera when nothing else is there, and pick when the island should warn that the Mac runs hot.

### Updates

The app compares the commit it was built from with this repository's `main` branch every couple of minutes and after waking, and updates itself while the island is closed. **Settings → General → Updates** has Check Now and the log. Builds are signed with a local certificate created once, so the Accessibility permission survives updates.

### Replacing the system volume HUD

Turn on **Replace the system volume and brightness HUD** in settings and grant **Accessibility** access when asked. The volume and brightness keys then show only in the island. Hold <kbd>⌥</kbd><kbd>⇧</kbd> for quarter steps, like on macOS.

### Posture

[Posture](../Hallning) is a companion menu bar app in this repository. While it runs, the island gets a Posture tab with today's score, the neck angle from AirPods, and buttons to pause or check now. When you've slouched for a while, a reminder appears in the notch instead of as a notification.

## Permissions and privacy

| Permission | Used for | Required |
|---|---|:---:|
| Accessibility | Replacing the system volume and brightness HUD | Optional |
| Keychain | Storing the Acord Hub token | Only with Acord Hub |

Everything else, like Now Playing, volume, outputs and brightness, works without any prompts. Shortcuts may ask for access to Home the first time a Home shortcut runs.

Network traffic goes to the Acord Hub server you configure (once you've added a token) and to GitHub to check for updates. There are no analytics. Everything else stays on your Mac.

## How it works

<details>
<summary><b>The notch window</b></summary>

The island is a borderless, transparent `NSPanel` placed above the menu bar on every Space, including over full-screen apps. It's non-activating, so it never takes focus. `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` give the exact notch rectangle, and a black shape of that size sits over the hardware cutout, where it's invisible. When the shape grows, it looks like the notch itself expands.

The panel is much larger than the island, so it lets clicks through (`ignoresMouseEvents`) unless the pointer is inside the island's hover zone. A global mouse monitor follows the pointer. Watching mouse movement needs no permission. Short delays (90 ms to open, 220 ms to close) keep it from flickering when the pointer brushes past.
</details>

<details>
<summary><b>Shape and motion</b></summary>

`NotchShape` is an animatable SwiftUI `Shape` with concave "ears" where it meets the top of the screen and rounded bottom corners. Both radii animate together with the size, so the outline morphs between states instead of cross-fading. Every state has its own spring: a slight bounce when opening and a calm, critically damped close. Content enters with a blur and scale from the notch, and the artwork moves between states with `matchedGeometryEffect`.

A single computed property, `IslandModel.presentation`, decides what the island shows by picking the most important state: open, HUD, posture reminder, track peek, music live activity, posture live activity, and finally closed.
</details>

<details>
<summary><b>Now Playing</b></summary>

The system-wide Now Playing state lives in Apple's private **MediaRemote** framework. Since macOS 15.4, MediaRemote only answers processes signed by Apple. To get around that, `Bridge/NowPlayingBridge.m` is compiled into a small dynamic library that is loaded into `/usr/bin/perl`, an Apple-signed binary, through Perl's `DynaLoader`. The bridge talks to the app over stdio. It writes one JSON line per change (artwork as base64, only when it changes) and reads commands like `toggle`, `next` and `seek 42.5`. It exits when the app quits.

This technique was pioneered by [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter).
</details>

<details>
<summary><b>Sound, brightness and keys</b></summary>

- **Core Audio** provides output devices, volume and mute as properties. The app subscribes to them with property listeners, so external changes, like the keyboard, show up instantly without polling. Switching outputs sets the system's default output device.
- **Brightness** uses the private `DisplayServices` framework to read and set the built-in display's brightness.
- **Replacing the HUD** uses a `CGEventTap` for `NX_SYSDEFINED` media-key events. The tap handles volume and brightness keys itself and swallows them before the system shows its overlay.
- **Haptics** use `NSHapticFeedbackManager`. They fire on the pointer movement that reaches the notch, and when a slider hits its end, because the trackpad only plays them while a finger is on it.
</details>

<details>
<summary><b>Home and Posture</b></summary>

- **Home** shells out to `/usr/bin/shortcuts`. It lists the shortcuts in the chosen folder and runs one with `--output-path`, so the shortcut's output can set the tile's on/off state.
- **Posture** talks to the companion app over `DistributedNotificationCenter`. Posture broadcasts its state and reminders. The island says hello, so Posture shows reminders in the notch instead of as notifications, and sends button presses back as commands.
</details>

## Project structure

```
DynamicIsland/
├── build.sh                    # Builds, bundles and signs the .app
├── Package.swift
├── Bridge/NowPlayingBridge.m   # MediaRemote bridge, runs inside /usr/bin/perl
├── Resources/                  # Info.plist, app icon
├── Scripts/make-icon.swift     # Draws AppIcon.icns
└── Sources/DynamicIsland/
    ├── App/                    # Entry point and app delegate
    ├── Island/                 # Window, notch geometry, state model
    ├── Services/               # Now Playing, audio, brightness, keys, Home, Posture, Acord Hub
    ├── Settings/               # Preferences and settings window
    ├── Views/                  # Island shape, live activities, tabs, components
    └── Debug/                  # Snapshot renderer (debug builds only)
```

## Development

```bash
CONFIG=debug ./build.sh            # debug build
"build/Dynamic Island.app/Contents/MacOS/DynamicIsland" --snapshots /tmp/island   # render every state to PNG
"build/Dynamic Island.app/Contents/MacOS/DynamicIsland" --trace    # log every state change
swift Scripts/make-icon.swift .    # redraw the app icon
```

The screenshots in this README come from `--snapshots`.

## Known limitations

- The app uses private frameworks (MediaRemote, DisplayServices), so it can't be sandboxed or ship on the App Store, and a macOS update could break those parts.
- A Home tile's on/off state reflects the last time the island ran that shortcut, not changes made elsewhere.
- Trackpad haptics need a Force Touch trackpad and a finger on it.
- The interface is in English only.

## Acknowledgements

Inspired by the iPhone's Dynamic Island and by Mac notch apps like [NotchNook](https://lo.cafe/notchnook), [Alcove](https://tryalcove.com) and [boring.notch](https://github.com/TheBoredTeam/boring.notch). Thanks to [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) for showing the way around the MediaRemote restrictions.

## License

[MIT](../LICENSE)

*Not affiliated with Apple. Dynamic Island, Mac and HomeKit are trademarks of Apple Inc.*
