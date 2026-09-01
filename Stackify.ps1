#Requires -Version 5.1
<#
    Stackify - a single-file Windows setup utility.
    Install apps (winget), apply system tweaks, and run Windows Update -
    all from one PowerShell script. No installation, no dependencies
    beyond what's already on Windows.

    Run it:  right-click -> Run with PowerShell   (it will self-elevate)
    Or:      powershell -ExecutionPolicy Bypass -File .\Stackify.ps1
#>

# ---------------------------------------------------------------------------
# Self-elevate to Administrator
#
# Two launch modes need two different re-invocations: running Stackify.ps1 as a
# real file (double-click / -File) has a $PSCommandPath to relaunch with
# -File; running it via `irm <url> | iex` has none (there is no file on
# disk - it exists only as piped text), so that path is detected and
# re-launched by re-running the same one-liner in an elevated process
# instead. Update $StackifySourceUrl below once Stackify is hosted somewhere (see
# README.md's "Set up irm | iex hosting" section) so the iex-relaunch path
# knows what URL to re-fetch.
# ---------------------------------------------------------------------------
$script:StackifySourceUrl = 'https://raw.githubusercontent.com/SYQD1/Stackify/main/Stackify.ps1'

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($PSCommandPath) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$PSCommandPath`""
        )
    } else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command",
            "irm $script:StackifySourceUrl | iex"
        )
    }
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# Hide our own console window - the GUI is the only window the user should see.
Add-Type -Name Win32 -Namespace ConsoleHide -MemberDefinition @'
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
'@
$hwnd = [ConsoleHide.Win32]::GetConsoleWindow()
if ($hwnd -ne [IntPtr]::Zero) { [ConsoleHide.Win32]::ShowWindow($hwnd, 0) | Out-Null } # SW_HIDE
# Hiding the console this way leaves Windows' "next window" default show
# state stuck on hidden/minimized - the WPF window below would otherwise
# open off-screen (position -32000,-32000) even though nothing ever calls
# Minimize on it. Forcing it to SW_SHOWNORMAL + foreground once its native
# handle exists (SourceInitialized, before ShowDialog paints anything)
# overrides that inherited state.

try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}

# ---------------------------------------------------------------------------
# Embedded data - the curated app catalog and tweak catalog (sourced from
# the winutil project's public config, trimmed to the fields Stackify uses).
# ---------------------------------------------------------------------------
$AppsJson = @'
{"1password":{"name":"1Password","desc":"1Password is a password manager that allows you to store and manage your passwords securely.","cat":"Utilities","winget":"AgileBits.1Password","choco":"1password","link":"https://1password.com/"},"7zip":{"name":"7-Zip","desc":"7-Zip is a free and open-source file archiver utility. It supports several compression formats and provides a high compression ratio, making it a popular choice for file compression.","cat":"Utilities","winget":"7zip.7zip","choco":"7zip","link":"https://www.7-zip.org/"},"adobe":{"name":"Adobe Acrobat Reader","desc":"Adobe Acrobat Reader is a free PDF viewer with essential features for viewing, printing, and annotating PDF documents.","cat":"Document","winget":"Adobe.Acrobat.Reader.64-bit","choco":"adobereader","link":"https://www.adobe.com/acrobat/pdf-reader.html"},"advancedip":{"name":"Advanced IP Scanner","desc":"Advanced IP Scanner is a fast and easy-to-use network scanner. It is designed to analyze LAN networks and provides information about connected devices.","cat":"Pro Tools","winget":"Famatech.AdvancedIPScanner","choco":"advanced-ip-scanner","link":"https://www.advanced-ip-scanner.com/"},"aimp":{"name":"AIMP (Music Player)","desc":"AIMP is a feature-rich music player with support for various audio formats, playlists, and customizable user interface.","cat":"Multimedia Tools","winget":"AIMP.AIMP","choco":"aimp","link":"https://www.aimp.ru/"},"angryipscanner":{"name":"Angry IP Scanner","desc":"Angry IP Scanner is an open-source and cross-platform network scanner. It is used to scan IP addresses and ports, providing information about network connectivity.","cat":"Pro Tools","winget":"angryziber.AngryIPScanner","choco":"angryip","link":"https://angryip.org/"},"anydesk":{"name":"AnyDesk","desc":"AnyDesk is a remote desktop software that enables users to access and control computers remotely. It is known for its fast connection and low latency.","cat":"Utilities","winget":"AnyDesk.AnyDesk","choco":"anydesk","link":"https://anydesk.com/"},"audacity":{"name":"Audacity","desc":"Audacity is a free and open-source audio editing software known for its powerful recording and editing capabilities.","cat":"Multimedia Tools","winget":"Audacity.Audacity","choco":"audacity","link":"https://www.audacityteam.org/"},"autoruns":{"name":"Autoruns","desc":"This utility shows you what programs are configured to run during system bootup or login.","cat":"Microsoft Tools","winget":"Microsoft.Sysinternals.Autoruns","choco":"autoruns","link":"https://learn.microsoft.com/en-us/sysinternals/downloads/autoruns"},"rdcman":{"name":"RDCMan","desc":"RDCMan manages multiple remote desktop connections. It is useful for managing server labs where you need regular access to each machine such as automated checkin systems and data centers.","cat":"Microsoft Tools","winget":"Microsoft.Sysinternals.RDCMan","choco":"rdcman","link":"https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman"},"autohotkey":{"name":"AutoHotkey","desc":"AutoHotkey is a scripting language for Windows that allows users to create custom automation scripts and macros. It is often used for automating repetitive tasks and customizing keyboard shortcuts.","cat":"Utilities","winget":"AutoHotkey.AutoHotkey","choco":"autohotkey","link":"https://www.autohotkey.com/"},"battlenet":{"name":"Battle.net","desc":"Battle.net is a launcher for games created and developed by Activision Blizzard","cat":"Games","winget":"Blizzard.BattleNet","choco":"na","link":"https://battle.net"},"bitwarden":{"name":"Bitwarden","desc":"Bitwarden is an open-source password management solution. It allows users to store and manage their passwords in a secure and encrypted vault, accessible across multiple devices.","cat":"Utilities","winget":"Bitwarden.Bitwarden","choco":"bitwarden","link":"https://bitwarden.com/"},"blender":{"name":"Blender (3D Graphics)","desc":"Blender is a powerful open-source 3D creation suite, offering modeling, sculpting, animation, and rendering tools.","cat":"Multimedia Tools","winget":"BlenderFoundation.Blender","choco":"blender","link":"https://www.blender.org/"},"brave":{"name":"Brave","desc":"Brave is a privacy-focused web browser that blocks ads and trackers, offering a faster and safer browsing experience.","cat":"Browsers","winget":"Brave.Brave","choco":"brave","link":"https://www.brave.com"},"bruno":{"name":"Bruno","desc":"Bruno is a local-first API client that stores collections as plain text files for version control and collaboration.","cat":"Development","winget":"Bruno.Bruno","choco":"bruno","link":"https://www.usebruno.com/"},"bulkcrapuninstaller":{"name":"Bulk Crap Uninstaller","desc":"Bulk Crap Uninstaller is a free and open-source uninstaller utility for Windows. It helps users remove unwanted programs and clean up their system by uninstalling multiple applications at once.","cat":"Utilities","winget":"Klocman.BulkCrapUninstaller","choco":"bulk-crap-uninstaller","link":"https://www.bcuninstaller.com/"},"blurautoclicker":{"name":"BlurAutoClicker","desc":"An Auto-clicker with a few advanced features and generally better performance than popular alternatives.","cat":"Utilities","winget":"Blur009.BlurAutoClicker","choco":"na","link":"https://blur009.vercel.app/projects/blur-autoclicker/"},"calibre":{"name":"Calibre","desc":"Calibre is a powerful and easy-to-use e-book manager, viewer, and converter.","cat":"Multimedia Tools","winget":"calibre.calibre","choco":"calibre","link":"https://calibre-ebook.com/"},"cemu":{"name":"Cemu","desc":"Cemu is a highly experimental software to emulate Wii U applications on PC.","cat":"Games","winget":"Cemu.Cemu","choco":"cemu","link":"https://cemu.info/"},"chatgpt":{"name":"ChatGPT Desktop","desc":"The official ChatGPT desktop app for Windows, distributed through the Microsoft Store.","cat":"Development","winget":"msstore:9NT1R1C2HH7J","choco":"na","link":"https://openai.com/chatgpt/download/"},"chatterino":{"name":"Chatterino","desc":"Chatterino is a chat client for Twitch chat that offers a clean and customizable interface for a better streaming experience.","cat":"Communications","winget":"ChatterinoTeam.Chatterino","choco":"chatterino","link":"https://www.chatterino.com/"},"chrome":{"name":"Chrome","desc":"Google Chrome is a widely used web browser known for its speed, simplicity, and seamless integration with Google services.","cat":"Browsers","winget":"Google.Chrome","choco":"googlechrome","link":"https://www.google.com/chrome/"},"chromium":{"name":"Chromium","desc":"Chromium is the open-source project that serves as the foundation for various web browsers, including Chrome.","cat":"Browsers","winget":"Hibbiki.Chromium","choco":"chromium","link":"https://www.chromium.org/"},"cinebenchr23":{"name":"Cinebench R23","desc":"Cinebench R23 is a benchmark tool for comparing CPU rendering performance across systems.","cat":"Pro Tools","winget":"Maxon.CinebenchR23","choco":"na","link":"https://www.maxon.net/en/cinebench"},"claude":{"name":"Claude Desktop","desc":"Anthropic's Claude desktop application for focused AI-assisted work and chat.","cat":"Development","winget":"Anthropic.Claude","choco":"claude","link":"https://claude.ai/download"},"claude-code":{"name":"Claude Code","desc":"Anthropic's agentic coding tool for terminal and IDE development workflows.","cat":"Development","winget":"Anthropic.ClaudeCode","choco":"claude-code","link":"https://code.claude.com/"},"cmake":{"name":"CMake","desc":"CMake is an open-source, cross-platform family of tools designed to build, test and package software.","cat":"Development","winget":"Kitware.CMake","choco":"cmake","link":"https://cmake.org/"},"codex":{"name":"Codex","desc":"Codex CLI is an OpenAI coding agent that runs locally in your terminal.","cat":"Development","winget":"OpenAI.Codex","choco":"codex","link":"https://developers.openai.com/codex/cli"},"cpuz":{"name":"CPU-Z","desc":"CPU-Z is a system monitoring and diagnostic tool for Windows. It provides detailed information about the computer's hardware components, including the CPU, memory, and motherboard.","cat":"Pro Tools","winget":"CPUID.CPU-Z","choco":"cpu-z","link":"https://www.cpuid.com/softwares/cpu-z.html"},"crystaldiskinfo":{"name":"Crystal Disk Info","desc":"Crystal Disk Info is a disk health monitoring tool that provides information about the status and performance of hard drives. It helps users anticipate potential issues and monitor drive health.","cat":"Utilities","winget":"CrystalDewWorld.CrystalDiskInfo","choco":"crystaldiskinfo","link":"https://crystalmark.info/en/software/crystaldiskinfo/"},"crystaldiskmark":{"name":"Crystal Disk Mark","desc":"Crystal Disk Mark is a disk benchmarking tool that measures the read and write speeds of storage devices. It helps users assess the performance of their hard drives and SSDs.","cat":"Utilities","winget":"CrystalDewWorld.CrystalDiskMark","choco":"crystaldiskmark","link":"https://crystalmark.info/en/software/crystaldiskmark/"},"cursor":{"name":"Cursor","desc":"AI-powered code editor (VS Code-based) with agentic coding features and integrated AI assistance for development workflows.","cat":"Development","winget":"Anysphere.Cursor","choco":"cursoride","link":"https://cursor.com/"},"ddu":{"name":"Display Driver Uninstaller","desc":"Display Driver Uninstaller (DDU) is a tool for completely uninstalling graphics drivers from NVIDIA, AMD, and Intel. It is useful for troubleshooting graphics driver-related issues.","cat":"Pro Tools","winget":"Wagnardsoft.DisplayDriverUninstaller","choco":"ddu","link":"https://www.wagnardsoft.com/display-driver-uninstaller-DDU-"},"discord":{"name":"Discord","desc":"Discord is a popular communication platform with voice, video, and text chat, designed for gamers but used by a wide range of communities.","cat":"Communications","winget":"Discord.Discord","choco":"discord","link":"https://discord.com/"},"dismtools":{"name":"DISMTools","desc":"DISMTools is a fast, customizable GUI for the DISM utility, supporting Windows images from Windows 7 onward. It handles installations on any drive, offers project support, and lets users tweak settings like color modes, language, and DISM versions; powered by both native DISM and a managed DISM API.","cat":"Microsoft Tools","winget":"CodingWondersSoftware.DISMTools.Stable","choco":"dismtools","link":"https://github.com/CodingWonders/DISMTools"},"ntlite":{"name":"NTLite","desc":"Integrate updates, drivers, automate Windows and application setup, speedup Windows deployment process and have it all set for the next time.","cat":"Microsoft Tools","winget":"Nlitesoft.NTLite","choco":"ntlite-free","link":"https://ntlite.com"},"dorion":{"name":"Dorion","desc":"Tiny alternative Discord client with a smaller footprint, snappier startup, themes, plugins and more!","cat":"Communications","winget":"SpikeHD.Dorion","choco":"dorion","link":"https://spikehd.dev/projects/dorion/"},"dockerdesktop":{"name":"Docker Desktop","desc":"Docker Desktop provides a local environment for building, running, and testing containerized applications on Windows.","cat":"Development","winget":"Docker.DockerDesktop","choco":"docker-desktop","link":"https://www.docker.com/products/docker-desktop/"},"dotnet6":{"name":".NET Desktop Runtime 6","desc":".NET Desktop Runtime 6 is a runtime environment required for running applications developed with .NET 6.","cat":"Microsoft Tools","winget":"Microsoft.DotNet.DesktopRuntime.6","choco":"dotnet-6.0-runtime","link":"https://dotnet.microsoft.com/download/dotnet/6.0"},"dotnet8":{"name":".NET Desktop Runtime 8","desc":".NET Desktop Runtime 8 is a runtime environment required for running applications developed with .NET 8.","cat":"Microsoft Tools","winget":"Microsoft.DotNet.DesktopRuntime.8","choco":"dotnet-8.0-runtime","link":"https://dotnet.microsoft.com/download/dotnet/8.0"},"dotnet9":{"name":".NET Desktop Runtime 9","desc":".NET Desktop Runtime 9 is a runtime environment required for running applications developed with .NET 9.","cat":"Microsoft Tools","winget":"Microsoft.DotNet.DesktopRuntime.9","choco":"dotnet-9.0-runtime","link":"https://dotnet.microsoft.com/download/dotnet/9.0"},"dotnet10":{"name":".NET Desktop Runtime 10","desc":".NET Desktop Runtime 10 is a runtime environment required for running applications developed with .NET 10.","cat":"Microsoft Tools","winget":"Microsoft.DotNet.DesktopRuntime.10","choco":"dotnet-10.0-runtime","link":"https://dotnet.microsoft.com/download/dotnet/10.0"},"dropbox":{"name":"Dropbox","desc":"Dropbox is a cloud storage client for syncing files, sharing content, and keeping documents available across devices.","cat":"Utilities","winget":"Dropbox.Dropbox","choco":"dropbox","link":"https://www.dropbox.com/desktop"},"eaapp":{"name":"EA App","desc":"EA App is a platform for accessing and playing Electronic Arts games.","cat":"Games","winget":"ElectronicArts.EADesktop","choco":"ea-app","link":"https://www.ea.com/ea-app"},"eartrumpet":{"name":"EarTrumpet (Audio)","desc":"EarTrumpet is an audio control app for Windows, providing a simple and intuitive interface for managing sound settings.","cat":"Multimedia Tools","winget":"File-New-Project.EarTrumpet","choco":"eartrumpet","link":"https://eartrumpet.app/"},"edge":{"name":"Edge","desc":"Microsoft Edge is a modern web browser built on Chromium, offering performance, security, and integration with Microsoft services.","cat":"Browsers","winget":"Microsoft.Edge","choco":"microsoft-edge","link":"https://www.microsoft.com/edge"},"es-de":{"name":"EmulationStation Desktop Edition","desc":"EmulationStation Desktop Edition is a frontend for browsing and launching games from your multi-platform game collection.","cat":"Games","winget":"ES-DE.EmulationStation-DE","choco":"","link":"https://es-de.org/"},"enteauth":{"name":"Ente Auth","desc":"Ente Auth is a free, cross-platform, end-to-end encrypted authenticator app.","cat":"Utilities","winget":"ente-io.auth-desktop","choco":"ente-auth","link":"https://ente.io/auth/"},"epicgames":{"name":"Epic Games Launcher","desc":"Epic Games Launcher is the client for accessing and playing games from the Epic Games Store.","cat":"Games","winget":"EpicGames.EpicGamesLauncher","choco":"epicgameslauncher","link":"https://www.epicgames.com/store/en-US/"},"files":{"name":"Files","desc":"Alternative file explorer.","cat":"Utilities","winget":"FilesCommunity.Files","choco":"files","link":"https://files.community"},"firefox":{"name":"Firefox","desc":"Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions.","cat":"Browsers","winget":"Mozilla.Firefox","choco":"firefox","link":"https://www.mozilla.org/en-US/firefox/new/"},"firefoxesr":{"name":"Firefox ESR","desc":"Mozilla Firefox is an open-source web browser known for its customization options, privacy features, and extensions. Firefox ESR (Extended Support Release) receives major updates every 42 weeks with minor updates such as crash fixes, security fixes and policy updates as needed, but at least every four weeks.","cat":"Browsers","winget":"Mozilla.Firefox.ESR","choco":"FirefoxESR","link":"https://www.mozilla.org/en-US/firefox/enterprise/"},"floorp":{"name":"Floorp","desc":"Floorp is an open-source web browser project that aims to provide a simple and fast browsing experience.","cat":"Browsers","winget":"Ablaze.Floorp","choco":"floorp","link":"https://floorp.app/"},"flux":{"name":"F.lux","desc":"f.lux adjusts the color temperature of your screen to reduce eye strain during nighttime use.","cat":"Utilities","winget":"flux.flux","choco":"flux","link":"https://justgetflux.com/"},"foobar":{"name":"foobar2000 (Music Player)","desc":"foobar2000 is a highly customizable and extensible music player for Windows, known for its modular design and advanced features.","cat":"Multimedia Tools","winget":"PeterPawlowski.foobar2000","choco":"foobar2000","link":"https://www.foobar2000.org/"},"fnm":{"name":"Fast Node Manager","desc":"Fast Node Manager (fnm) is a fast, cross-platform tool for installing and switching between Node.js versions.","cat":"Development","winget":"Schniz.fnm","choco":"fnm","link":"https://github.com/Schniz/fnm"},"foxpdfreader":{"name":"Foxit PDF Reader","desc":"Foxit PDF Reader is a free PDF viewer with a familiar ribbon-style interface.","cat":"Document","winget":"Foxit.FoxitReader","choco":"foxitreader","link":"https://www.foxit.com/pdf-reader/"},"geforcenow":{"name":"GeForce NOW","desc":"GeForce NOW is a cloud gaming service that allows you to play high-quality PC games on your device.","cat":"Games","winget":"Nvidia.GeForceNow","choco":"nvidia-geforce-now","link":"https://www.nvidia.com/en-us/geforce-now/"},"gimp":{"name":"GIMP (Image Editor)","desc":"GIMP is a versatile open-source raster graphics editor used for tasks such as photo retouching, image editing, and image composition.","cat":"Multimedia Tools","winget":"GIMP.GIMP.3","choco":"gimp","link":"https://www.gimp.org/"},"git":{"name":"Git","desc":"Git is a distributed version control system widely used for tracking changes in source code during software development.","cat":"Development","winget":"Git.Git","choco":"git","link":"https://git-scm.com/"},"gitextensions":{"name":"Git Extensions","desc":"Git Extensions is a graphical Git client for Windows with repository, history, and commit management tools.","cat":"Development","winget":"GitExtensionsTeam.GitExtensions","choco":"gitextensions","link":"https://gitextensions.github.io/"},"githubcli":{"name":"GitHub CLI","desc":"GitHub CLI brings pull requests, issues, releases, and other GitHub workflows to the terminal.","cat":"Development","winget":"GitHub.cli","choco":"gh","link":"https://cli.github.com/"},"githubdesktop":{"name":"GitHub Desktop","desc":"GitHub Desktop is a visual Git client that simplifies collaboration on GitHub repositories with an easy-to-use interface.","cat":"Development","winget":"GitHub.GitHubDesktop","choco":"git;github-desktop","link":"https://desktop.github.com/"},"gog":{"name":"GOG Galaxy","desc":"GOG Galaxy is a gaming client that offers DRM-free games, additional content, and more.","cat":"Games","winget":"GOG.Galaxy","choco":"goggalaxy","link":"https://www.gog.com/galaxy"},"golang":{"name":"Go","desc":"Go (or Golang) is a statically typed, compiled programming language designed for simplicity, reliability, and efficiency.","cat":"Development","winget":"GoLang.Go","choco":"golang","link":"https://go.dev/"},"googledrive":{"name":"Google Drive","desc":"File syncing across devices all tied to your Google account.","cat":"Utilities","winget":"Google.GoogleDrive","choco":"googledrive","link":"https://www.google.com/drive/"},"gpuz":{"name":"GPU-Z","desc":"GPU-Z provides detailed information about your graphics card and GPU.","cat":"Pro Tools","winget":"TechPowerUp.GPU-Z","choco":"gpu-z","link":"https://www.techpowerup.com/gpuz/"},"gsudo":{"name":"gsudo","desc":"gsudo is a sudo equivalent for Windows. It allows you to run commands with elevated administrative privileges directly within the current console window.","cat":"Pro Tools","winget":"gerardog.gsudo","choco":"gsudo","link":"https://github.com/gerardog/gsudo"},"helium":{"name":"Helium","desc":"Private, fast, and honest web browser.","cat":"Browsers","winget":"ImputNet.Helium","choco":"helium","link":"https://helium.computer"},"hugo":{"name":"Hugo","desc":"The world's fastest framework for building websites.","cat":"Utilities","winget":"Hugo.Hugo.Extended","choco":"hugo-extended","link":"https://gohugo.io"},"handbrake":{"name":"HandBrake","desc":"HandBrake is an open-source video transcoder, allowing you to convert video from nearly any format to a selection of widely supported codecs.","cat":"Multimedia Tools","winget":"HandBrake.HandBrake","choco":"handbrake","link":"https://handbrake.fr/"},"heroiclauncher":{"name":"Heroic Games Launcher","desc":"Heroic Games Launcher is an open-source alternative game launcher for Epic Games Store.","cat":"Games","winget":"HeroicGamesLauncher.HeroicGamesLauncher","choco":"heroic-games-launcher","link":"https://heroicgameslauncher.com/"},"hwinfo":{"name":"HWiNFO","desc":"HWiNFO provides comprehensive hardware information and diagnostics for Windows.","cat":"Pro Tools","winget":"REALiX.HWiNFO","choco":"hwinfo","link":"https://www.hwinfo.com/"},"hwmonitor":{"name":"HWMonitor","desc":"HWMonitor is a hardware monitoring program that reads PC systems main health sensors.","cat":"Pro Tools","winget":"CPUID.HWMonitor","choco":"hwmonitor","link":"https://www.cpuid.com/softwares/hwmonitor.html"},"imageglass":{"name":"ImageGlass (Image Viewer)","desc":"ImageGlass is a versatile image viewer with support for various image formats and a focus on simplicity and speed.","cat":"Multimedia Tools","winget":"DuongDieuPhap.ImageGlass","choco":"imageglass","link":"https://imageglass.org/"},"internetdownloadmanager":{"name":"Internet Download Manager","desc":"Internet Download Manager is a download manager for accelerating, resuming, and scheduling file downloads.","cat":"Utilities","winget":"Tonec.InternetDownloadManager","choco":"internet-download-manager","link":"https://www.internetdownloadmanager.com/"},"irfanview":{"name":"IrfanView","desc":"IrfanView is a lightweight, fast, and free image viewer and editor. Supports multiple formats, batch processing, and powerful plugins.","cat":"Multimedia Tools","winget":"IrfanSkiljan.IrfanView","choco":"irfanview","link":"https://irfanview.com/"},"itch":{"name":"Itch.io","desc":"Itch.io is a digital distribution platform for indie games and creative projects.","cat":"Games","winget":"ItchIo.Itch","choco":"itch","link":"https://itch.io/"},"itunes":{"name":"iTunes","desc":"iTunes is a media player, media library, and online radio broadcaster application developed by Apple Inc.","cat":"Multimedia Tools","winget":"Apple.iTunes","choco":"itunes","link":"https://www.apple.com/itunes/"},"java8":{"name":"Amazon Corretto 8 (LTS)","desc":"Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).","cat":"Development","winget":"Amazon.Corretto.8.JDK","choco":"corretto8jdk","link":"https://aws.amazon.com/corretto"},"java21":{"name":"Amazon Corretto 21 (LTS)","desc":"Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).","cat":"Development","winget":"Amazon.Corretto.21.JDK","choco":"corretto21jdk","link":"https://aws.amazon.com/corretto"},"java25":{"name":"Amazon Corretto 25 (LTS)","desc":"Amazon Corretto is a no-cost, multiplatform, production-ready distribution of the Open Java Development Kit (OpenJDK).","cat":"Development","winget":"Amazon.Corretto.25.JDK","choco":"corretto25jdk","link":"https://aws.amazon.com/corretto"},"jellyfinmediaplayer":{"name":"Jellyfin Media Player","desc":"Jellyfin Media Player is a client application for the Jellyfin media server, providing access to your media library.","cat":"Selfhosted Tools","winget":"Jellyfin.JellyfinMediaPlayer","choco":"jellyfin-media-player","link":"https://jellyfin.org/"},"jellyfinserver":{"name":"Jellyfin Server","desc":"Jellyfin Server is an open-source media server software, allowing you to organize and stream your media library.","cat":"Selfhosted Tools","winget":"Jellyfin.Server","choco":"jellyfin","link":"https://jellyfin.org/"},"jetbrains":{"name":"Jetbrains Toolbox","desc":"Jetbrains Toolbox is a platform for easy installation and management of JetBrains developer tools.","cat":"Development","winget":"JetBrains.Toolbox","choco":"jetbrainstoolbox","link":"https://www.jetbrains.com/toolbox/"},"jpegview":{"name":"JPEG View","desc":"JPEGView is a lean, fast and highly configurable viewer/editor for JPEG, BMP, PNG, WEBP, TGA, GIF, JXL, HEIC, HEIF, AVIF, and TIFF images with a minimal GUI.","cat":"Utilities","winget":"sylikc.JPEGView","choco":"jpegview","link":"https://github.com/sylikc/jpegview"},"joplin":{"name":"Joplin","desc":"Joplin is an open-source note-taking and to-do application with synchronization capabilities.","cat":"Document","winget":"Joplin.Joplin","choco":"joplin","link":"https://joplinapp.org/"},"keepassxc":{"name":"KeePassXC","desc":"KeePassXC is a modern, secure, and open-source password manager that stores and manages your most sensitive information. You can run KeePassXC on Windows, macOS, and Linux systems. KeePassXC is for people with extremely high demands of secure personal data management. It saves many different types of information, such as usernames, passwords, URLs, attachments, and notes in an offline, encrypted file that can be stored in any location, including private and public cloud solutions. For easy identification and management, user-defined titles and icons can be specified for entries. In addition, entries are sorted into customizable groups. An integrated search function allows you to use advanced patterns to easily find any entry in your database. A customizable, fast, and easy-to-use password generator utility allows you to create passwords with any combination of characters or easy to remember passphrases.","cat":"Utilities","winget":"KeePassXCTeam.KeePassXC","choco":"keepassxc","link":"https://keepassxc.org/"},"klite":{"name":"K-Lite Codec Standard","desc":"K-Lite Codec Pack Standard is a collection of audio and video codecs and related tools, providing essential components for media playback.","cat":"Multimedia Tools","winget":"CodecGuide.K-LiteCodecPack.Standard","choco":"k-litecodecpack-standard","link":"https://www.codecguide.com/"},"kodi":{"name":"Kodi Media Center","desc":"Kodi is an open-source media center application that allows you to play and view most videos, music, podcasts, and other digital media files.","cat":"Selfhosted Tools","winget":"XBMCFoundation.Kodi","choco":"kodi","link":"https://kodi.tv/"},"lazygit":{"name":"Lazygit","desc":"Simple terminal UI for git commands.","cat":"Development","winget":"JesseDuffield.lazygit","choco":"lazygit","link":"https://github.com/jesseduffield/lazygit/"},"libreoffice":{"name":"LibreOffice","desc":"LibreOffice is a powerful and free office suite, compatible with other major office suites.","cat":"Document","winget":"TheDocumentFoundation.LibreOffice","choco":"libreoffice-fresh","link":"https://www.libreoffice.org/"},"librewolf":{"name":"LibreWolf","desc":"LibreWolf is a privacy-focused web browser based on Firefox, with additional privacy and security enhancements.","cat":"Browsers","winget":"LibreWolf.LibreWolf","choco":"librewolf","link":"https://librewolf.net/"},"localsend":{"name":"LocalSend","desc":"An open-source cross-platform alternative to AirDrop.","cat":"Selfhosted Tools","winget":"LocalSend.LocalSend","choco":"localsend.install","link":"https://localsend.org/"},"mpc-qt":{"name":"mpc-qt","desc":"Media Player Classic Qute Theater","cat":"Multimedia Tools","winget":"mpc-qt.mpc-qt","choco":"mediainfo","link":"https://mpc-qt.github.io"},"mpv":{"name":"mpv","desc":"mpv is a free, open source, and cross-platform media player supporting a wide variety of media formats, codecs, and subtitle types.","cat":"Multimedia Tools","winget":"shinchiro.mpv","choco":null,"link":"https://mpv.io/"},"matrix":{"name":"Element","desc":"Element is a client for Matrix; an open network for secure, decentralized communication.","cat":"Communications","winget":"Element.Element","choco":"element-desktop","link":"https://element.io/"},"minitoolpartitionwizard":{"name":"MiniTool Partition Wizard","desc":"Comprehensive free partition manager that performs advanced operations Windows natively cannot, such as merging partitions, converting file systems, and organizing disk capacity.","cat":"Utilities","winget":"MiniTool.PartitionWizard.Free","choco":"minitoolpartitionwizard","link":"https://www.partitionwizard.com/"},"modrinth":{"name":"Modrinth App","desc":"Modrinth App is a desktop application for managing Minecraft mods and modpacks.","cat":"Games","winget":"Modrinth.ModrinthApp","choco":"modrinth-app","link":"https://modrinth.com/app"},"moonlight":{"name":"Moonlight/GameStream Client","desc":"Moonlight/GameStream Client allows you to stream PC games to other devices over your local network.","cat":"Selfhosted Tools","winget":"MoonlightGameStreamingProject.Moonlight","choco":"moonlight-qt","link":"https://moonlight-stream.org/"},"mpchc":{"name":"Media Player Classic - Home Cinema","desc":"Media Player Classic - Home Cinema (MPC-HC) is a free and open-source video and audio player for Windows. MPC-HC is based on the original Guliverkli project and contains many additional features and bug fixes.","cat":"Multimedia Tools","winget":"clsid2.mpc-hc","choco":"mpc-hc-clsid2","link":"https://mpc-hc.org/"},"msedgeredirect":{"name":"MSEdgeRedirect","desc":"A Tool to Redirect News, Search, Widgets, Weather, and More to your default browser.","cat":"Utilities","winget":"rcmaehl.MSEdgeRedirect","choco":"msedgeredirect","link":"https://github.com/rcmaehl/MSEdgeRedirect"},"msiafterburner":{"name":"MSI Afterburner","desc":"MSI Afterburner is a graphics card overclocking utility with advanced features.","cat":"Utilities","winget":"Guru3D.Afterburner","choco":"msiafterburner","link":"https://www.msi.com/Landing/afterburner"},"mullvadvpn":{"name":"Mullvad VPN","desc":"This is the VPN client software for the Mullvad VPN service.","cat":"Pro Tools","winget":"MullvadVPN.MullvadVPN","choco":"mullvad-app","link":"https://mullvad.net/"},"mullvadbrowser":{"name":"Mullvad Browser","desc":"Mullvad Browser is a privacy-focused web browser, developed in partnership with the Tor Project.","cat":"Browsers","winget":"MullvadVPN.MullvadBrowser","choco":"na","link":"https://mullvad.net/browser"},"nomacs":{"name":"nomacs","desc":"nomacs is a free, open-source image viewer, which supports multiple platforms. You can use it for viewing all common image formats, including RAW and .psd images.","cat":"Multimedia Tools","winget":"nomacs.nomacs","choco":"nomacs","link":"https://nomacs.org/"},"nanazip":{"name":"NanaZip","desc":"NanaZip is a fast and efficient file compression and decompression tool.","cat":"Utilities","winget":"M2Team.NanaZip","choco":"nanazip","link":"https://nanazip.org"},"netbird":{"name":"NetBird","desc":"NetBird is an open-source alternative comparable to TailScale that can be connected to a self-hosted server.","cat":"Selfhosted Tools","winget":"Netbird.Netbird","choco":"netbird","link":"https://netbird.io/"},"tailscale":{"name":"Tailscale","desc":"The Tailscale client allows you to connect all your devices using WireGuard\u0622\u00ae, without the hassle. Tailscale makes it as easy as installing an app and signing in.","cat":"Utilities","winget":"Tailscale.Tailscale","choco":"tailscale","link":"https://tailscale.com/"},"naps2":{"name":"NAPS2 (Scanner)","desc":"NAPS2 is a document scanning application that simplifies the process of creating electronic documents.","cat":"Document","winget":"Cyanfish.NAPS2","choco":"naps2","link":"https://www.naps2.com/"},"neovim":{"name":"Neovim","desc":"Neovim is a highly extensible text editor and an improvement over the original Vim editor.","cat":"Development","winget":"Neovim.Neovim","choco":"neovim","link":"https://neovim.io/"},"nextclouddesktop":{"name":"Nextcloud Desktop","desc":"Nextcloud Desktop is the official desktop client for the Nextcloud file synchronization and sharing platform.","cat":"Selfhosted Tools","winget":"Nextcloud.NextcloudDesktop","choco":"nextcloud-client","link":"https://nextcloud.com/install/#install-clients"},"nmap":{"name":"Nmap","desc":"Nmap (Network Mapper) is an open-source tool for network exploration and security auditing. It discovers devices on a network and provides information about their ports and services.","cat":"Pro Tools","winget":"Insecure.Nmap","choco":"nmap","link":"https://nmap.org/"},"nodejs":{"name":"NodeJS","desc":"NodeJS is a JavaScript runtime built on Chrome's V8 JavaScript engine for building server-side and networking applications.","cat":"Development","winget":"OpenJS.NodeJS","choco":"nodejs","link":"https://nodejs.org/"},"nodejslts":{"name":"NodeJS LTS","desc":"NodeJS LTS provides Long-Term Support releases for stable and reliable server-side JavaScript development.","cat":"Development","winget":"OpenJS.NodeJS.LTS","choco":"nodejs-lts","link":"https://nodejs.org/"},"pnpm":{"name":"pnpm","desc":"pnpm is a fast and disk space efficient package manager for JavaScript and Node.js applications.","cat":"Development","winget":"pnpm.pnpm","choco":null,"link":"https://pnpm.io/"},"notepadplus":{"name":"Notepad++","desc":"Notepad++ is a free, open-source code editor and Notepad replacement with support for multiple languages.","cat":"Multimedia Tools","winget":"Notepad++.Notepad++","choco":"notepadplusplus","link":"https://notepad-plus-plus.org/"},"nuget":{"name":"NuGet","desc":"NuGet is a package manager for the .NET framework, enabling developers to manage and share libraries in their .NET applications.","cat":"Microsoft Tools","winget":"Microsoft.NuGet","choco":"nuget.commandline","link":"https://www.nuget.org/"},"nvclean":{"name":"NVCleanstall","desc":"NVCleanstall is a tool designed to customize NVIDIA driver installations, allowing advanced users to control more aspects of the installation process.","cat":"Utilities","winget":"TechPowerUp.NVCleanstall","choco":"na","link":"https://www.techpowerup.com/nvcleanstall/"},"obs":{"name":"OBS Studio","desc":"OBS Studio is a free and open-source software for video recording and live streaming. It supports real-time video/audio capturing and mixing, making it popular among content creators.","cat":"Multimedia Tools","winget":"OBSProject.OBSStudio","choco":"obs-studio","link":"https://obsproject.com/"},"obsidian":{"name":"Obsidian","desc":"Obsidian is a powerful note-taking and knowledge management application.","cat":"Document","winget":"Obsidian.Obsidian","choco":"obsidian","link":"https://obsidian.md/"},"okular":{"name":"Okular","desc":"Okular is a versatile document viewer with advanced features.","cat":"Document","winget":"KDE.Okular","choco":"okular","link":"https://okular.kde.org/"},"onedrive":{"name":"OneDrive","desc":"OneDrive is a cloud storage service provided by Microsoft, allowing users to store and share files securely across devices.","cat":"Microsoft Tools","winget":"Microsoft.OneDrive","choco":"onedrive","link":"https://onedrive.live.com/"},"onlyoffice":{"name":"ONLYOFFICE Desktop","desc":"ONLYOFFICE Desktop is a comprehensive office suite for document editing and collaboration.","cat":"Document","winget":"ONLYOFFICE.DesktopEditors","choco":"onlyoffice","link":"https://www.onlyoffice.com/desktop.aspx"},"OPAutoClicker":{"name":"OPAutoClicker","desc":"A full-fledged autoclicker with two modes of autoclicking, at your dynamic cursor location or at a prespecified location.","cat":"Utilities","winget":"OPAutoClicker.OPAutoClicker","choco":"autoclicker","link":"https://www.opautoclicker.com"},"openrgb":{"name":"OpenRGB","desc":"OpenRGB is an open-source RGB lighting control software designed to manage and control RGB lighting for various components and peripherals.","cat":"Utilities","winget":"OpenRGB.OpenRGB","choco":"openrgb","link":"https://openrgb.org/"},"OpenVPN":{"name":"OpenVPN Connect","desc":"OpenVPN Connect is a VPN client that allows you to connect securely to a VPN server. It provides a secure and encrypted connection for protecting your online privacy.","cat":"Pro Tools","winget":"OpenVPNTechnologies.OpenVPNConnect","choco":"openvpn-connect","link":"https://openvpn.net/"},"OVirtualBox":{"name":"Oracle VirtualBox","desc":"Oracle VirtualBox is a powerful and free open-source virtualization tool for x86 and AMD64/Intel64 architectures.","cat":"Utilities","winget":"Oracle.VirtualBox","choco":"virtualbox","link":"https://www.virtualbox.org/"},"policyplus":{"name":"Policy Plus","desc":"Local Group Policy Editor plus more, for all Windows editions.","cat":"Utilities","winget":"Fleex255.PolicyPlus","choco":"na","link":"https://github.com/Fleex255/PolicyPlus"},"processexplorer":{"name":"Process Explorer","desc":"Process Explorer is a task manager and system monitor.","cat":"Microsoft Tools","winget":"Microsoft.Sysinternals.ProcessExplorer","choco":"procexp","link":"https://learn.microsoft.com/sysinternals/downloads/process-explorer"},"Paintdotnet":{"name":"Paint.NET","desc":"Paint.NET is a free image and photo editing software for Windows. It features an intuitive user interface and supports a wide range of powerful editing tools.","cat":"Multimedia Tools","winget":"dotPDN.PaintDotNet","choco":"paint.net","link":"https://www.getpaint.net/"},"parsec":{"name":"Parsec","desc":"Parsec is a low-latency, high-quality remote desktop sharing application for collaborating and gaming across devices.","cat":"Utilities","winget":"Parsec.Parsec","choco":"parsec","link":"https://parsec.app/"},"peazip":{"name":"PeaZip","desc":"PeaZip is a free, open-source file archiver utility that supports multiple archive formats and provides encryption features.","cat":"Utilities","winget":"Giorgiotani.Peazip","choco":"peazip","link":"https://peazip.github.io/"},"pdf-xchange":{"name":"PDF-XChange Editor","desc":"A comprehensive Windows-based software suite and editor for creating, viewing, editing, annotating, and signing PDF files.","cat":"Document","winget":"TrackerSoftware.PDF-XChangeEditor","choco":"pdfxchangeeditor","link":"https://www.pdf-xchange.com/"},"pdf24creator":{"name":"PDF24 Creator","desc":"Free and easy-to-use online/desktop PDF tools that make you more productive","cat":"Document","winget":"geeksoftwareGmbH.PDF24Creator","choco":"pdf24","link":"https://tools.pdf24.org/en/creator"},"pdfgear":{"name":"PDFgear","desc":"PDFgear is a piece of full-featured PDF management software for Windows, macOS, and mobile, and it's completely free to use.","cat":"Document","winget":"PDFgear.PDFgear","choco":"pdfgear","link":"https://www.pdfgear.com/"},"pdfsam":{"name":"PDFsam Basic","desc":"PDFsam Basic is a free and open-source tool for splitting, merging, and rotating PDF files.","cat":"Document","winget":"PDFsam.PDFsam","choco":"pdfsam","link":"https://pdfsam.org/"},"playnite":{"name":"Playnite","desc":"Playnite is an open-source video game library manager with one simple goal: To provide a unified interface for all of your games.","cat":"Games","winget":"Playnite.Playnite","choco":"playnite","link":"https://playnite.link/"},"plex":{"name":"Plex Media Server","desc":"Plex Media Server is a media server software that allows you to organize and stream your media library. It supports various media formats and offers a wide range of features.","cat":"Selfhosted Tools","winget":"Plex.PlexMediaServer","choco":"plexmediaserver","link":"https://www.plex.tv/your-media/"},"plexdesktop":{"name":"Plex Desktop","desc":"Plex Desktop for Windows is the front end for Plex Media Server.","cat":"Selfhosted Tools","winget":"Plex.Plex","choco":"plex","link":"https://www.plex.tv"},"posh":{"name":"Oh My Posh (Prompt)","desc":"Oh My Posh is a cross-platform prompt theme engine for any shell.","cat":"Development","winget":"JanDeDobbeleer.OhMyPosh","choco":"oh-my-posh","link":"https://ohmyposh.dev/"},"postman":{"name":"Postman","desc":"Postman is an API platform and desktop client for designing, testing, documenting, and collaborating on APIs.","cat":"Development","winget":"Postman.Postman","choco":"postman","link":"https://www.postman.com/downloads/"},"powershell":{"name":"PowerShell","desc":"PowerShell is a task automation framework and scripting language designed for system administrators, offering powerful command-line capabilities.","cat":"Microsoft Tools","winget":"Microsoft.PowerShell","choco":"powershell-core","link":"https://github.com/PowerShell/PowerShell"},"powertoys":{"name":"PowerToys","desc":"PowerToys is a set of utilities for power users to enhance productivity, featuring tools like FancyZones, PowerRename, and more.","cat":"Microsoft Tools","winget":"Microsoft.PowerToys","choco":"powertoys","link":"https://github.com/microsoft/PowerToys"},"prismlauncher":{"name":"Prism Launcher","desc":"Prism Launcher is an open-source Minecraft launcher with the ability to manage multiple instances, accounts, and mods.","cat":"Games","winget":"PrismLauncher.PrismLauncher","choco":"prismlauncher","link":"https://prismlauncher.org/"},"processlasso":{"name":"Process Lasso","desc":"Process Lasso is a system optimization and automation tool that improves system responsiveness and stability by adjusting process priorities and CPU affinities.","cat":"Utilities","winget":"BitSum.ProcessLasso","choco":"plasso","link":"https://bitsum.com/"},"protonauth":{"name":"Proton Authenticator","desc":"2FA app from Proton to securely sync and backup 2FA codes.","cat":"Utilities","winget":"Proton.ProtonAuthenticator","choco":"protonauth","link":"https://proton.me/authenticator"},"protonmail":{"name":"Proton Mail","desc":"Proton Mail is an end-to-end encrypted email service by Proton, protecting your privacy with zero-access encryption.","cat":"Communications","winget":"Proton.ProtonMail","choco":"protonmail","link":"https://proton.me/mail"},"protondrive":{"name":"Proton Drive","desc":"Proton Drive is an end-to-end encrypted Swiss vault for your files that protects your data.","cat":"Utilities","winget":"Proton.ProtonDrive","choco":"protondrive","link":"https://proton.me/drive"},"protonpass":{"name":"Proton Pass","desc":"Proton Pass is a cloud-based password manager with end-to-end encryption and unique email aliases.","cat":"Utilities","winget":"Proton.ProtonPass","choco":"protonpass","link":"https://proton.me/pass"},"protonvpn":{"name":"Proton VPN","desc":"Proton VPN is a no-logs VPN service that protects your privacy online with features like Secure Core and Tor over VPN.","cat":"Pro Tools","winget":"Proton.ProtonVPN","choco":"protonvpn","link":"https://protonvpn.com/"},"processmonitor":{"name":"Process Monitor","desc":"SysInternals Process Monitor is an advanced monitoring tool that shows real-time file system, registry, and process/thread activity.","cat":"Microsoft Tools","winget":"Microsoft.Sysinternals.ProcessMonitor","choco":"procexp","link":"https://docs.microsoft.com/en-us/sysinternals/downloads/procmon"},"putty":{"name":"PuTTY","desc":"PuTTY is a free and open-source terminal emulator, serial console, and network file transfer application. It supports various network protocols such as SSH, Telnet, and SCP.","cat":"Pro Tools","winget":"PuTTY.PuTTY","choco":"putty","link":"https://www.chiark.greenend.org.uk/~sgtatham/putty/"},"python3":{"name":"Python3","desc":"Python is a versatile programming language used for web development, data analysis, artificial intelligence, and more.","cat":"Development","winget":"Python.Python.3.14","choco":"python","link":"https://www.python.org/"},"qbittorrent":{"name":"qBittorrent","desc":"qBittorrent is a free and open-source BitTorrent client that aims to provide a feature-rich and lightweight alternative to other torrent clients.","cat":"Utilities","winget":"qBittorrent.qBittorrent","choco":"qbittorrent","link":"https://www.qbittorrent.org/"},"qownnotes":{"name":"QOwnNotes","desc":"QOwnNotes is a free open-source note taking app with Nextcloud/ownCloud integration.","cat":"Document","winget":"pbek.QOwnNotes","choco":"qownnotes","link":"https://www.qownnotes.org/"},"qtox":{"name":"QTox","desc":"QTox is a free and open-source messaging app that prioritizes user privacy and security in its design.","cat":"Communications","winget":"Tox.qTox","choco":"qtox","link":"https://qtox.github.io/"},"revo":{"name":"Revo Uninstaller","desc":"Revo Uninstaller is an advanced uninstaller tool that helps you remove unwanted software and clean up your system.","cat":"Utilities","winget":"RevoUninstaller.RevoUninstaller","choco":"revo-uninstaller","link":"https://www.revouninstaller.com/"},"WiseProgramUninstaller":{"name":"Wise Program Uninstaller (WiseCleaner)","desc":"Wise Program Uninstaller is the perfect solution for uninstalling Windows programs, allowing you to uninstall applications quickly and completely using its simple and user-friendly interface.","cat":"Utilities","winget":"WiseCleaner.WiseProgramUninstaller","choco":"na","link":"https://www.wisecleaner.com/wise-program-uninstaller.html"},"rufus":{"name":"Rufus Imager","desc":"Rufus is a utility that helps format and create bootable USB drives, such as USB keys or pen drives.","cat":"Utilities","winget":"Rufus.Rufus","choco":"rufus","link":"https://rufus.ie/"},"rustlang":{"name":"Rust","desc":"Rust is a programming language designed for safety and performance, particularly focused on systems programming.","cat":"Development","winget":"Rustlang.Rust.MSVC","choco":"rust","link":"https://www.rust-lang.org/"},"sdio":{"name":"Snappy Driver Installer Origin","desc":"Snappy Driver Installer Origin is a free and open-source driver updater with a vast driver database for Windows.","cat":"Utilities","winget":"GlennDelahoy.SnappyDriverInstallerOrigin","choco":"sdio","link":"https://www.glenn.delahoy.com/snappy-driver-installer-origin/"},"sharex":{"name":"ShareX (Screenshots)","desc":"ShareX is a free and open-source screen capture and file sharing tool. It supports various capture methods and offers advanced features for editing and sharing screenshots.","cat":"Multimedia Tools","winget":"ShareX.ShareX","choco":"sharex","link":"https://getsharex.com/"},"nilesoftShell":{"name":"Nilesoft Shell","desc":"Shell is an expanded context menu tool that adds extra functionality and customization options to the Windows context menu.","cat":"Utilities","winget":"Nilesoft.Shell","choco":"nilesoft-shell","link":"https://nilesoft.org/"},"systeminformer":{"name":"System Informer","desc":"A free, powerful, multi-purpose tool that helps you monitor system resources, debug software and detect malware.","cat":"Development","winget":"WinsiderSS.SystemInformer","choco":"systeminformer","link":"https://systeminformer.com/"},"signal":{"name":"Signal","desc":"Signal is a privacy-focused messaging app that offers end-to-end encryption for secure and private communication.","cat":"Communications","winget":"OpenWhisperSystems.Signal","choco":"signal","link":"https://signal.org/"},"signalrgb":{"name":"SignalRGB","desc":"SignalRGB lets you control and sync your favorite RGB devices with one free application.","cat":"Utilities","winget":"WhirlwindFX.SignalRgb","choco":"na","link":"https://www.signalrgb.com/"},"simplenote":{"name":"Simplenote","desc":"Simplenote is an easy way to keep notes, lists, ideas and more.","cat":"Document","winget":"Automattic.Simplenote","choco":"simplenote","link":"https://simplenote.com/"},"simplewall":{"name":"Simplewall","desc":"Simplewall is a free and open-source firewall application for Windows. It allows users to control and manage the inbound and outbound network traffic of applications.","cat":"Pro Tools","winget":"Henry++.simplewall","choco":"simplewall","link":"https://github.com/henrypp/simplewall"},"slack":{"name":"Slack","desc":"Slack is a collaboration hub that connects teams and facilitates communication through channels, messaging, and file sharing.","cat":"Communications","winget":"SlackTechnologies.Slack","choco":"slack","link":"https://slack.com/"},"startallback":{"name":"StartAllBack","desc":"StartAllBack restores and improves Windows taskbar, Start menu, File Explorer, and shell UI behavior.","cat":"Utilities","winget":"StartIsBack.StartAllBack","choco":"StartAllBack","link":"https://www.startallback.com/"},"starship":{"name":"Starship (Shell Prompt)","desc":"Starship is a fast, customizable, cross-platform prompt for PowerShell and other shells.","cat":"Development","winget":"Starship.Starship","choco":"starship","link":"https://starship.rs/"},"steam":{"name":"Steam","desc":"Steam is a digital distribution platform for purchasing and playing video games, offering multiplayer gaming, video streaming, and more.","cat":"Games","winget":"Valve.Steam","choco":"steam-client","link":"https://store.steampowered.com/about/"},"roblox":{"name":"Roblox","desc":"Roblox is a platform and game creation system that allows users to create and play games developed by the community.","cat":"Games","winget":"Roblox.Roblox","choco":"na","link":"https://www.roblox.com/"},"sublimetext":{"name":"Sublime Text","desc":"Sublime Text is a sophisticated text editor for code, markup, and prose.","cat":"Development","winget":"SublimeHQ.SublimeText.4","choco":"sublimetext4","link":"https://www.sublimetext.com/"},"sumatra":{"name":"Sumatra PDF","desc":"Sumatra PDF is a lightweight and fast PDF viewer with minimalistic design.","cat":"Document","winget":"SumatraPDF.SumatraPDF","choco":"sumatrapdf","link":"https://www.sumatrapdfreader.org/free-pdf-reader.html"},"sunshine":{"name":"Sunshine/GameStream Server","desc":"Sunshine is a GameStream server that allows you to remotely play PC games on Android devices, offering low-latency streaming.","cat":"Selfhosted Tools","winget":"LizardByte.Sunshine","choco":"sunshine","link":"https://app.lizardbyte.dev/Sunshine/"},"tcpview":{"name":"TCPView","desc":"SysInternals TCPView is a network monitoring tool that displays a detailed list of all TCP and UDP endpoints on your system.","cat":"Microsoft Tools","winget":"Microsoft.Sysinternals.TCPView","choco":"tcpview","link":"https://docs.microsoft.com/en-us/sysinternals/downloads/tcpview"},"teams":{"name":"Teams","desc":"Microsoft Teams is a collaboration platform that integrates with Office 365 and offers chat, video conferencing, file sharing, and more.","cat":"Communications","winget":"Microsoft.Teams","choco":"microsoft-teams","link":"https://www.microsoft.com/en-us/microsoft-teams/group-chat-software"},"teamviewer":{"name":"TeamViewer","desc":"TeamViewer is a popular remote access and support software that allows you to connect to and control remote devices.","cat":"Utilities","winget":"TeamViewer.TeamViewer","choco":"teamviewer9","link":"https://www.teamviewer.com/"},"teamspeak3":{"name":"TeamSpeak 3","desc":"TEAMSPEAK. YOUR TEAM. YOUR RULES. Use crystal clear sound to communicate with your teammates cross-platform with military-grade security, lag-free performance & unparalleled reliability and uptime.","cat":"Communications","winget":"TeamSpeakSystems.TeamSpeakClient","choco":"teamspeak","link":"https://www.teamspeak.com/"},"teamspeak6":{"name":"TeamSpeak 6","desc":"TEAMSPEAK. YOUR TEAM. YOUR RULES. Use crystal clear sound to communicate with your teammates cross-platform with military-grade security, lag-free performance & unparalleled reliability and uptime.","cat":"Communications","winget":"TeamSpeakSystems.TeamSpeakClient.Beta.6","choco":"na","link":"https://www.teamspeak.com/"},"telegram":{"name":"Telegram","desc":"Telegram is a cloud-based instant messaging app known for its security features, speed, and simplicity.","cat":"Communications","winget":"Telegram.TelegramDesktop","choco":"telegram","link":"https://telegram.org/"},"terminal":{"name":"Windows Terminal","desc":"Windows Terminal is a modern, fast, and efficient terminal application for command-line users, supporting multiple tabs, panes, and more.","cat":"Microsoft Tools","winget":"Microsoft.WindowsTerminal","choco":"microsoft-windows-terminal","link":"https://aka.ms/terminal"},"thunderbird":{"name":"Thunderbird","desc":"Mozilla Thunderbird is a free and open-source email client, news client, and chat client with advanced features.","cat":"Communications","winget":"Mozilla.Thunderbird","choco":"thunderbird","link":"https://www.thunderbird.net/"},"betterbird":{"name":"Betterbird","desc":"Betterbird is a fork of Mozilla Thunderbird with additional features and bugfixes.","cat":"Communications","winget":"Betterbird.Betterbird","choco":"betterbird","link":"https://www.betterbird.eu/"},"tor":{"name":"Tor Browser","desc":"Tor Browser is designed for anonymous web browsing, utilizing the Tor network to protect user privacy and security.","cat":"Browsers","winget":"TorProject.TorBrowser","choco":"tor-browser","link":"https://www.torproject.org/"},"totalcommander":{"name":"Total Commander","desc":"Total Commander is a file manager for Windows that provides a powerful and intuitive interface for file management.","cat":"Utilities","winget":"Ghisler.TotalCommander","choco":"TotalCommander","link":"https://www.ghisler.com/"},"treesize":{"name":"TreeSize Free","desc":"TreeSize Free is a disk space manager that helps you analyze and visualize the space usage on your drives.","cat":"Utilities","winget":"JAMSoftware.TreeSize.Free","choco":"treesizefree","link":"https://www.jam-software.com/treesize_free/"},"ttaskbar":{"name":"TranslucentTB","desc":"TranslucentTB is a tool that allows you to customize the transparency of the Windows Taskbar.","cat":"Utilities","winget":"CharlesMilette.TranslucentTB","choco":"translucenttb","link":"https://translucenttb.github.io"},"ubisoft":{"name":"Ubisoft Connect","desc":"Ubisoft Connect is Ubisoft's digital distribution and online gaming service, providing access to Ubisoft's games and services.","cat":"Games","winget":"Ubisoft.Connect","choco":"ubisoft-connect","link":"https://ubisoftconnect.com/"},"ungoogled":{"name":"Ungoogled Chromium","desc":"Ungoogled Chromium is a version of Chromium without Google's integration for enhanced privacy and control.","cat":"Browsers","winget":"eloston.ungoogled-chromium","choco":"ungoogled-chromium","link":"https://github.com/Eloston/ungoogled-chromium"},"unity":{"name":"Unity Game Engine","desc":"Unity is a powerful game development platform for creating 2D, 3D, augmented reality, and virtual reality games.","cat":"Development","winget":"Unity.UnityHub","choco":"unityhub","link":"https://unity.com/"},"vagrant":{"name":"Vagrant","desc":"Vagrant builds and manages reproducible virtual machine development environments from declarative configuration.","cat":"Development","winget":"Hashicorp.Vagrant","choco":"vagrant","link":"https://developer.hashicorp.com/vagrant"},"everything":{"name":"Everything","desc":"Everything is a search engine that locates files and folders by filename instantly for Windows. Unlike Windows search Everything initially displays every file and folder on your computer (hence the name Everything). You type in a search filter to limit what files and folders are displayed.","cat":"Utilities","winget":"voidtools.Everything","choco":"everything","link":"https://www.voidtools.com/"},"vc2015_32":{"name":"Visual C++ 2015-2022 32-bit","desc":"Visual C++ 2015-2022 32-bit redistributable package installs runtime components of Visual C++ libraries required to run 32-bit applications.","cat":"Microsoft Tools","winget":"Microsoft.VCRedist.2015+.x86","choco":"vcredist2015","link":"https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads"},"vc2015_64":{"name":"Visual C++ 2015-2022 64-bit","desc":"Visual C++ 2015-2022 64-bit redistributable package installs runtime components of Visual C++ libraries required to run 64-bit applications.","cat":"Microsoft Tools","winget":"Microsoft.VCRedist.2015+.x64","choco":"vcredist2015","link":"https://support.microsoft.com/en-us/help/2977003/the-latest-supported-visual-c-downloads"},"ventoy":{"name":"Ventoy","desc":"Ventoy is an open-source tool for creating bootable USB drives. It supports multiple ISO files on a single USB drive, making it a versatile solution for installing operating systems.","cat":"Pro Tools","winget":"Ventoy.Ventoy","choco":"ventoy","link":"https://www.ventoy.net/"},"vesktop":{"name":"Vesktop","desc":"A cross platform electron-based desktop app aiming to give you a snappier Discord experience with Vencord pre-installed.","cat":"Communications","winget":"Vencord.Vesktop","choco":"na","link":"https://vesktop.dev"},"viber":{"name":"Viber","desc":"Viber is a free messaging and calling app with features like group chats, video calls, and more.","cat":"Communications","winget":"Rakuten.Viber","choco":"viber","link":"https://www.viber.com/"},"visualstudio2022":{"name":"Visual Studio 2022","desc":"Visual Studio 2022 is an integrated development environment (IDE) for building, debugging, and deploying applications.","cat":"Development","winget":"Microsoft.VisualStudio.2022.Community","choco":"visualstudio2022community","link":"https://visualstudio.microsoft.com/"},"visualstudio2026":{"name":"Visual Studio 2026","desc":"Visual Studio 2026 is an integrated development environment (IDE) for building, debugging, and deploying applications.","cat":"Development","winget":"Microsoft.VisualStudio.Community","choco":"visualstudio2026community","link":"https://visualstudio.microsoft.com/"},"vivaldi":{"name":"Vivaldi","desc":"Vivaldi is a highly customizable web browser with a focus on user personalization and productivity features.","cat":"Browsers","winget":"Vivaldi.Vivaldi","choco":"vivaldi","link":"https://vivaldi.com/"},"vlc":{"name":"VLC (Video Player)","desc":"VLC Media Player is a free and open-source multimedia player that supports a wide range of audio and video formats. It is known for its versatility and cross-platform compatibility.","cat":"Multimedia Tools","winget":"VideoLAN.VLC","choco":"vlc","link":"https://www.videolan.org/vlc/"},"vrdesktopstreamer":{"name":"Virtual Desktop Streamer","desc":"Virtual Desktop Streamer is a tool that allows you to stream your desktop screen to VR devices.","cat":"Games","winget":"VirtualDesktop.Streamer","choco":"na","link":"https://www.vrdesktop.net/"},"vscode":{"name":"VS Code","desc":"Visual Studio Code is a free, open-source code editor with support for multiple programming languages.","cat":"Development","winget":"Microsoft.VisualStudioCode","choco":"vscode","link":"https://code.visualstudio.com/"},"vscodium":{"name":"VS Codium","desc":"VSCodium is a community-driven, freely-licensed binary distribution of Microsoft's VS Code.","cat":"Development","winget":"VSCodium.VSCodium","choco":"vscodium","link":"https://vscodium.com/"},"waterfox":{"name":"Waterfox","desc":"Waterfox is a fast, privacy-focused web browser based on Firefox, designed to preserve user choice and privacy.","cat":"Browsers","winget":"Waterfox.Waterfox","choco":"waterfox","link":"https://www.waterfox.net/"},"whatsapp":{"name":"WhatsApp Desktop","desc":"WhatsApp Desktop is the official Windows desktop messaging app from Meta, distributed through the Microsoft Store.","cat":"Communications","winget":"msstore:9NKSQGP7F2NH","choco":"na","link":"https://www.whatsapp.com/download"},"wingetui":{"name":"UniGetUI","desc":"UniGetUI is a GUI for WinGet, Chocolatey, and other Windows CLI package managers.","cat":"Utilities","winget":"Devolutions.UniGetUI","choco":"wingetui","link":"https://devolutions.net/unigetui/"},"winrar":{"name":"WinRAR","desc":"WinRAR is a powerful archive manager that allows you to create, manage, and extract compressed files.","cat":"Utilities","winget":"RARLab.WinRAR","choco":"winrar","link":"https://www.win-rar.com/"},"winscp":{"name":"WinSCP","desc":"WinSCP is a popular open-source SFTP, FTP, and SCP client for Windows. It allows secure file transfers between a local and a remote computer.","cat":"Pro Tools","winget":"WinSCP.WinSCP","choco":"winscp","link":"https://winscp.net/"},"wireguard":{"name":"WireGuard","desc":"WireGuard is a fast and modern VPN (Virtual Private Network) protocol. It aims to be simpler and more efficient than other VPN protocols, providing secure and reliable connections.","cat":"Pro Tools","winget":"WireGuard.WireGuard","choco":"wireguard","link":"https://www.wireguard.com/"},"wireshark":{"name":"Wireshark","desc":"Wireshark is a widely-used open-source network protocol analyzer. It allows users to capture and analyze network traffic in real-time, providing detailed insights into network activities.","cat":"Pro Tools","winget":"WiresharkFoundation.Wireshark","choco":"wireshark","link":"https://www.wireshark.org/"},"wiztree":{"name":"WizTree","desc":"WizTree is a fast disk space analyzer that helps you quickly find the files and folders consuming the most space on your hard drive.","cat":"Utilities","winget":"AntibodySoftware.WizTree","choco":"wiztree","link":"https://wiztreefree.com/"},"xeheditor":{"name":"HxD Hex Editor","desc":"HxD is a free hex editor that allows you to edit, view, search, and analyze binary files.","cat":"Utilities","winget":"MHNexus.HxD","choco":"HxD","link":"https://mh-nexus.de/en/hxd/"},"xournal":{"name":"Xournal++","desc":"Xournal++ is an open-source handwriting notetaking software with PDF annotation capabilities.","cat":"Document","winget":"Xournal++.Xournal++","choco":"xournalplusplus","link":"https://xournalpp.github.io/"},"yarn":{"name":"Yarn","desc":"Yarn is a fast, reliable, and secure dependency management tool for JavaScript projects.","cat":"Development","winget":"Yarn.Yarn","choco":"yarn","link":"https://yarnpkg.com/"},"zoom":{"name":"Zoom","desc":"Zoom is a popular video conferencing and web conferencing service for online meetings, webinars, and collaborative projects.","cat":"Communications","winget":"Zoom.Zoom","choco":"zoom","link":"https://zoom.us/"},"uv":{"name":"uv","desc":"uv is a fast Python package and project manager written in Rust.","cat":"Development","winget":"astral-sh.uv","choco":"uv","link":"https://docs.astral.sh/uv/getting-started/installation/"},"tightvnc":{"name":"TightVNC","desc":"TightVNC is a free and open-source remote desktop software that lets you access and control a computer over the network. With its intuitive interface, you can interact with the remote screen as if you were sitting in front of it. You can open files, launch applications, and perform other actions on the remote desktop almost as if you were physically there.","cat":"Utilities","winget":"GlavSoft.TightVNC","choco":"TightVNC","link":"https://www.tightvnc.com/"},"glazewm":{"name":"GlazeWM","desc":"GlazeWM is a tiling window manager for Windows inspired by i3 and Polybar.","cat":"Utilities","winget":"glzr-io.glazewm","choco":"glazewm","link":"https://github.com/glzr-io/glazewm"},"Overwolf":{"name":"Overwolf","desc":"Popular platform for game overlays and companion apps (mod managers, trackers, etc.), widely used by gamers.","cat":"Games","winget":"Overwolf.CurseForge","choco":"overwolf","link":"https://www.overwolf.com/app/overwolf-curseforge"},"OFGB":{"name":"OFGB (Oh Frick Go Back)","desc":"GUI Tool to remove ads from various places around Windows 11","cat":"Utilities","winget":"xM4ddy.OFGB","choco":"ofgb","link":"https://github.com/xM4ddy/OFGB"},"ZenBrowser":{"name":"Zen Browser","desc":"The modern, privacy-focused, performance-driven browser built on Firefox.","cat":"Browsers","winget":"Zen-Team.Zen-Browser","choco":"zen-browser","link":"https://zen-browser.app/"},"Zed":{"name":"Zed","desc":"Zed is a modern, high-performance code editor designed from the ground up for speed and collaboration.","cat":"Development","winget":"ZedIndustries.Zed","choco":"zed","link":"https://zed.dev/"},"zotero":{"name":"Zotero","desc":"Zotero is a free, easy-to-use tool to help you collect, organize, cite, and share your research materials.","cat":"Document","winget":"DigitalScholar.Zotero","choco":"zotero","link":"https://www.zotero.org/"},"deskflow":{"name":"Deskflow","desc":"Deskflow is a free and open-source software KVM that lets you share a single keyboard and mouse across multiple computers.","cat":"Utilities","winget":"Deskflow.Deskflow","choco":"deskflow","link":"https://github.com/deskflow/deskflow"},"Ruby":{"name":"Ruby","desc":"A Ruby language execution environment with a MSYS2 installation.","cat":"Development","winget":"RubyInstallerTeam.Ruby.4.0","choco":"ruby","link":"https://rubyinstaller.org/"},"Lua":{"name":"Lua","desc":"A 'batteries included environment' for the Lua scripting language on Windows.","cat":"Development","winget":"rjpcomputing.luaforwindows","choco":"lua","link":"https://github.com/rjpcomputing/luaforwindows"},"CloudflareWARP":{"name":"Cloudflare WARP","desc":"WARP is a freemium VPN service provided by Cloudflare. Includes usage of Cloudflare's DNS","cat":"Utilities","winget":"Cloudflare.Warp","choco":"warp","link":"https://one.one.one.one"},"spotify":{"name":"Spotify","desc":"Spotify is a digital music streaming service giving access to millions of songs, podcasts, and playlists.","cat":"Multimedia Tools","winget":"Spotify.Spotify","choco":"spotify","link":"https://www.spotify.com/"},"windhawk":{"name":"Windhawk","desc":"Windhawk is a customization marketplace for Windows programs, letting you install community-made mods that tweak the look and behavior of apps and the OS.","cat":"Utilities","winget":"RamenSoftware.Windhawk","choco":"windhawk","link":"https://windhawk.net/"}}
'@
$TweaksJson = @'
{"WPFTweaksActivity":{"name":"Activity History - Disable","desc":"Erases recent docs, clipboard, and run history.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"EnableActivityFeed","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"PublishUserActivities","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"UploadUserActivities","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksHiber":{"name":"Hibernation - Disable","desc":"Hibernation is really meant for laptops as it saves what's in memory before turning the PC off. It really should never be used.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\System\\CurrentControlSet\\Control\\Session Manager\\Power","Name":"HibernateEnabled","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\FlyoutMenuSettings","Name":"ShowHibernateOption","Value":"0","Type":"DWord","OriginalValue":"1"}],"apply":["powercfg.exe /hibernate off"],"undo":["powercfg.exe /hibernate on"]},"WPFTweaksWidget":{"name":"Widgets - Remove","desc":"Removes the annoying widgets in the bottom left of the Taskbar.","cat":"Essential Tweaks","type":"Checkbox","apply":["\n      # Sometimes if you dont stop the Widgets process the removal may fail\n\n      Get-Process *Widget* | Stop-Process\n      Get-AppxPackage Microsoft.WidgetsPlatformRuntime -AllUsers | Remove-AppxPackage -AllUsers\n      Get-AppxPackage MicrosoftWindows.Client.WebExperience -AllUsers | Remove-AppxPackage -AllUsers\n\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      Write-Host \"Removed widgets\"\n      "]},"WPFTweaksRevertStartMenu":{"name":"Start Menu Previous Layout - Enable","desc":"Bring back the old Start Menu layout from before the gradual rollout of the new one in 25H2. On newer versions of Windows !!THIS TWEAK WILL NOT WORK!!","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SYSTEM\\ControlSet001\\Control\\FeatureManagement\\Overrides\\8\\3036241548","Name":"EnabledState","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksDisableStoreSearch":{"name":"Microsoft Store Recommended Search Results - Disable","desc":"Will not display recommended Microsoft Store apps when searching for apps in the Start menu.","cat":"Essential Tweaks","type":"Checkbox","apply":["icacls \"$Env:LocalAppData\\Packages\\Microsoft.WindowsStore_8wekyb3d8bbwe\\LocalState\\store.db\" /deny Everyone:F"],"undo":["icacls \"$Env:LocalAppData\\Packages\\Microsoft.WindowsStore_8wekyb3d8bbwe\\LocalState\\store.db\" /grant Everyone:F"]},"WPFTweaksLocation":{"name":"Location Tracking - Disable","desc":"Disables Location Tracking.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\location","Name":"Value","Value":"Deny","Type":"String","OriginalValue":"Allow"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Sensor\\Overrides\\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}","Name":"SensorPermissionState","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKLM:\\SYSTEM\\Maps","Name":"AutoUpdateEnabled","Value":"0","Type":"DWord","OriginalValue":"1"}],"service":[{"Name":"lfsvc","StartupType":"Disabled","OriginalType":"Manual"}]},"WPFTweaksServices":{"name":"Services - Set to Manual","desc":"Sets some services to Manual startup and adjusts the SvcHostSplitThresholdInKB registry value to better match system memory, which can significantly reduce the number of svchost.exe processes.","cat":"Essential Tweaks","type":"Checkbox","apply":["\n      $Memory = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB\n      Set-ItemProperty -Path \"HKLM:\\SYSTEM\\CurrentControlSet\\Control\" -Name SvcHostSplitThresholdInKB -Value $Memory\n      "],"service":[{"Name":"CscService","StartupType":"Disabled","OriginalType":"Manual"},{"Name":"DiagTrack","StartupType":"Disabled","OriginalType":"Automatic"},{"Name":"MapsBroker","StartupType":"Manual","OriginalType":"Automatic"},{"Name":"StorSvc","StartupType":"Manual","OriginalType":"Automatic"},{"Name":"SharedAccess","StartupType":"Disabled","OriginalType":"Automatic"}]},"WPFTweaksBraveDebloat":{"name":"Brave Browser - Debloat","desc":"Disables various annoyances like Brave Rewards, Leo AI, Crypto Wallet and VPN.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveRewardsDisabled","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveWalletDisabled","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveVPNDisabled","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveAIChatEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveStatsPingEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveNewsDisabled","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveTalkDisabled","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"TorDisabled","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"BraveP3AEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"UrlKeyedAnonymizedDataCollectionEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"SafeBrowsingExtendedReportingEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\BraveSoftware\\Brave","Name":"MetricsReportingEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksDisableWarningForUnsignedRdp":{"name":"RDP Unsigned File Warnings - Disable","desc":"Disables warnings shown when launching unsigned RDP files introduced with the latest Windows 10 and 11 updates.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services\\Client","Name":"RedirectionWarningDialogVersion","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Terminal Server Client","Name":"RdpLaunchConsentAccepted","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksEdgeDebloat":{"name":"Microsoft Edge - Debloat","desc":"Disables various telemetry options, popups, and other annoyances in Edge.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\EdgeUpdate","Name":"CreateDesktopShortcutDefault","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"PersonalizationReportingEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge\\ExtensionInstallBlocklist","Name":"1","Value":"ofefcgjbeghpigppfmkologfjadafddi","Type":"String","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"ShowRecommendationsEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"HideFirstRunExperience","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"UserFeedbackAllowed","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"ConfigureDoNotTrack","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"AlternateErrorPagesEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"EdgeCollectionsEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"EdgeShoppingAssistantEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"MicrosoftEdgeInsiderPromotionEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"ShowMicrosoftRewards","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"WebWidgetAllowed","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"DiagnosticData","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"EdgeAssetDeliveryServiceEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"WalletDonationEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge","Name":"DefaultBrowserSettingsCampaignEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksConsumerFeatures":{"name":"ConsumerFeatures - Disable","desc":"Stops promoted app installs and reduces app suggestions from Microsoft Store content.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\CloudContent","Name":"DisableWindowsConsumerFeatures","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksTelemetry":{"name":"Telemetry - Disable","desc":"Disables Microsoft Telemetry.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo","Name":"Enabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Privacy","Name":"TailoredExperiencesWithDiagnosticDataEnabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Speech_OneCore\\Settings\\OnlineSpeechPrivacy","Name":"HasAccepted","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Input\\TIPC","Name":"Enabled","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\InputPersonalization","Name":"RestrictImplicitInkCollection","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\InputPersonalization","Name":"RestrictImplicitTextCollection","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\InputPersonalization\\TrainedDataStore","Name":"HarvestContacts","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Personalization\\Settings","Name":"AcceptedPrivacyPolicy","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\DataCollection","Name":"AllowTelemetry","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"Start_TrackProgs","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"PublishUserActivities","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Siuf\\Rules","Name":"NumberOfSIUFInPeriod","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"}],"apply":["\n      # Disable Defender Auto Sample Submission\n      Set-MpPreference -SubmitSamplesConsent 2\n\n      # Disable (Connected User Experiences and Telemetry) Service\n      Set-Service -Name diagtrack -StartupType Disabled\n\n      # Disable (Windows Error Reporting Manager) Service\n      Set-Service -Name wermgr -StartupType Disabled\n\n      # Disable PowerShell 7 telemetry\n      [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')\n\n      Remove-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Siuf\\Rules\" -Name PeriodInNanoSeconds\n      "],"undo":["\n      # Enable Defender Auto Sample Submission\n      Set-MpPreference -SubmitSamplesConsent 1\n\n      # Enable (Connected User Experiences and Telemetry) Service\n      Set-Service -Name diagtrack -StartupType Automatic\n\n      # Enable (Windows Error Reporting Manager) Service\n      Set-Service -Name wermgr -StartupType Automatic\n\n      # Enable PowerShell 7 telemetry\n      [Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '', 'Machine')\n      "]},"WPFTweaksDeliveryOptimization":{"name":"Delivery Optimization - Disable","desc":"Stops Windows from using your bandwidth to upload updates to other PCs on the internet or local network.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DeliveryOptimization","Name":"DODownloadMode","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksRemoveEdge":{"name":"Microsoft Edge - Remove","desc":"Uninstalls Microsoft Edge by creating dummy MicrosoftEdge.exe file in the legacy Edge folder. This tricks Windows into unlocking the official Edge uninstaller allowing for a system-level removal.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","apply":["\n      $Path = Resolve-Path -Path \"$Env:ProgramFiles (x86)\\Microsoft\\Edge\\Application\\*\\Installer\\setup.exe\" | Select-Object -Last 1\n\n      if (Test-Path $Path) {\n          New-Item -Path \"$Env:SystemRoot\\SystemApps\\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\\MicrosoftEdge.exe\" -Force\n          Start-Process -FilePath $Path -ArgumentList \"--uninstall --system-level --force-uninstall --delete-profile\" -Wait\n          Write-Host \"Microsoft Edge was removed\"\n      } else {\n          Write-Host \"Microsoft Edge is not installed\"\n      }\n      "],"undo":["\n      Write-Host \"Installing Microsoft Edge...\"\n      winget install Microsoft.Edge --source winget\n      "]},"WPFTweaksDisableBitLocker":{"name":"BitLocker - Disable","desc":"Disables BitLocker.","cat":"Essential Tweaks","type":"Checkbox","apply":["Disable-BitLocker -MountPoint $Env:SystemDrive"],"undo":["Enable-BitLocker -MountPoint $Env:SystemDrive"]},"WPFTweaksUTC":{"name":"Date & Time - Set Time to UTC","desc":"Essential for computers that are dual booting. Fixes the time sync with Linux systems.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\TimeZoneInformation","Name":"RealTimeIsUniversal","Value":"1","Type":"QWord","OriginalValue":"0"}]},"WPFTweaksRemoveOneDrive":{"name":"Microsoft OneDrive - Remove","desc":"Denies permission to remove OneDrive user files, then uses its own uninstaller to remove it and restores the original permission afterward.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","apply":["\n      # Deny permission to remove OneDrive folder\n      icacls $Env:OneDrive /deny \"Administrators:(D,DC)\"\n\n      Write-Host \"Uninstalling OneDrive...\"\n      Start-Process -FilePath (Join-Path $Env:SystemRoot \"System32\\OneDriveSetup.exe\") -ArgumentList '/uninstall' -Wait\n\n      # Some of OneDrive files use explorer, and OneDrive uses FileCoAuth\n      Write-Host \"Removing leftover OneDrive Files...\"\n\n      Stop-Process -Name FileCoAuth,Explorer\n\n      Remove-Item \"$Env:LocalAppData\\Microsoft\\OneDrive\" -Recurse -Force\n      Remove-Item \"$Env:ProgramData\\Microsoft OneDrive\" -Recurse -Force\n\n      # Grant back permission to access OneDrive folder\n      icacls $Env:OneDrive /grant \"Administrators:(D,DC)\"\n\n      if (-not (Get-ChildItem -Path $Env:OneDrive)) {\n          Remove-Item -Path $Env:OneDrive -Recurse\n          [Environment]::SetEnvironmentVariable('OneDrive', $null, 'User')\n      }\n\n      # Disable OneSyncSvc\n      Set-Service -Name OneSyncSvc -StartupType Disabled\n      "],"undo":["\n      Write-Host \"Installing OneDrive\"\n      winget install Microsoft.Onedrive --source winget\n\n      # Enabled OneSyncSvc\n      Set-Service -Name OneSyncSvc -StartupType Automatic\n      "]},"WPFTweaksRemoveHomeAndGallery":{"name":"File Explorer Home and Gallery - Disable","desc":"Removes the Home and Gallery from Explorer and sets This PC as default.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKCU:\\Software\\Classes\\CLSID\\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}","Name":"System.IsPinnedToNameSpaceTree","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Classes\\CLSID\\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}","Name":"System.IsPinnedToNameSpaceTree","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"LaunchTo","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksDisplay":{"name":"Visual Effects - Set to Best Performance","desc":"Sets the system preferences to performance. You can do this manually with sysdm.cpl as well.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKCU:\\Control Panel\\Desktop","Name":"DragFullWindows","Value":"0","Type":"String","OriginalValue":"1"},{"Path":"HKCU:\\Control Panel\\Desktop","Name":"MenuShowDelay","Value":"200","Type":"String","OriginalValue":"400"},{"Path":"HKCU:\\Control Panel\\Desktop\\WindowMetrics","Name":"MinAnimate","Value":"0","Type":"String","OriginalValue":"1"},{"Path":"HKCU:\\Control Panel\\Keyboard","Name":"KeyboardDelay","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"ListviewAlphaSelect","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"ListviewShadow","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"TaskbarAnimations","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\VisualEffects","Name":"VisualFXSetting","Value":"3","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\DWM","Name":"EnableAeroPeek","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"TaskbarMn","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"ShowTaskViewButton","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search","Name":"SearchboxTaskbarMode","Value":"0","Type":"DWord","OriginalValue":"1"}],"apply":["Set-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0))"],"undo":["Remove-ItemProperty -Path \"HKCU:\\Control Panel\\Desktop\" -Name \"UserPreferencesMask\""]},"WPFTweaksReservedStorage":{"name":"Disable Reserved Storage","desc":"Disables Windows Reserved Storage (7-10 GB held for updates/temp files). Recommended only on small drives. Re-enable before major Windows feature updates to avoid installation failures.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","apply":["DISM /Online /Set-ReservedStorageState /State:Disabled"],"undo":["DISM /Online /Set-ReservedStorageState /State:Enabled"]},"WPFTweaksRestorePoint":{"name":"Restore Point - Create","desc":"Creates a restore point at runtime in case a revert is needed from WinUtil modifications.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\SystemRestore","Name":"SystemRestorePointCreationFrequency","Value":"0","Type":"DWord","OriginalValue":"1440"}],"apply":["\n      if (-not (Get-ComputerRestorePoint)) {\n          Enable-ComputerRestore -Drive $Env:SystemDrive\n      }\n\n      Checkpoint-Computer -Description \"System Restore Point created by WinUtil\" -RestorePointType MODIFY_SETTINGS\n      Write-Host \"System Restore Point Created Successfully\" -ForegroundColor Green\n      "]},"WPFTweaksEndTaskOnTaskbar":{"name":"End Task With Right Click - Enable","desc":"Enables option to end task when right clicking a program in the taskbar.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced\\TaskbarDeveloperSettings","Name":"TaskbarEndTask","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksStorage":{"name":"Storage Sense - Disable","desc":"Storage Sense deletes temp files automatically.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\StorageSense\\Parameters\\StoragePolicy","Name":"01","Value":"0","Type":"DWord","OriginalValue":"1"}]},"WPFTweaksWindowsAI":{"name":"Windows AI - Disable And Remove","desc":"Removes and disables all AI features/packages","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer","Name":"SettingsPageVisibility","Value":"hide:aicomponents","Type":"String","OriginalValue":"<RemoveEntry>"},{"Path":"HKLM:\\SOFTWARE\\Policies\\WindowsNotepad","Name":"DisableAIFeatures","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}],"apply":["\n      $Appx = (Get-AppxPackage MicrosoftWindows.Client.CoreAI).PackageFullName\n      $Sid = (Get-LocalUser $Env:UserName).Sid.Value\n\n      New-Item \"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Appx\\AppxAllUserStore\\EndOfLife\\$Sid\\$Appx\" -Force\n\n      Get-AppxPackage -AllUsers \"*Copilot*\" | Remove-AppxPackage -AllUsers\n      winget uninstall -e --name \"Copilot\" --silent --force --accept-source-agreements 2>$null\n      Get-AppxPackage -AllUsers Microsoft.MicrosoftOfficeHub | Remove-AppxPackage -AllUsers\n\n      if ($Appx) {\n          Remove-AppxPackage $Appx\n      }\n\n      Set-Service -Name WSAIFabricSvc -StartupType Disabled\n      Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart\n\n      Write-Host \"Windows AI Disabled\"\n      "]},"WPFTweaksWPBT":{"name":"Windows Platform Binary Table (WPBT) - Disable","desc":"If enabled, WPBT allows your computer vendor to execute programs at boot time, such as anti-theft software, software drivers, as well as force install software without user consent. Poses potential security risk.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Session Manager","Name":"DisableWpbtExecution","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksPreventDeviceMetadataFromNetwork":{"name":"Prevent Device Companion Apps","desc":"Prevents additional software from being installed when plugging in devices (e.g. Ads when plugging in a monitor). Poses potential security risk.","cat":"Essential Tweaks","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Device Metadata","Name":"PreventDeviceMetadataFromNetwork","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFTweaksRazerBlock":{"name":"Razer Software Auto-Install - Disable","desc":"Blocks ALL Razer Software installations. The hardware works fine without any software.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\DriverSearching","Name":"SearchOrderConfig","Value":"0","Type":"DWord","OriginalValue":"1"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Device Installer","Name":"DisableCoInstallers","Value":"1","Type":"DWord","OriginalValue":"0"}],"apply":["\n      $RazerPath = \"$Env:SystemRoot\\Installer\\Razer\"\n\n      if (Test-Path $RazerPath) {\n        Remove-Item $RazerPath\\* -Recurse -Force\n      } else {\n        New-Item -Path $RazerPath -ItemType Directory\n      }\n\n      icacls $RazerPath /deny \"Everyone:(W)\"\n      "],"undo":["\n      icacls \"$Env:SystemRoot\\Installer\\Razer\" /remove:d Everyone\n      "]},"WPFTweaksDisableNotifications":{"name":"System Tray Notifications & Calendar - Disable","desc":"Disables all Notifications INCLUDING Calendar.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKCU:\\Software\\Policies\\Microsoft\\Windows\\Explorer","Name":"DisableNotificationCenter","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"},{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications","Name":"ToastEnabled","Value":"0","Type":"DWord","OriginalValue":"1"}]},"WPFTweaksBlockAdobeNet":{"name":"Adobe URL Block List - Enable","desc":"Reduces user interruptions by selectively blocking connections to Adobe's activation and telemetry servers. Credit: Ruddernation-Designs","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","apply":["\n      $hostsUrl = Invoke-RestMethod -Uri https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts\n      Add-Content -Path \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\" -Value $hostsUrl\n\n      ipconfig /flushdns\n      Write-Host 'Added Adobe url block list from host file'\n      "],"undo":["\n      Set-Content \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\" (\n          (Get-Content \"$Env:SystemRoot\\System32\\drivers\\etc\\hosts\") -join \"`n\" -replace '(?s)#New Ver.*', ''\n      )\n\n      ipconfig /flushdns\n      Write-Host 'Removed Adobe url block list from host file'\n      "]},"WPFTweaksRightClickMenu":{"name":"Right-Click Menu Previous Layout - Enable","desc":"Restores the classic context menu when right-clicking in File Explorer, replacing the simplified Windows 11 version.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","apply":["\n      New-Item -Path \"HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\" -Name InprocServer32 -Value \"\" -Force\n      Stop-Process -Name explorer\n      "],"undo":["Remove-Item -Path \"HKCU:\\Software\\Classes\\CLSID\\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\" -Recurse"]},"WPFTweaksDiskCleanup":{"name":"Disk Cleanup - Run","desc":"Runs Disk Cleanup on Drive C: and removes old Windows Updates.","cat":"Essential Tweaks","type":"Checkbox","apply":["\n      cleanmgr.exe /d C: /VERYLOWDISK\n      Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase\n      "]},"WPFTweaksDeleteTempFiles":{"name":"Temporary Files - Remove","desc":"Erases TEMP Folders.","cat":"Essential Tweaks","type":"Checkbox","apply":["\n      Remove-Item -Path \"$Env:Temp\\*\" -Recurse -Force\n      Remove-Item -Path \"$Env:SystemRoot\\Temp\\*\" -Recurse -Force\n      "]},"WPFTweaksIPv46":{"name":"IPv6 - Set IPv4 as Preferred","desc":"Setting the IPv4 preference can have latency and security benefits on private networks where IPv6 is not configured.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters","Name":"DisabledComponents","Value":"32","Type":"DWord","OriginalValue":"0"}]},"WPFTweaksTeredo":{"name":"Teredo - Disable","desc":"Teredo network tunneling is an IPv6 feature that can cause additional latency, but may cause problems with some games.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters","Name":"DisabledComponents","Value":"1","Type":"DWord","OriginalValue":"0"}],"apply":["netsh interface teredo set state disabled"],"undo":["netsh interface teredo set state default"]},"WPFTweaksDisableIPv6":{"name":"IPv6 - Disable","desc":"Disables IPv6.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Services\\Tcpip6\\Parameters","Name":"DisabledComponents","Value":"255","Type":"DWord","OriginalValue":"0"}],"apply":["Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip6"],"undo":["Enable-NetAdapterBinding -Name * -ComponentID ms_tcpip6"]},"WPFTweaksDisableBGapps":{"name":"Background Apps - Disable","desc":"Disables all Microsoft Store apps from running in the background, which has to be done individually since Windows 11.","cat":"z__Advanced Tweaks - CAUTION","type":"Checkbox","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\BackgroundAccessApplications","Name":"GlobalUserDisabled","Value":"1","Type":"DWord","OriginalValue":"0"}]},"WPFTweaksDisableExplorerAutoDiscovery":{"name":"File Explorer Automatic Folder Discovery - Disable","desc":"Windows Explorer automatically tries to guess the type of the folder based on its contents, slowing down the browsing experience. WARNING! Will disable File Explorer grouping.","cat":"Essential Tweaks","type":"Checkbox","apply":["\n      # Previously detected folders\n      $bags = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\"\n\n      # Folder types lookup table\n      $bagMRU = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\BagMRU\"\n\n      # Flush Explorer view database\n      Remove-Item -Path $bags -Recurse -Force\n      Write-Host \"Removed $bags\"\n\n      Remove-Item -Path $bagMRU -Recurse -Force\n      Write-Host \"Removed $bagMRU\"\n\n      # Every folder\n      $allFolders = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\\AllFolders\\Shell\"\n\n      if (!(Test-Path $allFolders)) {\n        New-Item -Path $allFolders -Force\n        Write-Host \"Created $allFolders\"\n      }\n\n      # Generic view\n      New-ItemProperty -Path $allFolders -Name \"FolderType\" -Value \"NotSpecified\" -PropertyType String -Force\n      Write-Host \"Set FolderType to NotSpecified\"\n\n      Write-Host Please sign out and back in, or restart your computer to apply the changes!\n      "],"undo":["\n      # Previously detected folders\n      $bags = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\Bags\"\n\n      # Folder types lookup table\n      $bagMRU = \"HKCU:\\Software\\Classes\\Local Settings\\Software\\Microsoft\\Windows\\Shell\\BagMRU\"\n\n      # Flush Explorer view database\n      Remove-Item -Path $bags -Recurse -Force\n      Write-Host \"Removed $bags\"\n\n      Remove-Item -Path $bagMRU -Recurse -Force\n      Write-Host \"Removed $bagMRU\"\n\n      Write-Host Please sign out and back in, or restart your computer to apply the changes!\n      "]},"WPFToggleDetailedBSoD":{"name":"BSoD Verbose Mode","desc":"Gives more information when you blue screen.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\CrashControl","Name":"DisplayParameters","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"},{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\CrashControl","Name":"DisableEmoticon","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}]},"WPFToggleBatteryPercentage":{"name":"System Tray Battery Percentage","desc":"Shows numeric battery percentage next to the battery icon in the system tray.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"IsBatteryPercentageEnabled","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>","DefaultState":"false"}]},"WPFToggleDarkMode":{"name":"Dark Theme for Windows","desc":"Dark Mode for the system and applications.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize","Name":"AppsUseLightTheme","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"},{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize","Name":"SystemUsesLightTheme","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"}],"apply":["\n      Invoke-WinUtilExplorerUpdate\n      if ($sync.ThemeButton.Content -eq [char]0xF08C) {\n        Invoke-WinutilThemeChange -theme \"Auto\"\n      }\n      "],"undo":["\n      Invoke-WinUtilExplorerUpdate\n      if ($sync.ThemeButton.Content -eq [char]0xF08C) {\n        Invoke-WinutilThemeChange -theme \"Auto\"\n      }\n      "]},"WPFToggleShowExt":{"name":"File Explorer File Extensions","desc":"Shows .file extensions in Explorer (.exe, .png, etc.)","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"HideFileExt","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"}],"apply":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "],"undo":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "]},"WPFToggleHiddenFiles":{"name":"File Explorer Hidden Files","desc":"Reveals hidden files in Explorer.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"Hidden","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}],"apply":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "],"undo":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "]},"WPFToggleVerboseLogon":{"name":"Logon Verbose Mode","desc":"Show detailed messages during startup/shutdown.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System","Name":"VerboseStatus","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}]},"WPFToggleNewOutlook":{"name":"Microsoft Outlook New Version","desc":"This will ensures the classic Outlook application is used.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\SOFTWARE\\Microsoft\\Office\\16.0\\Outlook\\Preferences","Name":"UseNewOutlook","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Software\\Microsoft\\Office\\16.0\\Outlook\\Options\\General","Name":"HideNewOutlookToggle","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"},{"Path":"HKCU:\\Software\\Policies\\Microsoft\\Office\\16.0\\Outlook\\Options\\General","Name":"DoNewOutlookAutoMigration","Value":"0","Type":"DWord","OriginalValue":"0","DefaultState":"false"},{"Path":"HKCU:\\Software\\Policies\\Microsoft\\Office\\16.0\\Outlook\\Preferences","Name":"NewOutlookMigrationUserSetting","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>","DefaultState":"true"}]},"WPFToggleScrollbars":{"name":"Scrollbars Always Visible","desc":"If enabled, scrollbars will always be visible. If disabled, Windows will automatically hide scrollbars when not in use.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Accessibility","Name":"DynamicScrollbars","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"false"}]},"WPFToggleMouseAcceleration":{"name":"Mouse Acceleration","desc":"Makes it so Cursor movement is affected by the speed of your physical mouse movements.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Mouse","Name":"MouseSpeed","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Control Panel\\Mouse","Name":"MouseThreshold1","Value":"6","Type":"DWord","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Control Panel\\Mouse","Name":"MouseThreshold2","Value":"10","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleNumLock":{"name":"Num Lock on Startup","desc":"Toggle the Num Lock key state when your computer starts.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKU:\\.Default\\Control Panel\\Keyboard","Name":"InitialKeyboardIndicators","Value":"2","Type":"String","OriginalValue":"0","DefaultState":"false"},{"Path":"HKCU:\\Control Panel\\Keyboard","Name":"InitialKeyboardIndicators","Value":"2","Type":"String","OriginalValue":"0","DefaultState":"false"}]},"WPFToggleWindowSnapping":{"name":"Window Snapping","desc":"Toggles the window snapping feature when dragging windows.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Desktop","Name":"WindowArrangementActive","Value":"1","Type":"String","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleStandbyFix":{"name":"S0 Sleep Network Connectivity","desc":"Toggles network connectivity during S0 Sleep which is low power idle in modern laptops.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\SOFTWARE\\Policies\\Microsoft\\Power\\PowerSettings\\f15576e8-98b7-4186-b944-eafa664402d9","Name":"ACSettingIndex","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleS3Sleep":{"name":"S3 Sleep","desc":"Toggles between Modern Standby and S3 Sleep, which cuts off power to the CPU while continuing to refresh the memory.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Power","Name":"PlatformAoAcOverride","Value":"0","Type":"DWord","OriginalValue":"<RemoveEntry>","DefaultState":"false"}]},"WPFToggleHideSettingsHome":{"name":"Settings Home Page","desc":"Toggles the Home Page in the Windows Settings app.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\Explorer","Name":"SettingsPageVisibility","Value":"show:home","Type":"String","OriginalValue":"hide:home","DefaultState":"true"}]},"WPFToggleBingSearch":{"name":"Start Menu Bing Search","desc":"Toggles Bing web search results in Windows Search.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search","Name":"BingSearchEnabled","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleLoginBlur":{"name":"Logon Screen Acrylic Blur","desc":"Toggles the acrylic blur effect on login screen background.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System","Name":"DisableAcrylicBackgroundOnLogon","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"}]},"WPFTweaksDisableLockscreen":{"name":"Lock Screen - Disable","desc":"Skips the lock screen entirely and goes directly to the sign-in screen on boot and wake.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Personalization","Name":"NoLockScreen","Value":"1","Type":"DWord","OriginalValue":"<RemoveEntry>"}]},"WPFToggleStartMenuRecommendations":{"name":"Start Menu Recommendations","desc":"Toggles the recommendations section in the Start Menu. WARNING: This will also disable Windows Spotlight on your Lock Screen as a side effect.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKLM:\\SOFTWARE\\Microsoft\\PolicyManager\\current\\device\\Start","Name":"HideRecommendedSection","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"},{"Path":"HKLM:\\SOFTWARE\\Microsoft\\PolicyManager\\current\\device\\Education","Name":"IsEducationEnvironment","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"},{"Path":"HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Explorer","Name":"HideRecommendedSection","Value":"0","Type":"DWord","OriginalValue":"1","DefaultState":"true"}],"apply":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "],"undo":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "]},"WPFToggleStickyKeys":{"name":"Sticky Keys","desc":"Toggles the Sticky Keys, which activate when clicking shift rapidly.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Control Panel\\Accessibility\\StickyKeys","Name":"Flags","Value":"506","Type":"DWord","OriginalValue":"58","DefaultState":"true"}]},"WPFToggleTaskbarAlignment":{"name":"Taskbar Centered Icons","desc":"Toggles the Taskbar alignment either to the left or center.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"TaskbarAl","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}],"apply":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "],"undo":["\n      Invoke-WinUtilExplorerUpdate -action \"restart\"\n      "]},"WPFToggleTaskbarSearch":{"name":"Taskbar Search Icon","desc":"Toggles the Search Button on the Taskbar.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Search","Name":"SearchboxTaskbarMode","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleTaskView":{"name":"Taskbar Task View Icon","desc":"Toggles the Task View Button in the Taskbar.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Advanced","Name":"ShowTaskViewButton","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleGameMode":{"name":"Game Mode","desc":"Toggles Windows prioritizes gaming performance by allocating system resources to games.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKCU:\\Software\\Microsoft\\GameBar","Name":"AllowAutoGameMode","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"},{"Path":"HKCU:\\Software\\Microsoft\\GameBar","Name":"AutoGameModeEnabled","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"true"}]},"WPFToggleLongPaths":{"name":"Enable Long Paths","desc":"Toggles support for file paths longer than 260 characters in Explorer.","cat":"Customize Preferences","type":"Toggle","registry":[{"Path":"HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem","Name":"LongPathsEnabled","Value":"1","Type":"DWord","OriginalValue":"0","DefaultState":"false"}]},"WPFOOSUbutton":{"name":"O&O ShutUp10++ - Run","desc":"","cat":"z__Advanced Tweaks - CAUTION","type":"Button"},"WPFAddUltPerf":{"name":"Ultimate Performance Profile - Enable","desc":"","cat":"Performance Plans - NOT FOR LAPTOPS","type":"Button"},"WPFRemoveUltPerf":{"name":"Ultimate Performance Profile - Disable","desc":"","cat":"Performance Plans - NOT FOR LAPTOPS","type":"Button"}}
'@

$Apps   = $AppsJson   | ConvertFrom-Json
$Tweaks = $TweaksJson | ConvertFrom-Json

# ---------------------------------------------------------------------------
# XAML - main window
# ---------------------------------------------------------------------------
[xml]$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Stackify" Height="880" Width="1320" WindowStartupLocation="CenterScreen"
        Background="#15161C" FontFamily="Segoe UI">
    <Window.Resources>
        <!-- NOTE: deliberately no custom TabControl.Template here. WPF's
             ContentSource="SelectedContent" (and TemplateBinding /
             RelativeSource=TemplatedParent bindings to it) is a
             compile-time-only XAML feature - it silently does nothing
             when XAML is loaded dynamically via XamlReader.Load, as this
             whole app does. An earlier custom TabControl template used it
             and every tab body silently rendered empty as a result (only
             the tab strip itself showed). The default TabControl template
             already places tab strip + content correctly, so only
             TabItem's own template (below) needs overriding to kill the
             white active-tab chrome. -->
        <Style TargetType="TabItem">
            <Setter Property="Padding" Value="18,10"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#8C8C98"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="3"/>
                            </Grid.RowDefinitions>
                            <Border x:Name="Bd" Grid.Row="0" Background="Transparent" CornerRadius="6,6,0,0"
                                    Padding="{TemplateBinding Padding}" Margin="0,0,4,0">
                                <ContentPresenter x:Name="Cp" ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <Border x:Name="Indicator" Grid.Row="1" Background="Transparent" Margin="14,0"/>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#20222C"/>
                                <Setter TargetName="Indicator" Property="Background" Value="#3D7BFF"/>
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <MultiTrigger>
                                <MultiTrigger.Conditions>
                                    <Condition Property="IsMouseOver" Value="True"/>
                                    <Condition Property="IsSelected" Value="False"/>
                                </MultiTrigger.Conditions>
                                <Setter TargetName="Bd" Property="Background" Value="#1E202B"/>
                                <Setter Property="Foreground" Value="#C7C7D1"/>
                            </MultiTrigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="CheckBox" x:Key="AppCheck">
            <Setter Property="Foreground" Value="#E4E4EC"/>
            <Setter Property="Margin" Value="0,5"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>
        <Style TargetType="CheckBox" x:Key="TweakCheck">
            <Setter Property="Foreground" Value="#E4E4EC"/>
            <Setter Property="Margin" Value="0,5"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Padding" Value="14,7"/>
            <Setter Property="Margin" Value="4"/>
            <Setter Property="Background" Value="#3D7BFF"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Background" Value="#20222C"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="BorderBrush" Value="#33354064"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="GroupBox">
            <Setter Property="Foreground" Value="#8FB2FF"/>
            <Setter Property="Margin" Value="0,4"/>
            <Setter Property="FontWeight" Value="Bold"/>
        </Style>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#E4E4EC"/>
        </Style>
        <Style TargetType="ProgressBar">
            <Setter Property="Height" Value="20"/>
            <Setter Property="Background" Value="#20222C"/>
            <Setter Property="Foreground" Value="#3D7BFF"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style x:Key="SectionHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="15"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="#41D6C3"/>
            <Setter Property="Margin" Value="2,14,0,8"/>
        </Style>

        <!-- Category filter "chip" button - a plain toggle-look Button so we
             can flip its Background/Foreground in code when active. -->
        <Style x:Key="CategoryChip" TargetType="Button">
            <Setter Property="Background" Value="#1B1D26"/>
            <Setter Property="Foreground" Value="#B8B8C2"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="0,0,6,6"/>
        </Style>

        <!-- Collapsible category section for the app list. -->
        <Style TargetType="Expander">
            <Setter Property="Foreground" Value="#41D6C3"/>
            <Setter Property="Margin" Value="0,6,0,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Expander">
                        <DockPanel>
                            <ToggleButton x:Name="Hdr" DockPanel.Dock="Top" Cursor="Hand"
                                          IsChecked="{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}}">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <StackPanel Orientation="Horizontal" Background="Transparent">
                                            <TextBlock x:Name="Arrow" Text="&#9662;" FontSize="11" Foreground="#41D6C3" Margin="0,0,6,0" VerticalAlignment="Center"/>
                                            <ContentPresenter VerticalAlignment="Center"/>
                                        </StackPanel>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsChecked" Value="False">
                                                <Setter TargetName="Arrow" Property="Text" Value="&#9656;"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                                <ContentPresenter ContentSource="Header" TextElement.Foreground="#41D6C3" TextElement.FontSize="15" TextElement.FontWeight="SemiBold"/>
                            </ToggleButton>
                            <ContentPresenter x:Name="ExpanderContent" Visibility="Collapsed"/>
                        </DockPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsExpanded" Value="True">
                                <Setter TargetName="ExpanderContent" Property="Visibility" Value="Visible"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Toggle-switch look for a CheckBox, used on the Tweaks tab's
             "Customize Preferences" list to mirror the reference UI. -->
        <Style x:Key="ToggleSwitch" TargetType="CheckBox">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="Track" Width="40" Height="21" CornerRadius="10.5" Background="#33354A">
                            <Border x:Name="Thumb" Width="17" Height="17" CornerRadius="8.5" Background="White"
                                    HorizontalAlignment="Left" Margin="2,0,0,0"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="Track" Property="Background" Value="#3D7BFF"/>
                                <Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="Thumb" Property="Margin" Value="0,0,2,0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Text="Stackify" FontSize="27" FontWeight="Bold" Foreground="#3D7BFF" Margin="4,0,0,10"/>

        <TabControl Grid.Row="1" Name="MainTabs" Background="#15161C" BorderThickness="0">

            <!-- INSTALL TAB -->
            <TabItem Header="Install">
                <Grid Margin="8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="220"/>
                        <ColumnDefinition Width="10"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <!-- Actions sidebar -->
                    <Border Grid.Column="0" Background="#1B1D26" CornerRadius="8" Padding="14">
                        <StackPanel>
                            <TextBlock Text="Actions" Style="{StaticResource SectionHeader}" Margin="0,0,0,8"/>
                            <Button Name="InstallSelectedBtn" Content="Install/Upgrade Applications" HorizontalAlignment="Stretch" Margin="0,3"/>
                            <Button Name="UninstallSelectedBtn" Content="Uninstall Applications" Background="#B24141" HorizontalAlignment="Stretch" Margin="0,3"/>
                            <Button Name="UpgradeAllBtn" Content="Upgrade all Applications" Background="#33354A" HorizontalAlignment="Stretch" Margin="0,3"/>

                            <TextBlock Text="Package Manager" Style="{StaticResource SectionHeader}"/>
                            <RadioButton Name="PkgWingetRadio" Content="WinGet" GroupName="PkgMgr" Foreground="#E4E4EC" IsChecked="True" Margin="2,4"/>
                            <RadioButton Name="PkgChocoRadio" Content="Chocolatey" GroupName="PkgMgr" Foreground="#E4E4EC" Margin="2,4"/>

                            <TextBlock Text="Selection" Style="{StaticResource SectionHeader}"/>
                            <Button Name="ClearAppSelectionBtn" Content="Clear Selection" Background="#33354A" HorizontalAlignment="Stretch" Margin="0,3"/>
                            <Button Name="CollapseAllBtn" Content="Collapse All Categories" Background="#33354A" HorizontalAlignment="Stretch" Margin="0,3"/>
                            <Button Name="ExpandAllBtn" Content="Expand All Categories" Background="#33354A" HorizontalAlignment="Stretch" Margin="0,3"/>
                            <TextBlock Name="AppSelectedCount" Text="Selected Apps: 0" Foreground="#8FB2FF" FontWeight="SemiBold" Margin="4,10,0,4"/>
                            <Button Name="ShowInstalledBtn" Content="Show Installed Apps" Background="#33354A" HorizontalAlignment="Stretch" Margin="0,3"/>
                        </StackPanel>
                    </Border>

                    <!-- App list -->
                    <DockPanel Grid.Column="2">
                        <StackPanel DockPanel.Dock="Top" Margin="0,0,0,10">
                            <WrapPanel Name="CategoryFilterPanel" Margin="0,0,0,8"/>
                            <TextBox Name="AppSearchBox" Width="340" HorizontalAlignment="Left"/>
                        </StackPanel>
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="AppsPanel"/>
                        </ScrollViewer>
                    </DockPanel>
                </Grid>
            </TabItem>

            <!-- TWEAKS TAB -->
            <TabItem Header="Tweaks">
                <DockPanel Margin="8">
                    <Border DockPanel.Dock="Top" Background="#1B1D26" CornerRadius="6" Padding="10" Margin="0,0,0,10">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Recommended Selections:" Foreground="#7C7C88" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,10,0"/>
                            <Button Name="PresetStandardBtn" Content="Standard"/>
                            <Button Name="PresetMinimalBtn" Content="Minimal" Background="#33354A"/>
                            <Button Name="PresetAdvancedBtn" Content="Advanced" Background="#B24141"/>
                            <Button Name="PresetClearBtn" Content="Clear" Background="#33354A"/>
                            <Button Name="GetInstalledTweaksBtn" Content="Get Installed Tweaks" Background="#33354A"/>
                            <Button Name="AppxRemovalBtn" Content="AppX Removal" Background="#33354A"/>
                            <TextBox Name="TweakSearchBox" Width="200" Margin="20,0,0,0"/>
                        </StackPanel>
                    </Border>
                    <Border DockPanel.Dock="Bottom" Background="#1B1D26" CornerRadius="6" Padding="10" Margin="0,10,0,0">
                        <StackPanel Orientation="Horizontal">
                            <Button Name="ApplyTweaksBtn" Content="Run Tweaks"/>
                            <Button Name="UndoTweaksBtn" Content="Undo Selected Tweaks" Background="#B24141"/>
                            <TextBlock Name="TweakSelectedCount" Text="0 selected" VerticalAlignment="Center" Margin="14,0" Foreground="#8FB2FF" FontWeight="SemiBold"/>
                        </StackPanel>
                    </Border>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="TweaksEssentialPanel" Margin="4,0"/>
                        </ScrollViewer>
                        <Border Grid.Column="1" Background="#26283340" Width="1" Margin="0,4"/>
                        <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto">
                            <StackPanel Name="TweaksPreferencesPanel" Margin="4,0"/>
                        </ScrollViewer>
                    </Grid>
                </DockPanel>
            </TabItem>

            <!-- UPDATES TAB -->
            <TabItem Header="Updates">
                <StackPanel Margin="10">
                    <TextBlock Text="Windows Update Profiles" FontSize="23" FontWeight="Bold" Margin="0,0,0,4"/>
                    <TextBlock Text="Choose how Windows receives updates. Each profile replaces the Windows Update settings managed by Stackify."
                               Foreground="#8C8C98" Margin="0,0,0,18" TextWrapping="Wrap"/>
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="14"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="14"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <Border Grid.Column="0" BorderBrush="#3ADE7A" BorderThickness="2" CornerRadius="8" Padding="18" Background="#1B1D26">
                            <StackPanel>
                                <TextBlock Text="Recommended" FontSize="18" FontWeight="Bold" Foreground="#3ADE7A"/>
                                <TextBlock Text="Balanced security and stability" Foreground="#8C8C98" Margin="0,2,0,14" TextWrapping="Wrap"/>
                                <TextBlock Text="- Defers feature updates for 365 days" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="- Defers quality updates for 4 days" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="- Excludes drivers from quality updates" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="- Prevents automatic restarts while a user is signed in" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="Available on Windows Pro, Enterprise, and Education editions."
                                           FontStyle="Italic" Foreground="#6E6E7A" Margin="0,12,0,0" TextWrapping="Wrap"/>
                                <Button Name="ApplyRecommendedBtn" Content="Apply Recommended" Margin="0,18,0,0" Background="#2E7D46"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Column="2" BorderBrush="#33354A" BorderThickness="1" CornerRadius="8" Padding="18" Background="#1B1D26">
                            <StackPanel>
                                <TextBlock Text="Windows Default" FontSize="18" FontWeight="Bold"/>
                                <TextBlock Text="Return control to Windows" Foreground="#8C8C98" Margin="0,2,0,14" TextWrapping="Wrap"/>
                                <TextBlock Text="- Removes Windows Update policies applied by Stackify" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="- Restores update service startup settings" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="- Re-enables update scheduled tasks" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="Use this to undo the Recommended or Disable profile."
                                           FontStyle="Italic" Foreground="#6E6E7A" Margin="0,12,0,0" TextWrapping="Wrap"/>
                                <Button Name="RestoreDefaultsBtn" Content="Restore Defaults" Margin="0,18,0,0" Background="#33354A"/>
                            </StackPanel>
                        </Border>

                        <Border Grid.Column="4" BorderBrush="#B24141" BorderThickness="1" CornerRadius="8" Padding="18" Background="#1B1D26">
                            <StackPanel>
                                <TextBlock Text="Disable Updates" FontSize="18" FontWeight="Bold" Foreground="#E5605E"/>
                                <TextBlock Text="Advanced use only" Foreground="#E5605E" Margin="0,2,0,14" TextWrapping="Wrap"/>
                                <TextBlock Text="- Disables automatic update policy" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="- Stops update services and scheduled tasks" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="- Clears downloaded update files" Margin="0,3" TextWrapping="Wrap"/>
                                <TextBlock Text="Security updates will not be installed while this profile is active."
                                           Foreground="#E5605E" Margin="0,12,0,0" TextWrapping="Wrap"/>
                                <Button Name="DisableUpdatesBtn" Content="Disable Updates" Margin="0,18,0,0" Background="#B24141"/>
                            </StackPanel>
                        </Border>
                    </Grid>

                    <Border BorderBrush="#26283A" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,18,0,0" Background="#1B1D26">
                        <TextBlock Text="Changes apply system-wide. Restart Windows after switching profiles. Use Restore Defaults to undo a Stackify update policy."
                                   Foreground="#8C8C98" HorizontalAlignment="Center" TextWrapping="Wrap"/>
                    </Border>

                    <Border Background="#1B1D26" CornerRadius="8" Padding="10" Margin="0,16,0,0">
                        <StackPanel Orientation="Horizontal">
                            <Button Name="CheckUpdatesBtn" Content="Check for Updates Now" Background="#33354A"/>
                            <Button Name="InstallUpdatesBtn" Content="Install All Updates" Background="#33354A"/>
                            <Button Name="OpenWUBtn" Content="Open Windows Update Settings" Background="#33354A"/>
                        </StackPanel>
                    </Border>
                    <TextBlock Name="UpdatesStatus" Margin="4,12,0,0" Foreground="#8FB2FF" TextWrapping="Wrap"/>
                </StackPanel>
            </TabItem>
        </TabControl>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($reader)
$Window.Add_SourceInitialized({
    $wndHwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
    [ConsoleHide.Win32]::ShowWindow($wndHwnd, 1) | Out-Null   # SW_SHOWNORMAL
    [ConsoleHide.Win32]::SetForegroundWindow($wndHwnd) | Out-Null
})

# Grab named controls
$ctrl = @{}
foreach ($name in @(
        'AppSearchBox','AppsPanel','CategoryFilterPanel','InstallSelectedBtn','UninstallSelectedBtn','ClearAppSelectionBtn','AppSelectedCount',
        'UpgradeAllBtn','PkgWingetRadio','PkgChocoRadio','CollapseAllBtn','ExpandAllBtn','ShowInstalledBtn',
        'TweakSearchBox','TweaksEssentialPanel','TweaksPreferencesPanel','ApplyTweaksBtn','UndoTweaksBtn','TweakSelectedCount',
        'PresetStandardBtn','PresetMinimalBtn','PresetAdvancedBtn','PresetClearBtn','GetInstalledTweaksBtn','AppxRemovalBtn',
        'ApplyRecommendedBtn','RestoreDefaultsBtn','DisableUpdatesBtn',
        'CheckUpdatesBtn','InstallUpdatesBtn','OpenWUBtn','UpdatesStatus')) {
    $ctrl[$name] = $Window.FindName($name)
}

# ---------------------------------------------------------------------------
# Inline help popover for the Tweaks tab's "?" icons - a single reusable,
# non-modal Popup placed right at the mouse cursor. Shows on hover, also
# toggles on click, and is never a separate dialog window.
# ---------------------------------------------------------------------------
$script:HelpPopupText = New-Object System.Windows.Controls.TextBlock
$script:HelpPopupText.TextWrapping = 'Wrap'
$script:HelpPopupText.Foreground = '#E4E4EC'
$script:HelpPopupText.FontSize = 12.5

$script:HelpPopupBorder = New-Object System.Windows.Controls.Border
$script:HelpPopupBorder.Background = '#20222C'
$script:HelpPopupBorder.BorderBrush = '#3D7BFF'
$script:HelpPopupBorder.BorderThickness = 1
$script:HelpPopupBorder.CornerRadius = 6
$script:HelpPopupBorder.Padding = 10
$script:HelpPopupBorder.MaxWidth = 300
$script:HelpPopupBorder.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 12; ShadowDepth = 2; Opacity = 0.5 }
$script:HelpPopupBorder.Child = $script:HelpPopupText

$script:HelpPopup = New-Object System.Windows.Controls.Primitives.Popup
$script:HelpPopup.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Mouse
$script:HelpPopup.HorizontalOffset = 12
$script:HelpPopup.VerticalOffset = 12
$script:HelpPopup.AllowsTransparency = $true
$script:HelpPopup.PopupAnimation = 'Fade'
$script:HelpPopup.StaysOpen = $true
$script:HelpPopup.Child = $script:HelpPopupBorder

function Show-HelpPopup {
    param($Target, [string]$Text)
    $script:HelpPopupText.Text = $Text
    $script:HelpPopup.PlacementTarget = $Target
    $script:HelpPopup.IsOpen = $true
}
function Hide-HelpPopup { $script:HelpPopup.IsOpen = $false }
function Toggle-HelpPopup {
    param($Target, [string]$Text)
    if ($script:HelpPopup.IsOpen -and $script:HelpPopup.PlacementTarget -eq $Target) {
        $script:HelpPopup.IsOpen = $false
    } else {
        Show-HelpPopup -Target $Target -Text $Text
    }
}

# ---------------------------------------------------------------------------
# Real app icons - fetched from each app's own website favicon (a small,
# genuine brand mark for that app) via Google's favicon service, cached to
# disk so repeat runs load instantly and offline. Falls back to a colored
# letter badge if a fetch fails or there's no network.
# ---------------------------------------------------------------------------
$IconCacheDir = Join-Path $env:LOCALAPPDATA 'Stackify\IconCache'
if (-not (Test-Path $IconCacheDir)) { New-Item -ItemType Directory -Path $IconCacheDir -Force | Out-Null }

$IconCache      = @{}                                            # icon key -> BitmapImage
$AppIconImages  = New-Object 'System.Collections.Generic.Dictionary[string,object]'   # app id -> Image control
$AppIconKeyById = @{}                                             # app id -> icon key
$QueuedIconKeys = New-Object 'System.Collections.Generic.HashSet[string]'

$BadgePalette = @('#E05353','#3ADE7A','#3A6FF7','#F2B84B','#B45AE0','#3AC7DE','#E0703A','#5AE0A8','#E05AC0','#8C9EFF')
function Get-BadgeColor { param([string]$Key)
    $hash = 0
    foreach ($c in $Key.ToCharArray()) { $hash = $hash + [int][char]$c }
    return $BadgePalette[$hash % $BadgePalette.Count]
}

# A handful of apps sit on a domain (e.g. google.com) whose favicon is the
# parent brand's mark, not the app's own - Chrome and Firefox both looked
# wrong/generic through the plain favicon lookup. These get a direct,
# official high-resolution logo URL instead.
$IconOverrides = @{
    'chrome'  = 'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e1/Google_Chrome_icon_%28February_2022%29.svg/250px-Google_Chrome_icon_%28February_2022%29.svg.png'
    'firefox' = 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a0/Firefox_logo%2C_2019.svg/250px-Firefox_logo%2C_2019.svg.png'
}

function Get-AppDomain { param([string]$Link)
    if ([string]::IsNullOrWhiteSpace($Link)) { return $null }
    try { return (([Uri]$Link).Host -replace '^www\.', '') } catch { return $null }
}

# The icon "key" identifies a unique icon to fetch/cache: an override'd app
# gets its own key (so it never shares a cached favicon with sibling apps
# on the same domain), everything else keys off its domain as before.
function Get-AppIconKey { param([string]$Id, [string]$Domain)
    if ($IconOverrides.ContainsKey($Id)) { return "app:$Id" }
    if ($Domain) { return "domain:$Domain" }
    return $null
}

function Get-IconDownloadUrl { param([string]$Key)
    if ($Key.StartsWith('app:')) {
        $appId = $Key.Substring(4)
        return $IconOverrides[$appId]
    }
    $domain = $Key.Substring(7)
    return "https://www.google.com/s2/favicons?sz=64&domain=$domain"
}

function Get-CachedIconFile { param([string]$Key)
    $safe = ($Key -replace '[^a-zA-Z0-9\.\-]', '_')
    return (Join-Path $IconCacheDir "$safe.png")
}

function ConvertTo-BitmapImage { param([byte[]]$Bytes)
    $ms = New-Object System.IO.MemoryStream(,$Bytes)
    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
    $bmp.BeginInit()
    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bmp.StreamSource = $ms
    $bmp.EndInit()
    $bmp.Freeze()
    return $bmp
}

# A neutral placeholder shown while the real icon is still loading.
function New-PlaceholderBitmap {
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(24, 24, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $visual = New-Object System.Windows.Media.DrawingVisual
    $dc = $visual.RenderOpen()
    $brush = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.Color]::FromArgb(255,42,44,56))
    $dc.DrawEllipse($brush, $null, (New-Object System.Windows.Point(12,12)), 12, 12)
    $dc.Close()
    $bmp.Render($visual)
    $bmp.Freeze()
    return $bmp
}
$script:PlaceholderIcon = New-PlaceholderBitmap

function New-AppIconImage {
    param([string]$Id, [string]$Key)
    $img = New-Object System.Windows.Controls.Image
    $img.Width = 22; $img.Height = 22
    $img.Stretch = 'Uniform'
    $img.Margin = '0,0,8,0'
    $img.Source = $script:PlaceholderIcon
    if ($Key -and $IconCache.ContainsKey($Key)) {
        $img.Source = $IconCache[$Key]
    }
    if ($Id) { $AppIconImages[$Id] = $img }
    return $img
}

function Set-IconOnImage { param($ImgControl, $BitmapImage)
    if ($ImgControl -and $BitmapImage) { $ImgControl.Source = $BitmapImage }
}

# Icon downloads happen on a small runspace pool - those background threads
# never touch a single WPF object. Results land in a thread-safe queue; a
# DispatcherTimer on the UI thread drains it and assigns bitmaps to the
# right Image controls. This two-sided split is what keeps it crash-safe:
# WPF objects are only ever touched from the UI thread.
$script:IconResultQueue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$script:IconRunspacePool = [runspacefactory]::CreateRunspacePool(1, 8)
$script:IconRunspacePool.Open()
$script:IconJobs = New-Object System.Collections.Generic.List[object]

function Start-IconDownloadsAsync {
    param([string[]]$Keys)
    foreach ($key in $Keys) {
        if (-not $key -or $QueuedIconKeys.Contains($key)) { continue }
        $QueuedIconKeys.Add($key) | Out-Null

        $cacheFile = Get-CachedIconFile -Key $key
        if (Test-Path $cacheFile) {
            try {
                $bytes = [IO.File]::ReadAllBytes($cacheFile)
                $script:IconResultQueue.Enqueue([pscustomobject]@{ Key = $key; Bytes = $bytes })
                continue
            } catch {}
        }

        $url = Get-IconDownloadUrl -Key $key
        if ([string]::IsNullOrWhiteSpace($url)) { continue }

        $ps = [powershell]::Create()
        $ps.RunspacePool = $script:IconRunspacePool
        [void]$ps.AddScript({
            param($Key, $Url, $Queue, $CacheFile)
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
                $bytes = $wc.DownloadData($Url)
                if ($bytes -and $bytes.Length -gt 0) {
                    try { [IO.File]::WriteAllBytes($CacheFile, $bytes) } catch {}
                    $Queue.Enqueue([pscustomobject]@{ Key = $Key; Bytes = $bytes })
                }
            } catch {}
        }).AddArgument($key).AddArgument($url).AddArgument($script:IconResultQueue).AddArgument($cacheFile)
        $handle = $ps.BeginInvoke()
        $script:IconJobs.Add(@{ PS = $ps; Handle = $handle }) | Out-Null
    }
}

function Start-IconResultTimer {
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(150)
    $timer.Add_Tick({
        $item = $null
        $drained = 0
        while ($drained -lt 25 -and $script:IconResultQueue.TryDequeue([ref]$item)) {
            $drained++
            try {
                $bmp = ConvertTo-BitmapImage -Bytes $item.Bytes
                $IconCache[$item.Key] = $bmp
                foreach ($kv in $AppIconKeyById.GetEnumerator()) {
                    if ($kv.Value -eq $item.Key -and $AppIconImages.ContainsKey($kv.Key)) {
                        Set-IconOnImage -ImgControl $AppIconImages[$kv.Key] -BitmapImage $bmp
                    }
                }
            } catch {}
        }
        for ($i = $script:IconJobs.Count - 1; $i -ge 0; $i--) {
            $job = $script:IconJobs[$i]
            if ($job.Handle.IsCompleted) {
                try { $job.PS.EndInvoke($job.Handle) | Out-Null } catch {}
                $job.PS.Dispose()
                $script:IconJobs.RemoveAt($i)
            }
        }
    })
    $timer.Start()
    return $timer
}

# ---------------------------------------------------------------------------
# Build the Install tab checkboxes, grouped by category
# ---------------------------------------------------------------------------
$AppCheckboxes = @{}
$appsByCategory = @{}
foreach ($prop in $Apps.PSObject.Properties) {
    $id  = $prop.Name
    $app = $prop.Value
    if (-not $appsByCategory.ContainsKey($app.cat)) { $appsByCategory[$app.cat] = New-Object System.Collections.Generic.List[object] }
    $appsByCategory[$app.cat].Add(@{ id = $id; app = $app })
    $AppIconKeyById[$id] = Get-AppIconKey -Id $id -Domain (Get-AppDomain -Link $app.link)
}

function New-AppRow {
    param($Id, $App)
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.Children.Add((New-AppIconImage -Id $Id -Key $AppIconKeyById[$Id])) | Out-Null
    $nameTb = New-Object System.Windows.Controls.TextBlock
    $nameTb.Text = $App.name
    $nameTb.VerticalAlignment = 'Center'
    $row.Children.Add($nameTb) | Out-Null
    return $row
}

$script:ActiveCategory = 'All'
$script:ShowInstalledOnly = $false
$script:InstalledWingetIds = $null
$script:CategoryChipButtons = @{}
# Every checkbox and its Expander are built exactly once at startup; a
# search keystroke or filter change never recreates WPF controls again -
# it only flips Visibility on the already-built rows. Rebuilding ~230
# checkboxes (with icons, tooltips, event bindings) on every keystroke was
# the actual source of the search lag.
$script:AppCategoryInfo = New-Object System.Collections.Generic.List[object]  # {cat, expander, rows:[{id,app,checkbox}]}

function Build-AppsPanelOnce {
    $ctrl.AppsPanel.Children.Clear()
    $script:AppCategoryInfo.Clear()
    $iconKeysNeeded = New-Object System.Collections.Generic.List[string]

    foreach ($cat in ($appsByCategory.Keys | Sort-Object)) {
        $expander = New-Object System.Windows.Controls.Expander
        $expander.IsExpanded = $true

        $wrap = New-Object System.Windows.Controls.WrapPanel
        $wrap.Margin = '20,4,0,0'
        $rows = New-Object System.Collections.Generic.List[object]

        foreach ($it in $appsByCategory[$cat]) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Style = $Window.FindResource('AppCheck')
            $cb.Content = New-AppRow -Id $it.id -App $it.app
            $cb.Width = 270
            $cb.ToolTip = $it.app.desc
            $cb.Tag = $it.id
            $cb.Add_Checked({ Update-AppCount })
            $cb.Add_Unchecked({ Update-AppCount })
            $AppCheckboxes[$it.id] = $cb
            $wrap.Children.Add($cb) | Out-Null
            $rows.Add(@{ id = $it.id; app = $it.app; checkbox = $cb }) | Out-Null
            if ($AppIconKeyById[$it.id]) { $iconKeysNeeded.Add($AppIconKeyById[$it.id]) }
        }
        $expander.Content = $wrap
        $ctrl.AppsPanel.Children.Add($expander) | Out-Null
        $script:AppCategoryInfo.Add(@{ cat = $cat; expander = $expander; rows = $rows }) | Out-Null
    }
    Start-IconDownloadsAsync -Keys $iconKeysNeeded
}

# Cheap filter pass: no controls are created or destroyed here, only
# Visibility flags and header text - this is what runs on every keystroke.
function Apply-AppsFilter {
    param([string]$Filter = '')
    foreach ($entry in $script:AppCategoryInfo) {
        $categoryActive = $script:ActiveCategory -eq 'All' -or $entry.cat -eq $script:ActiveCategory
        $visibleCount = 0
        if ($categoryActive) {
            foreach ($row in $entry.rows) {
                $matchesFilter = [string]::IsNullOrWhiteSpace($Filter) -or
                    $row.app.name.ToLower().Contains($Filter) -or
                    $row.app.desc.ToLower().Contains($Filter)
                $matchesInstalled = -not $script:ShowInstalledOnly -or
                    ($script:InstalledWingetIds -and $script:InstalledWingetIds.Contains($row.app.winget))
                $show = $matchesFilter -and $matchesInstalled
                $row.checkbox.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
                if ($show) { $visibleCount++ }
            }
        } else {
            foreach ($row in $entry.rows) { $row.checkbox.Visibility = 'Collapsed' }
        }
        $entry.expander.Visibility = if ($visibleCount -gt 0) { 'Visible' } else { 'Collapsed' }
        $entry.expander.Header = "$($entry.cat) ($visibleCount)"
    }
}

function Update-AppCount {
    $n = ($AppCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $ctrl.AppSelectedCount.Text = "Selected Apps: $n"
}

function Set-ActiveCategoryChip {
    param([string]$Category)
    $script:ActiveCategory = $Category
    foreach ($kv in $script:CategoryChipButtons.GetEnumerator()) {
        if ($kv.Key -eq $Category) {
            $kv.Value.Background = '#3D7BFF'
            $kv.Value.Foreground = 'White'
        } else {
            $kv.Value.Background = '#1B1D26'
            $kv.Value.Foreground = '#B8B8C2'
        }
    }
    Apply-AppsFilter -Filter $ctrl.AppSearchBox.Text.ToLower()
}

function Build-CategoryFilterChips {
    $ctrl.CategoryFilterPanel.Children.Clear()
    $script:CategoryChipButtons.Clear()
    $allCats = @('All') + ($appsByCategory.Keys | Sort-Object)
    foreach ($cat in $allCats) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Style = $Window.FindResource('CategoryChip')
        $btn.Content = $cat
        if ($cat -eq $script:ActiveCategory) { $btn.Background = '#3D7BFF'; $btn.Foreground = 'White' }
        $capturedCat = $cat
        $btn.Add_Click({ Set-ActiveCategoryChip -Category $capturedCat }.GetNewClosure())
        $script:CategoryChipButtons[$cat] = $btn
        $ctrl.CategoryFilterPanel.Children.Add($btn) | Out-Null
    }
}

Build-CategoryFilterChips
$script:IconTimer = Start-IconResultTimer
Build-AppsPanelOnce
Apply-AppsFilter

# Debounced search: typing restarts a short timer instead of filtering on
# every single keystroke, so a fast typist never triggers more than one
# filter pass every ~150ms.
$script:AppSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:AppSearchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:AppSearchTimer.Add_Tick({
    $script:AppSearchTimer.Stop()
    Apply-AppsFilter -Filter $ctrl.AppSearchBox.Text.ToLower()
})
$ctrl.AppSearchBox.Add_TextChanged({
    $script:AppSearchTimer.Stop()
    $script:AppSearchTimer.Start()
})

$ctrl.ClearAppSelectionBtn.Add_Click({
    foreach ($cb in $AppCheckboxes.Values) { $cb.IsChecked = $false }
    Update-AppCount
})
$ctrl.CollapseAllBtn.Add_Click({ foreach ($entry in $script:AppCategoryInfo) { $entry.expander.IsExpanded = $false } })
$ctrl.ExpandAllBtn.Add_Click({ foreach ($entry in $script:AppCategoryInfo) { $entry.expander.IsExpanded = $true } })

$ctrl.ShowInstalledBtn.Add_Click({
    if (-not $script:ShowInstalledOnly) {
        $ctrl.ShowInstalledBtn.Content = 'Checking installed apps...'
        [System.Windows.Forms.Application]::DoEvents()
        if (-not $script:InstalledWingetIds) {
            $script:InstalledWingetIds = New-Object 'System.Collections.Generic.HashSet[string]'
            try {
                $listOut = (Invoke-WingetSilently -ArgList @('list', '--accept-source-agreements')).Output
                foreach ($appProp in $Apps.PSObject.Properties) {
                    if ($listOut -match [Regex]::Escape($appProp.Value.winget)) {
                        $script:InstalledWingetIds.Add($appProp.Value.winget) | Out-Null
                    }
                }
            } catch {}
        }
        $script:ShowInstalledOnly = $true
        $ctrl.ShowInstalledBtn.Content = 'Show All Apps'
    } else {
        $script:ShowInstalledOnly = $false
        $ctrl.ShowInstalledBtn.Content = 'Show Installed Apps'
    }
    Apply-AppsFilter -Filter $ctrl.AppSearchBox.Text.ToLower()
})

$ctrl.UpgradeAllBtn.Add_Click({
    $useChoco = $ctrl.PkgChocoRadio.IsChecked
    $pw = New-ProgressWindow -Title 'Stackify - Upgrade all Applications' -Max 1
    $pw.Status.Text = "Upgrading all applications via $(if($useChoco){'Chocolatey'}else{'WinGet'})..."
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $result = if ($useChoco) {
            Invoke-ChocoSilently -ArgList @('upgrade', 'all', '-y')
        } else {
            Invoke-WingetSilently -ArgList @('upgrade', '--all', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
        }
        $pw.Log.AppendText($result.Output)
    } catch {
        $pw.Log.AppendText("ERROR: $($_.Exception.Message)`r`n")
    }
    $pw.Bar.Value = 1
    $pw.Status.Text = 'Done.'
})

# ---------------------------------------------------------------------------
# Build the Tweaks tab: Essential + Advanced (left column, checkboxes) and
# Customize Preferences (right column, toggle switches).
# ---------------------------------------------------------------------------
$TweakCheckboxes = @{}
$tweaksByCategory = @{}
foreach ($prop in $Tweaks.PSObject.Properties) {
    $id = $prop.Name
    $tw = $prop.Value
    if (-not $tweaksByCategory.ContainsKey($tw.cat)) { $tweaksByCategory[$tw.cat] = New-Object System.Collections.Generic.List[object] }
    $tweaksByCategory[$tw.cat].Add(@{ id = $id; tw = $tw })
}

function New-TweakCheckboxRow {
    param($Id, $Tw)
    $wrap = New-Object System.Windows.Controls.StackPanel
    $wrap.Orientation = 'Horizontal'
    $cb = New-Object System.Windows.Controls.CheckBox
    $cb.Style = $Window.FindResource('TweakCheck')
    $cb.Content = $Tw.name
    $cb.ToolTip = $Tw.desc
    $cb.Tag = $Id
    $cb.Add_Checked({ Update-TweakCount })
    $cb.Add_Unchecked({ Update-TweakCount })
    $TweakCheckboxes[$Id] = $cb
    $wrap.Children.Add($cb) | Out-Null

    $help = New-Object System.Windows.Controls.Border
    $help.Width = 15; $help.Height = 15; $help.CornerRadius = 8
    $help.Background = '#26283A'
    $help.Margin = '4,0,0,0'
    $help.Cursor = 'Help'
    $helpTb = New-Object System.Windows.Controls.TextBlock
    $helpTb.Text = '?'; $helpTb.FontSize = 9; $helpTb.FontWeight = 'Bold'
    $helpTb.Foreground = '#41D6C3'; $helpTb.HorizontalAlignment = 'Center'; $helpTb.VerticalAlignment = 'Center'
    $help.Child = $helpTb

    $desc = $Tw.desc
    $help.Add_MouseEnter({ Show-HelpPopup -Target $help -Text $desc }.GetNewClosure())
    $help.Add_MouseLeave({ Hide-HelpPopup }.GetNewClosure())
    $help.Add_MouseLeftButtonDown({ Toggle-HelpPopup -Target $help -Text $desc }.GetNewClosure())

    $wrap.Children.Add($help) | Out-Null
    return $wrap
}

function New-TweakToggleRow {
    param($Id, $Tw)
    $row = New-Object System.Windows.Controls.DockPanel
    $row.Margin = '2,6'
    $labelStack = New-Object System.Windows.Controls.StackPanel
    $labelStack.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($labelStack, 'Left')
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = $Tw.name
    $label.ToolTip = $Tw.desc
    $label.VerticalAlignment = 'Center'
    $label.FontSize = 13
    $labelStack.Children.Add($label) | Out-Null

    $toggle = New-Object System.Windows.Controls.CheckBox
    $toggle.Style = $Window.FindResource('ToggleSwitch')
    $toggle.HorizontalAlignment = 'Right'
    $toggle.VerticalAlignment = 'Center'
    $toggle.Tag = $Id
    $toggle.Add_Checked({ Update-TweakCount })
    $toggle.Add_Unchecked({ Update-TweakCount })
    $TweakCheckboxes[$Id] = $toggle
    $row.Children.Add($labelStack) | Out-Null
    $row.Children.Add($toggle) | Out-Null
    return $row
}

# Same fix as the Install tab: every row is built exactly once, and a
# search keystroke only flips Visibility - it never recreates controls.
$script:TweakSectionInfo = New-Object System.Collections.Generic.List[object]  # {header, rows:[{id,tw,row}]}

function Build-TweaksPanelOnce {
    $ctrl.TweaksEssentialPanel.Children.Clear()
    $ctrl.TweaksPreferencesPanel.Children.Clear()
    $TweakCheckboxes.Clear()
    $script:TweakSectionInfo.Clear()

    foreach ($cat in @('Essential Tweaks', 'z__Advanced Tweaks - CAUTION', 'Performance Plans - NOT FOR LAPTOPS')) {
        if (-not $tweaksByCategory.ContainsKey($cat)) { continue }
        $label = $cat -replace '^z__', '' -replace ' - NOT FOR LAPTOPS', ''
        $header = New-Object System.Windows.Controls.TextBlock
        $header.Text = $label
        $header.Style = $Window.FindResource('SectionHeader')
        if ($cat -like 'z__*') { $header.Foreground = '#FF9466' }
        $ctrl.TweaksEssentialPanel.Children.Add($header) | Out-Null

        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($it in $tweaksByCategory[$cat]) {
            $row = New-TweakCheckboxRow -Id $it.id -Tw $it.tw
            $ctrl.TweaksEssentialPanel.Children.Add($row) | Out-Null
            $rows.Add(@{ id = $it.id; tw = $it.tw; row = $row }) | Out-Null
        }
        $script:TweakSectionInfo.Add(@{ header = $header; rows = $rows }) | Out-Null
    }

    if ($tweaksByCategory.ContainsKey('Customize Preferences')) {
        $header = New-Object System.Windows.Controls.TextBlock
        $header.Text = 'Customize Preferences'
        $header.Style = $Window.FindResource('SectionHeader')
        $ctrl.TweaksPreferencesPanel.Children.Add($header) | Out-Null

        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($it in $tweaksByCategory['Customize Preferences']) {
            $row = New-TweakToggleRow -Id $it.id -Tw $it.tw
            $ctrl.TweaksPreferencesPanel.Children.Add($row) | Out-Null
            $rows.Add(@{ id = $it.id; tw = $it.tw; row = $row }) | Out-Null
        }
        $script:TweakSectionInfo.Add(@{ header = $header; rows = $rows }) | Out-Null
    }
}

function Apply-TweaksFilter {
    param([string]$Filter = '')
    foreach ($section in $script:TweakSectionInfo) {
        $visibleCount = 0
        foreach ($r in $section.rows) {
            $show = [string]::IsNullOrWhiteSpace($Filter) -or
                $r.tw.name.ToLower().Contains($Filter) -or
                $r.tw.desc.ToLower().Contains($Filter)
            $r.row.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
            if ($show) { $visibleCount++ }
        }
        $section.header.Visibility = if ($visibleCount -gt 0) { 'Visible' } else { 'Collapsed' }
    }
}

function Update-TweakCount {
    $n = ($TweakCheckboxes.Values | Where-Object { $_.IsChecked }).Count
    $ctrl.TweakSelectedCount.Text = "$n selected"
}

Build-TweaksPanelOnce
Apply-TweaksFilter

$script:TweakSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:TweakSearchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:TweakSearchTimer.Add_Tick({
    $script:TweakSearchTimer.Stop()
    Apply-TweaksFilter -Filter $ctrl.TweakSearchBox.Text.ToLower()
})
$ctrl.TweakSearchBox.Add_TextChanged({
    $script:TweakSearchTimer.Stop()
    $script:TweakSearchTimer.Start()
})

# Preset selections
$MinimalTweakIds = @('WPFTweaksConsumerFeatures','WPFTweaksTelemetry','WPFTweaksDeliveryOptimization',
    'WPFTweaksDiskCleanup','WPFTweaksDeleteTempFiles','WPFTweaksWidget','WPFTweaksLocation','WPFTweaksActivity')

function Select-TweakPreset {
    param([string[]]$Ids)
    foreach ($kv in $TweakCheckboxes.GetEnumerator()) { $kv.Value.IsChecked = $false }
    foreach ($id in $Ids) { if ($TweakCheckboxes.ContainsKey($id)) { $TweakCheckboxes[$id].IsChecked = $true } }
    Update-TweakCount
}

$ctrl.PresetMinimalBtn.Add_Click({ Select-TweakPreset -Ids $MinimalTweakIds })
$ctrl.PresetStandardBtn.Add_Click({
    $ids = $tweaksByCategory['Essential Tweaks'] | ForEach-Object { $_.id }
    Select-TweakPreset -Ids $ids
})
$ctrl.PresetAdvancedBtn.Add_Click({
    $ids = @()
    if ($tweaksByCategory.ContainsKey('Essential Tweaks')) { $ids += $tweaksByCategory['Essential Tweaks'] | ForEach-Object { $_.id } }
    if ($tweaksByCategory.ContainsKey('z__Advanced Tweaks - CAUTION')) { $ids += $tweaksByCategory['z__Advanced Tweaks - CAUTION'] | ForEach-Object { $_.id } }
    Select-TweakPreset -Ids $ids
})
$ctrl.PresetClearBtn.Add_Click({ Select-TweakPreset -Ids @() })

# "Get Installed Tweaks" - checks each tweak's registry state against the
# desired value and pre-selects the ones already applied on this machine.
function Test-TweakApplied {
    param($Tw)
    if (-not $Tw.registry -or $Tw.registry.Count -eq 0) { return $false }
    foreach ($r in $Tw.registry) {
        if ($r.Value -eq '<RemoveEntry>') {
            $cur = Get-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue
            if ($cur) { return $false }
        } else {
            $curProp = Get-ItemProperty -Path $r.Path -Name $r.Name -ErrorAction SilentlyContinue
            if (-not $curProp) { return $false }
            if ("$($curProp.$($r.Name))" -ne "$($r.Value)") { return $false }
        }
    }
    return $true
}

$ctrl.GetInstalledTweaksBtn.Add_Click({
    foreach ($kv in $TweakCheckboxes.GetEnumerator()) {
        $tw = $Tweaks.($kv.Key)
        try { $kv.Value.IsChecked = (Test-TweakApplied -Tw $tw) } catch { $kv.Value.IsChecked = $false }
    }
    Update-TweakCount
})

# "AppX Removal" - a small companion window listing installed AppX
# packages with a Remove Selected action.
$ctrl.AppxRemovalBtn.Add_Click({
    $w = New-Object System.Windows.Window
    $w.Title = 'Stackify - AppX Removal'
    $w.Width = 620; $w.Height = 620
    $w.Background = '#15161C'
    $w.WindowStartupLocation = 'CenterOwner'
    $w.Owner = $Window

    $dock = New-Object System.Windows.Controls.DockPanel
    $dock.Margin = 10

    $top = New-Object System.Windows.Controls.StackPanel
    $top.Orientation = 'Horizontal'
    [System.Windows.Controls.DockPanel]::SetDock($top, 'Top')
    $removeBtn = New-Object System.Windows.Controls.Button
    $removeBtn.Content = 'Remove Selected'
    $removeBtn.Padding = '14,7'; $removeBtn.Margin = 4; $removeBtn.Background = '#B24141'; $removeBtn.Foreground = 'White'
    $countTb = New-Object System.Windows.Controls.TextBlock
    $countTb.Margin = '10,0'; $countTb.VerticalAlignment = 'Center'; $countTb.Foreground = '#8FB2FF'
    $top.Children.Add($removeBtn) | Out-Null
    $top.Children.Add($countTb) | Out-Null

    $scroll = New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility = 'Auto'
    $listPanel = New-Object System.Windows.Controls.StackPanel
    $scroll.Content = $listPanel

    $dock.Children.Add($top) | Out-Null
    $dock.Children.Add($scroll) | Out-Null
    $w.Content = $dock

    $pkgCheckboxes = @{}
    try {
        $packages = Get-AppxPackage | Sort-Object Name -Unique
        foreach ($p in $packages) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = $p.Name
            $cb.Foreground = '#E4E4EC'
            $cb.Margin = '2,4'
            $cb.Tag = $p.PackageFullName
            $pkgCheckboxes[$p.PackageFullName] = $cb
            $listPanel.Children.Add($cb) | Out-Null
        }
        $countTb.Text = "$($packages.Count) packages installed"
    } catch {
        $countTb.Text = "Could not list AppX packages: $($_.Exception.Message)"
    }

    $removeBtn.Add_Click({
        $selected = $pkgCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key }
        if ($selected.Count -eq 0) { return }
        foreach ($full in $selected) {
            try { Remove-AppxPackage -Package $full -ErrorAction SilentlyContinue } catch {}
            if ($pkgCheckboxes[$full]) { $pkgCheckboxes[$full].IsEnabled = $false; $pkgCheckboxes[$full].Content = "$($pkgCheckboxes[$full].Content)  (removed)" }
        }
    })

    $w.ShowDialog() | Out-Null
})

# ---------------------------------------------------------------------------
# Shared: a small progress window with a determinate bar
# ---------------------------------------------------------------------------
function New-ProgressWindow {
    param([string]$Title, [int]$Max)
    $w = New-Object System.Windows.Window
    $w.Title = $Title
    $w.Width = 640; $w.Height = 480
    $w.Background = '#15161C'
    $w.WindowStartupLocation = 'CenterOwner'
    $w.Owner = $Window

    $dock = New-Object System.Windows.Controls.DockPanel
    $dock.Margin = 10

    $statusTb = New-Object System.Windows.Controls.TextBlock
    $statusTb.Foreground = '#8FB2FF'; $statusTb.Margin = '0,0,0,6'; $statusTb.FontWeight = 'SemiBold'
    [System.Windows.Controls.DockPanel]::SetDock($statusTb, 'Top')

    $bar = New-Object System.Windows.Controls.ProgressBar
    $bar.Minimum = 0; $bar.Maximum = [Math]::Max($Max, 1); $bar.Value = 0
    $bar.Height = 20; $bar.Margin = '0,0,0,10'
    $bar.Background = '#20222C'; $bar.Foreground = '#3D7BFF'
    [System.Windows.Controls.DockPanel]::SetDock($bar, 'Top')

    $box = New-Object System.Windows.Controls.TextBox
    $box.IsReadOnly = $true; $box.AcceptsReturn = $true; $box.TextWrapping = 'Wrap'
    $box.VerticalScrollBarVisibility = 'Auto'; $box.FontFamily = 'Consolas'
    $box.Background = '#0F1014'; $box.Foreground = '#B8FFB8'
    $box.BorderThickness = 0

    $dock.Children.Add($statusTb) | Out-Null
    $dock.Children.Add($bar) | Out-Null
    $dock.Children.Add($box) | Out-Null
    $w.Content = $dock
    $w.Show()
    [System.Windows.Forms.Application]::DoEvents()

    return @{ Window = $w; Bar = $bar; Status = $statusTb; Log = $box }
}

# ---------------------------------------------------------------------------
# Install / Uninstall via winget - fully silent (hidden child process
# window, no installer UI), with a determinate progress bar.
# ---------------------------------------------------------------------------
function Test-Winget {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}
function Test-Choco {
    return [bool](Get-Command choco -ErrorAction SilentlyContinue)
}

function Invoke-ProcessSilently {
    param([string]$FileName, [string[]]$ArgList)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = ($ArgList -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = 'Hidden'
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Output = "$out`r`n$err"; ExitCode = $p.ExitCode }
}
function Invoke-WingetSilently { param([string[]]$ArgList) Invoke-ProcessSilently -FileName 'winget' -ArgList $ArgList }
function Invoke-ChocoSilently  { param([string[]]$ArgList) Invoke-ProcessSilently -FileName 'choco'  -ArgList $ArgList }

function Run-WingetJob {
    param([string[]]$Ids, [switch]$Uninstall)

    $useChoco = $ctrl.PkgChocoRadio.IsChecked

    if ($useChoco -and -not (Test-Choco)) {
        [System.Windows.MessageBox]::Show('Chocolatey (choco) was not found on this system. Install it from chocolatey.org, or switch the Package Manager back to WinGet.', 'Stackify', 'OK', 'Error') | Out-Null
        return
    }
    if (-not $useChoco -and -not (Test-Winget)) {
        [System.Windows.MessageBox]::Show('winget was not found on this system. Install "App Installer" from the Microsoft Store, then try again.', 'Stackify', 'OK', 'Error') | Out-Null
        return
    }
    if ($Ids.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one app first.', 'Stackify', 'OK', 'Information') | Out-Null
        return
    }

    $verb = if ($Uninstall) { 'Uninstalling' } else { 'Installing' }
    $pw = New-ProgressWindow -Title "Stackify - $verb" -Max $Ids.Count
    $done = 0
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($id in $Ids) {
        $appDef = $Apps.$id
        $pkgId = if ($useChoco) { $appDef.choco } else { $appDef.winget }
        if ($useChoco -and [string]::IsNullOrWhiteSpace($pkgId)) {
            $pw.Log.AppendText("`r`n=== Skipping $($appDef.name) - no Chocolatey package known ===`r`n")
            $failed.Add($appDef.name) | Out-Null
            $done++; $pw.Bar.Value = $done
            continue
        }
        $pw.Status.Text = "$verb $($appDef.name) ($($done + 1) of $($Ids.Count))..."
        $pw.Log.AppendText("`r`n=== $verb $($appDef.name) ($pkgId via $(if($useChoco){'Chocolatey'}else{'WinGet'})) ===`r`n")
        $pw.Log.ScrollToEnd()
        [System.Windows.Forms.Application]::DoEvents()

        try {
            if ($useChoco) {
                # Chocolatey exit code 0 = success, 1641/3010 = success + reboot needed.
                $args = if ($Uninstall) { @('uninstall', $pkgId, '-y') } else { @('install', $pkgId, '-y', '--no-progress') }
                $result = Invoke-ChocoSilently -ArgList $args
                $ok = $result.ExitCode -in @(0, 1641, 3010)
            } else {
                # Deliberately no --scope argument: forcing --scope machine breaks
                # any package whose manifest only declares a user-scope installer
                # (very common - Proton Mail, Discord, Spotify, most Electron
                # apps), since winget has no machine-scope installer to fall
                # back to for those and the install just silently fails.
                # Letting winget pick the scope itself (its normal default
                # behavior) matches what a plain `winget install <id>` does.
                $args = if ($Uninstall) {
                    @('uninstall', '--id', $pkgId, '-e', '--silent', '--disable-interactivity', '--accept-source-agreements')
                } else {
                    @('install', '--id', $pkgId, '-e', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
                }
                $result = Invoke-WingetSilently -ArgList $args
                # winget: 0 = success, -1978335189 (0x8A15002B) = already installed (uninstall-time no-op is fine).
                $ok = $result.ExitCode -eq 0 -or ($Uninstall -and $result.ExitCode -eq -1978335212)
            }
            $pw.Log.AppendText($result.Output)
            if ($ok) {
                $pw.Log.AppendText("`r`n--- OK ($($appDef.name)) ---`r`n")
            } else {
                $pw.Log.AppendText("`r`n--- FAILED ($($appDef.name), exit code $($result.ExitCode)) ---`r`n")
                $failed.Add($appDef.name) | Out-Null
            }
        } catch {
            $pw.Log.AppendText("ERROR: $($_.Exception.Message)`r`n")
            $failed.Add($appDef.name) | Out-Null
        }
        $done++
        $pw.Bar.Value = $done
        $pw.Log.ScrollToEnd()
        [System.Windows.Forms.Application]::DoEvents()
    }

    if ($failed.Count -eq 0) {
        $pw.Status.Text = "Done - all $done succeeded."
    } else {
        $pw.Status.Text = "Done - $($done - $failed.Count) of $done succeeded, $($failed.Count) failed."
    }
    $pw.Log.AppendText("`r`n=== Done ===`r`n")
    if ($failed.Count -gt 0) {
        $pw.Log.AppendText("Failed: $($failed -join ', ')`r`n")
    }
}

$ctrl.InstallSelectedBtn.Add_Click({
    $ids = $AppCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key }
    Run-WingetJob -Ids $ids
})
$ctrl.UninstallSelectedBtn.Add_Click({
    $ids = $AppCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key }
    Run-WingetJob -Ids $ids -Uninstall
})

# ---------------------------------------------------------------------------
# Apply / Undo tweaks
# ---------------------------------------------------------------------------
function Set-RegistryValue {
    param($Path, $Name, $Value, $Type)
    if ($Value -eq '<RemoveEntry>') {
        Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        return
    }
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    $propType = switch ($Type) {
        'DWord'  { 'DWord' }
        'QWord'  { 'QWord' }
        'String' { 'String' }
        default  { 'String' }
    }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $propType -Force | Out-Null
}

function Invoke-Tweak {
    param($TweakId, [switch]$Undo, $OutBox)

    $tw = $Tweaks.$TweakId
    $OutBox.AppendText("`r`n=== $(if($Undo){'Undoing'}else{'Applying'}) $($tw.name) ===`r`n")

    if (-not $Undo) {
        if ($tw.registry) {
            foreach ($r in $tw.registry) {
                try { Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.Value -Type $r.Type }
                catch { $OutBox.AppendText("  registry warn: $($_.Exception.Message)`r`n") }
            }
        }
        if ($tw.service) {
            foreach ($s in $tw.service) {
                try { Set-Service -Name $s.Name -StartupType $s.StartupType -ErrorAction SilentlyContinue } catch {}
            }
        }
        if ($tw.apply) {
            foreach ($block in $tw.apply) {
                try {
                    $sb = [ScriptBlock]::Create($block)
                    Invoke-Command -ScriptBlock $sb | Out-Null
                } catch { $OutBox.AppendText("  script warn: $($_.Exception.Message)`r`n") }
            }
        }
    } else {
        if ($tw.registry) {
            foreach ($r in $tw.registry) {
                try { Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.OriginalValue -Type $r.Type }
                catch { $OutBox.AppendText("  registry warn: $($_.Exception.Message)`r`n") }
            }
        }
        if ($tw.undo) {
            foreach ($block in $tw.undo) {
                try {
                    $sb = [ScriptBlock]::Create($block)
                    Invoke-Command -ScriptBlock $sb | Out-Null
                } catch { $OutBox.AppendText("  script warn: $($_.Exception.Message)`r`n") }
            }
        }
    }
    $OutBox.ScrollToEnd()
    [System.Windows.Forms.Application]::DoEvents()
}

function Run-TweaksJob {
    param([string[]]$Ids, [switch]$Undo)
    if ($Ids.Count -eq 0) {
        [System.Windows.MessageBox]::Show('Select at least one tweak first.', 'Stackify', 'OK', 'Information') | Out-Null
        return
    }
    $pw = New-ProgressWindow -Title "Stackify - $(if($Undo){'Undo'}else{'Apply'}) Tweaks" -Max $Ids.Count
    $done = 0
    foreach ($id in $Ids) {
        $pw.Status.Text = "$(if($Undo){'Undoing'}else{'Applying'}) $($Tweaks.$id.name) ($($done + 1) of $($Ids.Count))..."
        Invoke-Tweak -TweakId $id -Undo:$Undo -OutBox $pw.Log
        $done++
        $pw.Bar.Value = $done
    }
    $pw.Status.Text = "Done - $done of $($Ids.Count) processed."
    $pw.Log.AppendText("`r`n=== Done. Some tweaks need a restart or Explorer relaunch to fully apply. ===`r`n")
}

$ctrl.ApplyTweaksBtn.Add_Click({
    $ids = $TweakCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key }
    Run-TweaksJob -Ids $ids
})
$ctrl.UndoTweaksBtn.Add_Click({
    $ids = $TweakCheckboxes.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key }
    Run-TweaksJob -Ids $ids -Undo
})

# ---------------------------------------------------------------------------
# Updates tab - Windows Update Profiles (Recommended / Windows Default /
# Disable Updates), plus manual check+install via the Windows Update Agent
# COM API.
# ---------------------------------------------------------------------------
$WUPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$WUAuPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'

function Apply-RecommendedUpdatePolicy {
    New-Item -Path $WUPolicyPath -Force | Out-Null
    New-Item -Path $WUAuPolicyPath -Force | Out-Null
    New-ItemProperty -Path $WUPolicyPath -Name 'DeferFeatureUpdatesPeriodInDays' -Value 365 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $WUPolicyPath -Name 'DeferQualityUpdatesPeriodInDays' -Value 4 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $WUPolicyPath -Name 'ExcludeWUDriversInQualityUpdate' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $WUAuPolicyPath -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 -PropertyType DWord -Force | Out-Null
    Remove-ItemProperty -Path $WUAuPolicyPath -Name 'NoAutoUpdate' -ErrorAction SilentlyContinue
    Set-Service -Name wuauserv -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Get-ScheduledTask -TaskPath '\Microsoft\Windows\WindowsUpdate\*' -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
}

function Restore-DefaultUpdatePolicy {
    Remove-Item -Path $WUPolicyPath -Recurse -Force -ErrorAction SilentlyContinue
    Set-Service -Name wuauserv -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service -Name wuauserv -ErrorAction SilentlyContinue
    Get-ScheduledTask -TaskPath '\Microsoft\Windows\WindowsUpdate\*' -ErrorAction SilentlyContinue | Enable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
}

function Disable-Updates {
    New-Item -Path $WUAuPolicyPath -Force | Out-Null
    New-ItemProperty -Path $WUAuPolicyPath -Name 'NoAutoUpdate' -Value 1 -PropertyType DWord -Force | Out-Null
    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
    Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
    Set-Service -Name wuauserv -StartupType Disabled -ErrorAction SilentlyContinue
    Get-ScheduledTask -TaskPath '\Microsoft\Windows\WindowsUpdate\*' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
    $downloadPath = "$env:WINDIR\SoftwareDistribution\Download"
    if (Test-Path $downloadPath) { Remove-Item "$downloadPath\*" -Recurse -Force -ErrorAction SilentlyContinue }
}

$ctrl.ApplyRecommendedBtn.Add_Click({
    $ctrl.UpdatesStatus.Text = 'Applying Recommended update profile...'
    [System.Windows.Forms.Application]::DoEvents()
    try { Apply-RecommendedUpdatePolicy; $ctrl.UpdatesStatus.Text = 'Recommended update profile applied. Restart Windows to fully take effect.' }
    catch { $ctrl.UpdatesStatus.Text = "Error: $($_.Exception.Message)" }
})
$ctrl.RestoreDefaultsBtn.Add_Click({
    $ctrl.UpdatesStatus.Text = 'Restoring Windows default update settings...'
    [System.Windows.Forms.Application]::DoEvents()
    try { Restore-DefaultUpdatePolicy; $ctrl.UpdatesStatus.Text = 'Windows Update settings restored to default.' }
    catch { $ctrl.UpdatesStatus.Text = "Error: $($_.Exception.Message)" }
})
$ctrl.DisableUpdatesBtn.Add_Click({
    $confirm = [System.Windows.MessageBox]::Show('This stops Windows Update entirely, including security updates. Continue?', 'Stackify', 'YesNo', 'Warning')
    if ($confirm -ne 'Yes') { return }
    $ctrl.UpdatesStatus.Text = 'Disabling Windows Update...'
    [System.Windows.Forms.Application]::DoEvents()
    try { Disable-Updates; $ctrl.UpdatesStatus.Text = 'Windows Update disabled.' }
    catch { $ctrl.UpdatesStatus.Text = "Error: $($_.Exception.Message)" }
})

$script:PendingUpdates = $null

$ctrl.CheckUpdatesBtn.Add_Click({
    $ctrl.UpdatesStatus.Text = 'Checking for updates via Windows Update Agent...'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $result   = $searcher.Search("IsInstalled=0 and IsHidden=0")
        $script:PendingUpdates = $result.Updates
        if ($result.Updates.Count -eq 0) {
            $ctrl.UpdatesStatus.Text = "You're up to date - no updates available."
        } else {
            $ctrl.UpdatesStatus.Text = "$($result.Updates.Count) update(s) available. Click 'Install All Updates' to install them."
        }
    } catch { $ctrl.UpdatesStatus.Text = "Error: $($_.Exception.Message)" }
})

$ctrl.InstallUpdatesBtn.Add_Click({
    if (-not $script:PendingUpdates -or $script:PendingUpdates.Count -eq 0) {
        $ctrl.UpdatesStatus.Text = "No checked updates in hand - click 'Check for Updates Now' first."
        return
    }
    $pw = New-ProgressWindow -Title 'Stackify - Windows Update' -Max 2
    try {
        $session    = New-Object -ComObject Microsoft.Update.Session
        $downloader = $session.CreateUpdateDownloader()
        $toDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $script:PendingUpdates) { $toDownload.Add($u) | Out-Null }
        $downloader.Updates = $toDownload
        $pw.Status.Text = 'Downloading updates...'
        $pw.Log.AppendText("Downloading $($toDownload.Count) update(s)...`r`n")
        $downloader.Download() | Out-Null
        $pw.Bar.Value = 1

        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $toDownload
        $pw.Status.Text = 'Installing updates (this can take a while)...'
        $installResult = $installer.Install()
        $pw.Bar.Value = 2
        $pw.Log.AppendText("Result code: $($installResult.ResultCode) (2 = Succeeded)`r`n")
        if ($installResult.RebootRequired) { $pw.Log.AppendText("`r`nA restart is required to finish installing updates.`r`n") }
        $pw.Status.Text = 'Done.'
    } catch {
        $pw.Log.AppendText("ERROR: $($_.Exception.Message)`r`n")
    }
})

$ctrl.OpenWUBtn.Add_Click({ Start-Process 'ms-settings:windowsupdate' })

# ---------------------------------------------------------------------------
$Window.ShowDialog() | Out-Null
