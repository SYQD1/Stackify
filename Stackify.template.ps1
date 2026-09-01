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
__APPS_JSON__
'@
$TweaksJson = @'
__TWEAKS_JSON__
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
    'chrome'     = 'https://thumb.wikimedia.org/wikipedia/commons/thumb/e/e1/Google_Chrome_icon_%28February_2022%29.svg/250px-Google_Chrome_icon_%28February_2022%29.svg.png'
    'firefox'    = 'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a0/Firefox_logo%2C_2019.svg/250px-Firefox_logo%2C_2019.svg.png'
    # These four have no favicon.ico at their domain root at all (confirmed
    # by hand), and/or their catalog `link` is a redirect shortlink (aka.ms)
    # rather than the product's own site, so domain-based lookup can't work
    # for them no matter what fallback order is tried. Pointed directly at
    # a real icon asset from each project instead.
    'terminal'   = 'https://raw.githubusercontent.com/microsoft/terminal/main/res/terminal.ico'
    'gimp'       = 'https://www.gimp.org/images/wilber32.png'
    'klite'      = 'https://www.codecguide.com/mpc_logo.png'
    'eartrumpet' = 'https://raw.githubusercontent.com/File-New-Project/EarTrumpet/master/EarTrumpet.Package/Assets/Square44x44Logo.altform-unplated_targetsize-256.png'
    'qtox'       = 'https://raw.githubusercontent.com/qTox/qTox/master/img/icons/128x128/qtox.png'
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

# Try the domain's own favicon.ico first - it's the authoritative source
# and, empirically, more reliable than Google's proxy: for some sites
# (irfanview.com is a confirmed case) Google's service returns HTTP 200
# with a generic placeholder glyph instead of erroring, which a fallback
# can't catch since nothing ever signals failure. Google's service is still
# useful as the second attempt for sites with no favicon.ico at their
# domain root (many modern sites reference their icon via a hashed/CDN path
# instead) - e.g. videolan.org 404s the direct fetch but Google resolves it.
function Get-IconDownloadUrl { param([string]$Key)
    if ($Key.StartsWith('app:')) {
        $appId = $Key.Substring(4)
        return $IconOverrides[$appId]
    }
    $domain = $Key.Substring(7)
    return "https://$domain/favicon.ico"
}

function Get-IconFallbackUrl { param([string]$Key)
    if ($Key.StartsWith('app:')) { return $null }
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
        $fallbackUrl = Get-IconFallbackUrl -Key $key

        $ps = [powershell]::Create()
        $ps.RunspacePool = $script:IconRunspacePool
        [void]$ps.AddScript({
            param($Key, $Url, $FallbackUrl, $Queue, $CacheFile)
            function Try-Download { param($U)
                try {
                    $wc = New-Object System.Net.WebClient
                    $wc.Headers.Add('User-Agent', 'Mozilla/5.0')
                    $bytes = $wc.DownloadData($U)
                    if ($bytes -and $bytes.Length -gt 0) { return $bytes }
                } catch {}
                return $null
            }
            $bytes = Try-Download -U $Url
            if (-not $bytes -and $FallbackUrl) { $bytes = Try-Download -U $FallbackUrl }
            if ($bytes) {
                try { [IO.File]::WriteAllBytes($CacheFile, $bytes) } catch {}
                $Queue.Enqueue([pscustomobject]@{ Key = $Key; Bytes = $bytes })
            }
        }).AddArgument($key).AddArgument($url).AddArgument($fallbackUrl).AddArgument($script:IconResultQueue).AddArgument($cacheFile)
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
                    if ([string]::IsNullOrWhiteSpace($appProp.Value.winget)) { continue }
                    $matchId = $appProp.Value.winget -replace '^msstore:', ''
                    if ($listOut -match [Regex]::Escape($matchId)) {
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
# Set-RegistryValue and Invoke-Tweak are defined here, before the toggle
# rows below are built - not just organizationally. New-TweakToggleRow's
# instant-apply click handlers are created via .GetNewClosure(), which
# snapshots the function table available at that exact moment; a function
# defined later in the script (as these originally were, further down near
# Run-TweaksJob) would not exist yet in that snapshot, and every toggle
# click would fail with "Invoke-Tweak is not recognized..." silently
# swallowed by the handler's own try/catch. Confirmed this failure mode by
# temporarily logging the caught exception before moving these up.
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

    # $OutBox is optional - the Customize Preferences toggles apply/undo
    # instantly on click (no progress window for a single quick registry
    # tweak), while the batch Run Tweaks / Undo Selected Tweaks flow passes
    # a real log TextBox.
    $log = { param($Text) if ($OutBox) { $OutBox.AppendText($Text) } }.GetNewClosure()

    $tw = $Tweaks.$TweakId
    & $log "`r`n=== $(if($Undo){'Undoing'}else{'Applying'}) $($tw.name) ===`r`n"

    if (-not $Undo) {
        if ($tw.registry) {
            foreach ($r in $tw.registry) {
                try { Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.Value -Type $r.Type }
                catch { & $log "  registry warn: $($_.Exception.Message)`r`n" }
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
                } catch { & $log "  script warn: $($_.Exception.Message)`r`n" }
            }
        }
    } else {
        if ($tw.registry) {
            foreach ($r in $tw.registry) {
                try { Set-RegistryValue -Path $r.Path -Name $r.Name -Value $r.OriginalValue -Type $r.Type }
                catch { & $log "  registry warn: $($_.Exception.Message)`r`n" }
            }
        }
        if ($tw.undo) {
            foreach ($block in $tw.undo) {
                try {
                    $sb = [ScriptBlock]::Create($block)
                    Invoke-Command -ScriptBlock $sb | Out-Null
                } catch { & $log "  script warn: $($_.Exception.Message)`r`n" }
            }
        }
    }
    if ($OutBox) {
        $OutBox.ScrollToEnd()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

$TweakCheckboxes = @{}
# .Suppress is set while programmatically syncing toggle state to the real
# registry (startup, "Get Installed Tweaks", and the preset buttons) so
# that doesn't itself trigger the Customize Preferences toggles' instant
# apply/undo below - only an actual user click should do that.
$script:ToggleSyncState = @{ Suppress = $false }
# $script: variables referenced INLINE inside a .GetNewClosure()'d
# scriptblock body don't reliably resolve against the real script scope at
# invocation time (confirmed via a trace log: it read back empty, not the
# value that had actually been set). Wrapping the read in a normal function
# call - same as Set-RegistryValue/Invoke-Tweak above needing to be defined
# before Build-TweaksPanelOnce runs, and the same pattern Show-HelpPopup
# already relies on elsewhere - resolves correctly instead.
function Test-ToggleSyncSuppressed { return [bool]$script:ToggleSyncState.Suppress }
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
    $toggleId = $Id
    # Customize Preferences toggles behave like real OS settings switches -
    # flipping one applies (or undoes) it immediately, unlike the
    # Essential/Advanced checkboxes on the left which only get applied in
    # a batch once "Run Tweaks" is clicked.
    $toggle.Add_Checked({
        Update-TweakCount
        if (Test-ToggleSyncSuppressed) { return }
        try { Invoke-Tweak -TweakId $toggleId } catch {}
    }.GetNewClosure())
    $toggle.Add_Unchecked({
        Update-TweakCount
        if (Test-ToggleSyncSuppressed) { return }
        try { Invoke-Tweak -TweakId $toggleId -Undo } catch {}
    }.GetNewClosure())
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
    # The presets (Standard/Minimal/Advanced/Clear) only ever pick from
    # Essential/Advanced tweak ids, never Customize Preferences toggles -
    # but this still unconditionally unchecks every checkbox, toggles
    # included, so without suppressing it a preset click would silently
    # undo every currently-active toggle (Dark Theme, etc.) as a side effect.
    $script:ToggleSyncState.Suppress = $true
    try {
        foreach ($kv in $TweakCheckboxes.GetEnumerator()) { $kv.Value.IsChecked = $false }
        foreach ($id in $Ids) { if ($TweakCheckboxes.ContainsKey($id)) { $TweakCheckboxes[$id].IsChecked = $true } }
    } finally {
        $script:ToggleSyncState.Suppress = $false
    }
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

function Sync-TweaksToSystemState {
    $script:ToggleSyncState.Suppress = $true
    try {
        foreach ($kv in $TweakCheckboxes.GetEnumerator()) {
            $tw = $Tweaks.($kv.Key)
            try { $kv.Value.IsChecked = (Test-TweakApplied -Tw $tw) } catch { $kv.Value.IsChecked = $false }
        }
    } finally {
        $script:ToggleSyncState.Suppress = $false
    }
    Update-TweakCount
}

$ctrl.GetInstalledTweaksBtn.Add_Click({ Sync-TweaksToSystemState })

# Reflect the machine's real current state as soon as the Tweaks tab is
# built, rather than only after an explicit "Get Installed Tweaks" click -
# every toggle/checkbox already knows how to detect this (Test-TweakApplied
# reads the real registry values), it just wasn't being run automatically.
Sync-TweaksToSystemState

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

# A plain synchronous Process.Start + ReadToEnd()/WaitForExit() here blocks
# whichever thread calls it for the entire install duration - and every
# caller of this function runs on the UI thread, so a real install (which
# can run for tens of seconds to minutes) would freeze the whole window and
# Windows would mark it "Not Responding", even though it's actually still
# working. Runs the process on a background runspace instead and pumps
# DoEvents while waiting, so the window stays responsive and paints
# normally throughout - same pattern already used for icon downloads.
$script:ProcessRunspacePool = [runspacefactory]::CreateRunspacePool(1, 4)
$script:ProcessRunspacePool.Open()

function Invoke-ProcessSilently {
    param([string]$FileName, [string[]]$ArgList)
    $ps = [powershell]::Create()
    $ps.RunspacePool = $script:ProcessRunspacePool
    [void]$ps.AddScript({
        param($FileName, $ArgList)
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
    }).AddArgument($FileName).AddArgument($ArgList)

    $handle = $ps.BeginInvoke()
    while (-not $handle.IsCompleted) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
    $result = $ps.EndInvoke($handle)
    $ps.Dispose()
    return $result[0]
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
        if ([string]::IsNullOrWhiteSpace($pkgId)) {
            # A handful of apps (e.g. RustDesk) aren't on WinGet at all, only
            # Chocolatey, or vice versa - this used to only be checked for
            # Chocolatey, so picking WinGet for one of those apps would build
            # an --id argument with nothing after it instead of skipping
            # cleanly.
            $mgrName = if ($useChoco) { 'Chocolatey' } else { 'WinGet' }
            $otherMgrName = if ($useChoco) { 'WinGet' } else { 'Chocolatey' }
            $pw.Log.AppendText("`r`n=== Skipping $($appDef.name) - no $mgrName package known (try $otherMgrName instead) ===`r`n")
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
                # A few catalog entries use the "msstore:<id>" convention to
                # mark a Microsoft Store package (e.g. ChatGPT Desktop,
                # WhatsApp Desktop). winget's --id flag doesn't understand
                # that prefix syntax at all ("no package found") - the store
                # source has to be passed separately via --source.
                $wingetId = $pkgId
                $sourceArgs = @()
                if ($pkgId -like 'msstore:*') {
                    $wingetId = $pkgId.Substring(8)
                    $sourceArgs = @('--source', 'msstore')
                }

                # Deliberately no --scope argument: forcing --scope machine breaks
                # any package whose manifest only declares a user-scope installer
                # (very common - Proton Mail, Discord, Spotify, most Electron
                # apps), since winget has no machine-scope installer to fall
                # back to for those and the install just silently fails.
                # Letting winget pick the scope itself (its normal default
                # behavior) matches what a plain `winget install <id>` does.
                $args = if ($Uninstall) {
                    @('uninstall', '--id', $wingetId, '-e', '--silent', '--disable-interactivity', '--accept-source-agreements') + $sourceArgs
                } else {
                    @('install', '--id', $wingetId, '-e', '--silent', '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements') + $sourceArgs
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
