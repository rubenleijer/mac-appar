<h1 align="center">mac-appar · Acord edition</h1>

<p align="center">
  Two native macOS apps written in Swift and SwiftUI.<br>
  No Xcode project: each app is a Swift package with a one-line build script.
</p>

<p align="center">
  <a href="https://github.com/Emsurenar/mac-appar/actions/workflows/build.yml"><img src="https://github.com/Emsurenar/mac-appar/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/platform-macOS-black?logo=apple" alt="macOS">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center">
  <img src="DynamicIsland/Screenshots/hero.png" alt="Dynamic Island open under the menu bar">
</p>

## Acord edition – install

This fork is the **Acord Media** version of Dynamic Island: everything in the original plus Acord Hub (tasks, timer and time logging, calendar and Google meetings, approvals, posts), a file tray, temperature and battery, and automatic updates.

**Install on a new Mac** (Apple silicon, macOS 14+):

1. Download [`Install Dynamic Island.command`](https://raw.githubusercontent.com/rubenleijer/mac-appar/main/DynamicIsland/Install%20Dynamic%20Island.command) (right-click → Save Link As…), or run this in Terminal:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/rubenleijer/mac-appar/main/DynamicIsland/Scripts/update.sh | bash
   ```
2. If you downloaded the file: right-click it → **Open** (the first time macOS asks because it's from the internet). It builds the app, installs it in Applications and starts it – a couple of minutes.
3. Open the island's **Settings** (right-click the notch) → **Acord Hub**: the MCP server is `https://hub.acordmedia.com/api/mcp`. Ask Ruben for the MCP token, then **Test Connection** and pick yourself under **You are**.
4. Optional: **General** → turn on **Replace the system volume and brightness HUD** and allow Accessibility when asked.

From then on the app checks this repository every couple of minutes and updates itself – everyone stays on the same version.

→ [Everything the Acord edition does](DynamicIsland/README.md#acord-hub)

## The apps

### [Dynamic Island](DynamicIsland)

A Dynamic Island that grows out of your MacBook's notch. It shows Now Playing from any app with artwork and controls, and lets you set volume, brightness and audio output, including AirPods and AirPlay. It shows volume and output changes as HUDs in the notch, and runs your Apple Home scenes through Shortcuts. The animations use the same springs as the iPhone.

→ [Read more](DynamicIsland/README.md)

### [Posture](Hallning)

A menu bar app that keeps an eye on how you sit. Every 10 seconds it reads your shoulders, head and face from the camera with Apple's Vision framework, and AirPods can add your neck angle. It learns your own good and bad postures from a short calibration and reminds you, with concrete advice, when you've been slouching for a while. With Dynamic Island running, the reminders appear in the notch.

→ [Read more](Hallning/README.md)

<p align="center">
  <img src="DynamicIsland/Screenshots/posture.png" width="640" alt="Posture shown in the Dynamic Island">
</p>

## Requirements

| | Dynamic Island | Posture |
|---|---|---|
| macOS | 14 Sonoma or later | 26 Tahoe or later |
| Mac | Apple silicon. Designed for MacBooks with a notch | Apple silicon with a camera |
| Tools | Xcode 16+ or the Command Line Tools | Xcode 26+ or the Command Line Tools |

## Build and run

```bash
git clone https://github.com/Emsurenar/mac-appar.git
cd mac-appar

# Dynamic Island
DynamicIsland/build.sh --run

# Posture
Hallning/build.sh --run
```

Each script builds a release binary with Swift Package Manager, wraps it in an `.app` bundle in the app's `build/` folder, signs it and, with `--run`, launches it. Both apps live in the menu bar area and have no Dock icon.

## How the two apps work together

The apps are independent, and each one works on its own. When both run, they talk over `DistributedNotificationCenter`:

- Posture broadcasts its state after every check, and its reminders.
- Dynamic Island announces itself. Posture then sends reminders to the notch instead of as notifications, and the island sends button presses (pause, check now) back.

## Repository layout

```
mac-appar/
├── DynamicIsland/   # The notch app (Swift package, build script, screenshots)
├── Hallning/        # The Posture app (Swift package, build script)
└── .github/         # CI: builds both apps on macOS 26
```

## Contributing

Issues and pull requests are welcome. Please keep changes in the style of the surrounding code and make sure both apps still build:

```bash
(cd DynamicIsland && swift build) && (cd Hallning && swift build)
```

## License

[MIT](LICENSE) © 2026 Emre Sunar

*Not affiliated with Apple. Dynamic Island, Mac and AirPods are trademarks of Apple Inc.*
