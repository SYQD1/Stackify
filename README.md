# Stackify

A single-file PowerShell + WPF tool for Windows: install 230+ apps via WinGet or
Chocolatey, apply system tweaks, and manage Windows Update, all from one script
(`irm | iex` supported). No installer, no dependencies beyond what Windows
already ships with, nothing left behind.

Inspired by [Chris Titus Tech's WinUtil](https://github.com/ChrisTitusTech/winutil),
with its own curated app catalog, tweak set, and UI.

## Quick start

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/SYQD1/Stackify/main/Stackify.ps1 | iex
```

You'll get one UAC prompt (Stackify needs admin rights to install apps and change
system settings), then the app window opens. Nothing is installed on your system
beyond what you explicitly choose in the app itself.

Prefer to download it first and look before running? Grab
[`Stackify.ps1`](Stackify.ps1) from this repo and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Stackify.ps1
```

Either way it self-elevates automatically — you never need to manually open an
admin PowerShell window first.

## What it does

**Install** — a searchable, categorized catalog of apps (Browsers, Communications,
Development, Document, Games, Microsoft Tools, Multimedia Tools, Pro Tools,
Selfhosted Tools, Utilities). Multi-select and install, uninstall, or upgrade
everything at once, via either WinGet or Chocolatey. Installs run silently in the
background with a progress bar — no installer wizards popping up.

**Tweaks** — a curated set of Windows tweaks (Essential, Customize Preferences,
Performance Plans, and an Advanced/CAUTION section for the riskier ones), each
appliable and reversible. Comes with quick presets (Standard/Minimal/Advanced),
a "Get Installed Tweaks" scanner that shows you what's already applied on your
machine, and a companion AppX bloatware remover.

**Updates** — three one-click Windows Update profiles (Recommended, Windows
Default, Disable Updates), plus a manual check-and-install using Windows' own
Update Agent, no extra modules required.

## Requirements

- Windows 10 or 11
- PowerShell 5.1+ (included with Windows)
- [WinGet](https://apps.microsoft.com/detail/9nblggh4nns1) for installs (already
  present on most recent Windows installs); Chocolatey is optional if you'd
  rather use that instead

## Safety notes

- Stackify needs administrator rights to install software and change system
  settings — that's what the UAC prompt is for.
- The Advanced/CAUTION tweaks section exists because some of those tweaks are
  more aggressive (removing built-in apps, disabling services) — read what a
  tweak does before applying it, and use Undo if something doesn't feel right.
- The "Disable Updates" profile stops Windows from receiving security updates
  while active. Only use it if you know why you need it.

## Credits

The app and tweak catalogs are sourced from the public config of
[ChrisTitusTech/winutil](https://github.com/ChrisTitusTech/winutil) (MIT-licensed),
trimmed and extended for Stackify.
