#Requires -Version 5.1
<#
    BALDYBEAST OPTIMIZER
    Windows 10 / 11 gaming optimization, debloat and cleanup utility.

    Run from disk  : powershell -ExecutionPolicy Bypass -File Optimize.ps1
    Run from GitHub: irm "https://raw.githubusercontent.com/BaldyBeast/BALDYBEAST-OPTIMIZER/main/Optimize.ps1" | iex

    Single file. No external DLLs. Pure PowerShell + WPF.
    Author: BaldyBeast   License: MIT
#>

$ErrorActionPreference = 'Continue'

$script:AppVersion   = '1.0.0'
$script:RepoRawUrl   = 'https://raw.githubusercontent.com/BaldyBeast/BALDYBEAST-OPTIMIZER/main/Optimize.ps1'
$script:LogFile      = Join-Path $env:TEMP 'BaldyBeast-Optimizer.log'
$script:LogBox       = $null
$script:Window       = $null
$script:NeedsReboot  = $false
$script:ValidateMode = ($env:BALDYBEAST_VALIDATE -eq '1')

# ----------------------------------------------------------------------------
# ASCII banner font (every cell is exactly 7 characters wide)
# ----------------------------------------------------------------------------
$script:BannerFont = @{
    'B' = @('###### ', '#     #', '###### ', '#     #', '#     #', '###### ')
    'A' = @(' ##### ', '#     #', '#     #', '#######', '#     #', '#     #')
    'L' = @('#      ', '#      ', '#      ', '#      ', '#      ', '###### ')
    'D' = @('###### ', '#     #', '#     #', '#     #', '#     #', '###### ')
    'Y' = @('#     #', '#     #', ' #   # ', '  # #  ', '   #   ', '   #   ')
    'E' = @('#######', '#      ', '#####  ', '#      ', '#      ', '#######')
    'S' = @(' ##### ', '#      ', ' ##### ', '      #', '#     #', ' ##### ')
    'T' = @('#######', '   #   ', '   #   ', '   #   ', '   #   ', '   #   ')
}

function Get-BaldyBanner {
    $word = 'BALDYBEAST'
    $rows = for ($r = 0; $r -lt 6; $r++) {
        (($word.ToCharArray() | ForEach-Object { $script:BannerFont[[string]$_][$r] }) -join ' ')
    }
    return ($rows -join [System.Environment]::NewLine)
}

if (-not $script:ValidateMode) {
    Write-Host ''
    Write-Host (Get-BaldyBanner) -ForegroundColor Yellow
    Write-Host ''
    Write-Host ('  BALDYBEAST OPTIMIZER v{0}  |  Windows 10/11 gaming utility' -f $script:AppVersion) -ForegroundColor DarkYellow
    Write-Host ('  Log file: {0}' -f $script:LogFile) -ForegroundColor Gray
    Write-Host ''
}

# ----------------------------------------------------------------------------
# Self elevation: relaunch with administrator rights when needed
# ----------------------------------------------------------------------------
if (-not $script:ValidateMode) {
    $isElevated = $false
    try {
        $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        $isElevated = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        $isElevated = $false
    }

    if (-not $isElevated) {
        Write-Host '[*] Administrator rights required. Requesting elevation...' -ForegroundColor Yellow

        $relaunchArgs = $null
        if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Test-Path -LiteralPath $PSCommandPath)) {
            # Running from a real file: relaunch that file
            $relaunchArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
        } else {
            # Running via irm | iex: recover the source text and drop it into a temp file
            $sourceText = $null
            try { $sourceText = $MyInvocation.MyCommand.ScriptBlock.ToString() } catch { $sourceText = $null }

            if (-not [string]::IsNullOrWhiteSpace($sourceText) -and $sourceText.Contains('BALDYBEAST')) {
                $tempScript = Join-Path $env:TEMP ('BaldyBeast-Optimize-{0}.ps1' -f ([guid]::NewGuid().ToString('N').Substring(0, 8)))
                Set-Content -LiteralPath $tempScript -Value $sourceText -Encoding UTF8
                $relaunchArgs = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $tempScript
            } else {
                # Last resort: elevate by pulling the script from GitHub again
                $relaunchArgs = '-NoProfile -ExecutionPolicy Bypass -Command "irm ''{0}'' | iex"' -f $script:RepoRawUrl
            }
        }

        try {
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $relaunchArgs | Out-Null
        } catch {
            Write-Host ('[!] Elevation failed: {0}' -f $_.Exception.Message) -ForegroundColor Red
        }
        return
    }
}

# ----------------------------------------------------------------------------
# Helper functions
# ----------------------------------------------------------------------------
function Update-Ui {
    try {
        if ($null -ne $script:Window) {
            $script:Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
            $script:Window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
        }
    } catch { }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    $line = '[{0}] [{1,-5}] {2}' -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message

    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }

    if ($null -ne $script:LogBox) {
        $script:LogBox.AppendText($line + "`r`n")
        $script:LogBox.ScrollToEnd()
    }

    if (-not $script:ValidateMode) {
        $color = 'Gray'
        switch ($Level) {
            'OK'    { $color = 'Green' }
            'WARN'  { $color = 'Yellow' }
            'ERROR' { $color = 'Red' }
        }
        Write-Host $line -ForegroundColor $color
    }

    Update-Ui
}

function Confirm-Action {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Message
    )
    try {
        $result = [System.Windows.MessageBox]::Show($script:Window, $Message, $Title, 'YesNo', 'Warning')
        return ($result -eq 'Yes')
    } catch {
        return $false
    }
}

function Set-RegValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [ValidateSet('DWord', 'String', 'QWord', 'ExpandString', 'Binary')][string]$Type = 'DWord'
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop | Out-Null
        Write-Log ('Registry {0}\{1} = {2}' -f $Path, $Name, $Value) 'OK'
        return $true
    } catch {
        Write-Log ('Registry FAILED {0}\{1}: {2}' -f $Path, $Name, $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Set-ServiceSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateSet('Disabled', 'Manual', 'Automatic')][string]$StartType = 'Disabled'
    )

    try {
        $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            Write-Log ('Service {0} not present on this system, skipped' -f $Name)
            return
        }
        if ($service.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        }
        Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop
        Write-Log ('Service {0} set to {1}' -f $Name, $StartType) 'OK'
    } catch {
        Write-Log ('Service {0} failed: {1}' -f $Name, $_.Exception.Message) 'ERROR'
    }
}

function Disable-TaskSafe {
    param([Parameter(Mandatory = $true)][string]$TaskPath)

    try {
        $cut = $TaskPath.LastIndexOf('\')
        if ($cut -lt 1) {
            Write-Log ('Task path not understood: {0}' -f $TaskPath) 'WARN'
            return
        }
        $folder = $TaskPath.Substring(0, $cut + 1)
        $name   = $TaskPath.Substring($cut + 1)

        $task = Get-ScheduledTask -TaskName $name -TaskPath $folder -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            Write-Log ('Task not present, skipped: {0}' -f $TaskPath)
            return
        }
        Disable-ScheduledTask -TaskName $name -TaskPath $folder -ErrorAction Stop | Out-Null
        Write-Log ('Task disabled: {0}' -f $TaskPath) 'OK'
    } catch {
        Write-Log ('Task failed {0}: {1}' -f $TaskPath, $_.Exception.Message) 'ERROR'
    }
}

function Clear-PathSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    try {
        if (-not (Test-Path -LiteralPath $Path)) {
            Write-Log ('{0}: path not found, skipped' -f $Label)
            return
        }

        $freedBytes = 0L
        $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            try { $freedBytes += $file.Length } catch { }
        }

        Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        Write-Log ('{0}: freed about {1} MB' -f $Label, [math]::Round(($freedBytes / 1MB), 1)) 'OK'
    } catch {
        Write-Log ('{0} failed: {1}' -f $Label, $_.Exception.Message) 'ERROR'
    }
}

# ----------------------------------------------------------------------------
# XAML: styles, header, gaming tab
# ----------------------------------------------------------------------------
$xamlA = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="BALDYBEAST OPTIMIZER" Height="800" Width="1140"
        MinHeight="660" MinWidth="960" WindowStartupLocation="CenterScreen"
        Background="#FF14141F" Foreground="#FFE8E8F0"
        FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <SolidColorBrush x:Key="AccentBrush" Color="#FFF59E0B"/>
    <SolidColorBrush x:Key="CardBrush" Color="#FF22223A"/>
    <SolidColorBrush x:Key="LineBrush" Color="#FF3A3A52"/>
    <SolidColorBrush x:Key="DimBrush" Color="#FFA0A0B8"/>

    <Style TargetType="Border" x:Key="Card">
      <Setter Property="Background" Value="#FF22223A"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="16"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
      <Setter Property="BorderBrush" Value="#FF3A3A52"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>

    <Style TargetType="TextBlock" x:Key="CardHeader">
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="#FFF59E0B"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
    </Style>

    <Style TargetType="TextBlock" x:Key="DimText">
      <Setter Property="Foreground" Value="#FFA0A0B8"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="0,4,0,8"/>
    </Style>

    <Style TargetType="CheckBox" x:Key="DarkCheck">
      <Setter Property="Foreground" Value="#FFE8E8F0"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Margin" Value="2,6,2,6"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>

    <Style TargetType="Button" x:Key="DarkButton">
      <Setter Property="Background" Value="#FF2D2D44"/>
      <Setter Property="Foreground" Value="#FFE8E8F0"/>
      <Setter Property="BorderBrush" Value="#FF3F3F5C"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"
                                TextElement.Foreground="{TemplateBinding Foreground}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.88"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Opacity" Value="0.72"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Button" x:Key="AccentButton" BasedOn="{StaticResource DarkButton}">
      <Setter Property="Background" Value="#FFF59E0B"/>
      <Setter Property="Foreground" Value="#FF201500"/>
      <Setter Property="BorderBrush" Value="#FFF59E0B"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Padding" Value="18,10"/>
    </Style>

    <Style TargetType="Button" x:Key="DangerButton" BasedOn="{StaticResource DarkButton}">
      <Setter Property="Background" Value="#FFB91C1C"/>
      <Setter Property="Foreground" Value="#FFFFE4E4"/>
      <Setter Property="BorderBrush" Value="#FFEF4444"/>
    </Style>

    <Style TargetType="TabItem" x:Key="DarkTab">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="tabBd" Background="Transparent" BorderBrush="#FF3A3A52"
                    BorderThickness="1,1,1,0" CornerRadius="8,8,0,0" Margin="0,0,6,0" Padding="16,9">
              <ContentPresenter x:Name="headerHost" ContentSource="Header" TextElement.Foreground="#FFB8B8CC"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="tabBd" Property="Background" Value="#FF22223A"/>
                <Setter TargetName="tabBd" Property="BorderBrush" Value="#FFF59E0B"/>
                <Setter TargetName="headerHost" Property="TextElement.Foreground" Value="#FFF59E0B"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="tabBd" Property="Background" Value="#FF2D2D44"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="190"/>
    </Grid.RowDefinitions>

    <!-- Banner header -->
    <Grid Grid.Row="0" Margin="18,14,18,4">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0" VerticalAlignment="Center">
        <TextBlock x:Name="txtBanner" FontFamily="Consolas" FontSize="13" FontWeight="Bold"
                   Foreground="#FFF59E0B" TextWrapping="NoWrap"/>
        <TextBlock x:Name="txtSubtitle" Foreground="#FFA0A0B8" FontSize="12" Margin="2,4,0,0"
                   Text="Windows 10 / 11 gaming optimizer, debloat and cleanup utility"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="btnRestorePoint" Style="{StaticResource DarkButton}" Content="Create Restore Point" Margin="0,0,8,0"/>
        <Button x:Name="btnReboot" Style="{StaticResource DarkButton}" Content="Restart PC" Margin="0,0,8,0"/>
        <Button x:Name="btnOptimizeAll" Style="{StaticResource AccentButton}" Content="Optimize Everything (Gaming Ready)"/>
      </StackPanel>
    </Grid>

    <!-- Tabs -->
    <TabControl x:Name="tabMain" Grid.Row="2" Margin="18,8,18,0" Background="#FF1F1F2E"
                BorderBrush="#FF3A3A52" Padding="10">

      <!-- ================= GAMING TWEAKS ================= -->
      <TabItem Header="Gaming Tweaks" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Power and Performance"/>
                <CheckBox x:Name="chkPowerPlan" Style="{StaticResource DarkCheck}"
                          Content="Enable Ultimate Performance power plan and switch to it (falls back to High Performance)"/>
                <CheckBox x:Name="chkMmcss" Style="{StaticResource DarkCheck}"
                          Content="Tune MMCSS: remove network throttling, boost Games task GPU and IO priority"/>
                <CheckBox x:Name="chkUsbSuspend" Style="{StaticResource DarkCheck}"
                          Content="Disable USB selective suspend (steadier mouse and keyboard polling)"/>
                <CheckBox x:Name="chkVisualFx" Style="{StaticResource DarkCheck}"
                          Content="Set visual effects for best performance (keeps smooth fonts)"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Mouse, Capture and Game Mode"/>
                <CheckBox x:Name="chkMouseAccel" Style="{StaticResource DarkCheck}"
                          Content="Disable mouse acceleration (Enhance Pointer Precision off)"/>
                <CheckBox x:Name="chkGameDVR" Style="{StaticResource DarkCheck}"
                          Content="Disable Game DVR and background recording (GameConfigStore + AppCaptureEnabled)"/>
                <CheckBox x:Name="chkFullscreen" Style="{StaticResource DarkCheck}"
                          Content="Disable fullscreen optimizations (FSE behavior mode for games)"/>
                <CheckBox x:Name="chkGameMode" Style="{StaticResource DarkCheck}"
                          Content="Enable Game Mode and silence Game Bar popups"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Graphics Scheduling"/>
                <CheckBox x:Name="chkHAGS" Style="{StaticResource DarkCheck}"
                          Content="Enable Hardware-Accelerated GPU Scheduling (HwSchMode = 2, reboot required)"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="HAGS needs a supported GPU driver and a restart. The tool flags that at the end."/>
              </StackPanel>
            </Border>

            <Button x:Name="btnApplyGaming" Style="{StaticResource AccentButton}"
                    Content="Apply Selected Gaming Tweaks" HorizontalAlignment="Left" Margin="0,4,0,14"/>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
'@

# ----------------------------------------------------------------------------
# XAML: debloat tab, system clean tab, about tab, log panel
# ----------------------------------------------------------------------------
$xamlB = @'
      <!-- ================= DEBLOAT AND SERVICES ================= -->
      <TabItem Header="Debloat and Services" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Bloatware Apps (removed for all users)"/>
                <CheckBox x:Name="chkBloatBing" Style="{StaticResource DarkCheck}"
                          Content="Bing News, Bing Weather, Get Help, Get Started, Office Hub"/>
                <CheckBox x:Name="chkBloat3D" Style="{StaticResource DarkCheck}"
                          Content="3D Builder, 3D Viewer, Mixed Reality Portal"/>
                <CheckBox x:Name="chkBloatGames" Style="{StaticResource DarkCheck}"
                          Content="Solitaire Collection, Xbox Console Companion"/>
                <CheckBox x:Name="chkBloatMisc" Style="{StaticResource DarkCheck}"
                          Content="People, Feedback Hub, Maps, Power Automate, To Do, Zune Music and Video, Skype, Mail and Calendar, Clipchamp, Teams"/>
                <CheckBox x:Name="chkBloatCortana" Style="{StaticResource DarkCheck}"
                          Content="Cortana app"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Gaming Services and Xbox Game Bar stay installed so Game Pass and captures keep working."/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Telemetry and Tracking"/>
                <CheckBox x:Name="chkTelemetry" Style="{StaticResource DarkCheck}"
                          Content="Disable telemetry, Diagnostic Tracking (DiagTrack) and CEIP scheduled tasks"/>
                <CheckBox x:Name="chkServices" Style="{StaticResource DarkCheck}"
                          Content="Disable unneeded services: Maps Broker, Retail Demo, WMP Network Sharing"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Windows Annoyances"/>
                <CheckBox x:Name="chkCortana" Style="{StaticResource DarkCheck}"
                          Content="Disable Cortana and web results in the taskbar search"/>
                <CheckBox x:Name="chkBackgroundApps" Style="{StaticResource DarkCheck}"
                          Content="Disable background apps globally"/>
                <CheckBox x:Name="chkConsumer" Style="{StaticResource DarkCheck}"
                          Content="Disable consumer experiences, suggested apps, tips and Start menu ads"/>
                <CheckBox x:Name="chkActivity" Style="{StaticResource DarkCheck}"
                          Content="Disable activity history and upload of user activities"/>
                <CheckBox x:Name="chkWidgets" Style="{StaticResource DarkCheck}"
                          Content="Disable Widgets and News and Interests"/>
                <CheckBox x:Name="chkCopilot" Style="{StaticResource DarkCheck}"
                          Content="Disable Windows Copilot"/>
                <CheckBox x:Name="chkRecall" Style="{StaticResource DarkCheck}"
                          Content="Disable Windows Recall and AI data analysis"/>
                <CheckBox x:Name="chkOneDrive" Style="{StaticResource DarkCheck}"
                          Content="Remove OneDrive autostart entry (files stay untouched)"/>
              </StackPanel>
            </Border>

            <StackPanel Orientation="Horizontal" Margin="0,4,0,14">
              <Button x:Name="btnSelectAllDebloat" Style="{StaticResource DarkButton}"
                      Content="Select Recommended" Margin="0,0,8,0"/>
              <Button x:Name="btnApplyDebloat" Style="{StaticResource AccentButton}"
                      Content="Apply Selected Debloat Tweaks"/>
            </StackPanel>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= SYSTEM CLEAN ================= -->
      <TabItem Header="System Clean" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="File Cleanup"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Each button logs how much space it freed. Nothing here touches personal files."/>
                <WrapPanel>
                  <Button x:Name="btnCleanTemp" Style="{StaticResource DarkButton}" Content="Clear Temp Files" Margin="0,0,8,8"/>
                  <Button x:Name="btnCleanWU" Style="{StaticResource DarkButton}" Content="Clear Windows Update Cache" Margin="0,0,8,8"/>
                  <Button x:Name="btnCleanPrefetch" Style="{StaticResource DarkButton}" Content="Clear Prefetch" Margin="0,0,8,8"/>
                  <Button x:Name="btnCleanDO" Style="{StaticResource DarkButton}" Content="Clear Delivery Optimization" Margin="0,0,8,8"/>
                  <Button x:Name="btnCleanWER" Style="{StaticResource DarkButton}" Content="Clear Error Reports" Margin="0,0,8,8"/>
                  <Button x:Name="btnCleanRecycle" Style="{StaticResource DarkButton}" Content="Empty Recycle Bin" Margin="0,0,8,8"/>
                  <Button x:Name="btnCleanDNS" Style="{StaticResource DarkButton}" Content="Flush DNS Cache" Margin="0,0,8,8"/>
                </WrapPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Maintenance"/>
                <WrapPanel>
                  <Button x:Name="btnCleanAll" Style="{StaticResource AccentButton}" Content="Run Full Cleanup" Margin="0,0,8,8"/>
                  <Button x:Name="btnDisableHibernation" Style="{StaticResource DangerButton}" Content="Disable Hibernation (frees disk space)" Margin="0,0,8,8"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Disabling hibernation deletes hiberfil.sys (roughly the size of your RAM) and turns off Fast Startup."/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= ABOUT ================= -->
      <TabItem Header="About" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="BALDYBEAST OPTIMIZER"/>
                <TextBlock x:Name="txtAbout" TextWrapping="Wrap" Foreground="#FFD0D0E0" FontSize="13" LineHeight="23"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
    </TabControl>

    <!-- Console log -->
    <Grid Grid.Row="3" Margin="18,10,18,14">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <DockPanel Grid.Row="0" Margin="0,0,0,6">
        <Button x:Name="btnClearLog" DockPanel.Dock="Right" Style="{StaticResource DarkButton}"
                Content="Clear Log" Padding="12,4"/>
        <TextBlock Text="Console Log" FontWeight="Bold" Foreground="#FFF59E0B" VerticalAlignment="Center"/>
      </DockPanel>
      <TextBox x:Name="txtLog" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap"
               VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
               FontFamily="Consolas" FontSize="12" Background="#FF0D0D14" Foreground="#FF9FE8B0"
               BorderBrush="#FF3A3A52" Padding="8"/>
    </Grid>
  </Grid>
</Window>
'@

# ----------------------------------------------------------------------------
# Win32 interop used for instant mouse setting apply
# ----------------------------------------------------------------------------
if (-not ('BaldyBeast.Win32' -as [type])) {
    Add-Type -Namespace BaldyBeast -Name Win32 -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true)]
public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, uint lpvParam, uint fuWinIni);
'@
}

# ----------------------------------------------------------------------------
# Gaming tweaks
# ----------------------------------------------------------------------------
function Enable-UltimatePowerPlan {
    $ultimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
    $highGuid     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

    Write-Log 'Switching power plan...'
    try {
        $existing = & powercfg.exe /list 2>$null | Select-String -SimpleMatch $ultimateGuid
        if (-not $existing) {
            & powercfg.exe /duplicatescheme $ultimateGuid 2>$null | Out-Null
            Write-Log 'Ultimate Performance scheme duplicated into power plans' 'OK'
        }
        & powercfg.exe /setactive $ultimateGuid 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'setactive failed' }
        Write-Log 'Ultimate Performance power plan is now active' 'OK'
    } catch {
        Write-Log 'Ultimate Performance unavailable, falling back to High Performance' 'WARN'
        & powercfg.exe /duplicatescheme $highGuid 2>$null | Out-Null
        & powercfg.exe /setactive $highGuid 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'High Performance power plan is now active' 'OK'
        } else {
            Write-Log 'Could not activate a high performance power plan' 'ERROR'
        }
    }
}

function Disable-MouseAcceleration {
    Write-Log 'Disabling mouse acceleration (Enhance Pointer Precision)...'
    Set-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type 'String' | Out-Null
    Set-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type 'String' | Out-Null
    Set-RegValue -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type 'String' | Out-Null

    # SPI_SETMOUSE = 4, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    try {
        [void][BaldyBeast.Win32]::SystemParametersInfo(4, 0, 0, 3)
        Write-Log 'Pointer precision disabled and applied immediately' 'OK'
    } catch {
        Write-Log ('Mouse apply failed: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Disable-GameDvr {
    Write-Log 'Disabling Game DVR and background recording...'
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0 | Out-Null
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -Value 2 | Out-Null
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_HonorUserFSEBehaviorMode' -Value 1 | Out-Null
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehavior' -Value 2 | Out-Null
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_DXGIHonorFSEWindowsCompatible' -Value 1 | Out-Null
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_EFSEFeatureFlags' -Value 0 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0 | Out-Null
}

function Disable-FullscreenOptimizations {
    Write-Log 'Disabling fullscreen optimizations...'
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -Value 2 | Out-Null
    Set-RegValue -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_DXGIHonorFSEWindowsCompatible' -Value 1 | Out-Null
}

function Enable-GameMode {
    Write-Log 'Enabling Game Mode and quieting Game Bar...'
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'UseNexusForGameBarEnabled' -Value 0 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\GameBar' -Name 'ShowStartupPanel' -Value 0 | Out-Null
}

function Enable-Hags {
    Write-Log 'Enabling Hardware-Accelerated GPU Scheduling (HwSchMode = 2)...'
    Set-RegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -Value 2 | Out-Null
    $script:NeedsReboot = $true
}

function Set-MmcssTuning {
    Write-Log 'Tuning MMCSS network throttling and Games task scheduling...'
    $profileKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-RegValue -Path $profileKey -Name 'NetworkThrottlingIndex' -Value ([uint32]::MaxValue) | Out-Null
    Set-RegValue -Path $profileKey -Name 'SystemResponsiveness' -Value 0 | Out-Null

    $gamesKey = Join-Path $profileKey 'Tasks\Games'
    Set-RegValue -Path $gamesKey -Name 'GPU Priority' -Value 8 | Out-Null
    Set-RegValue -Path $gamesKey -Name 'Priority' -Value 6 | Out-Null
    Set-RegValue -Path $gamesKey -Name 'Scheduling Category' -Value 'High' -Type 'String' | Out-Null
    Set-RegValue -Path $gamesKey -Name 'SFIO Priority' -Value 'High' -Type 'String' | Out-Null
}

function Disable-UsbSelectiveSuspend {
    Write-Log 'Disabling USB selective suspend...'
    # sub_usb = 2a737441-1930-4402-8d77-b2bebba308a3, USBSELECTSUSPEND = 48e6b7a6-50f5-4782-a5d4-53bb8f07e226
    & powercfg.exe /setacvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
    & powercfg.exe /setdcvalueindex scheme_current 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 2>$null | Out-Null
    & powercfg.exe /setactive scheme_current 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'USB selective suspend disabled on the active plan' 'OK'
    } else {
        Write-Log 'USB selective suspend could not be changed' 'WARN'
    }
}

function Set-VisualEffectsPerformance {
    Write-Log 'Setting visual effects for best performance...'
    Set-RegValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 | Out-Null
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    Set-RegValue -Path $adv -Name 'VisualFXSetting' -Value 2 | Out-Null
    Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -Value ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) -Type 'Binary' | Out-Null
    Set-RegValue -Path 'HKCU:\Control Panel\Desktop' -Name 'DragFullWindows' -Value '1' -Type 'String' | Out-Null
    Set-RegValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type 'String' | Out-Null
}

function Invoke-GamingTweaks {
    Write-Log '===== Gaming Tweaks: applying selected tweaks ====='
    if ($chkPowerPlan.IsChecked)  { Enable-UltimatePowerPlan }
    if ($chkMouseAccel.IsChecked) { Disable-MouseAcceleration }
    if ($chkGameDvr.IsChecked)    { Disable-GameDvr }
    if ($chkFullscreen.IsChecked) { Disable-FullscreenOptimizations }
    if ($chkGameMode.IsChecked)   { Enable-GameMode }
    if ($chkHags.IsChecked)       { Enable-Hags }
    if ($chkMmcss.IsChecked)      { Set-MmcssTuning }
    if ($chkUsbSuspend.IsChecked) { Disable-UsbSelectiveSuspend }
    if ($chkVisualFx.IsChecked)   { Set-VisualEffectsPerformance }
    Write-Log '===== Gaming Tweaks: done =====' 'OK'
}

# ----------------------------------------------------------------------------
# Debloat and services
# ----------------------------------------------------------------------------
function Remove-BloatApps {
    $groups = [ordered]@{}

    if ($chkBloatBing.IsChecked) {
        $groups['Bing and info apps'] = @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub')
    }
    if ($chkBloat3D.IsChecked) {
        $groups['3D and Mixed Reality'] = @('Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.MixedReality.Portal')
    }
    if ($chkBloatGames.IsChecked) {
        $groups['Casual games and Xbox companion'] = @('Microsoft.MicrosoftSolitaireCollection', 'Microsoft.XboxApp')
    }
    if ($chkBloatMisc.IsChecked) {
        $groups['Consumer apps'] = @('Microsoft.People', 'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.SkypeApp', 'Microsoft.WindowsCommunicationsApps', 'Clipchamp.Clipchamp', 'MSTeams', 'MicrosoftTeams')
    }
    if ($chkBloatCortana.IsChecked) {
        $groups['Cortana'] = @('Microsoft.549981C3F5F10')
    }

    if ($groups.Count -eq 0) {
        Write-Log 'No bloatware groups selected, skipping removal'
        return
    }

    foreach ($groupName in $groups.Keys) {
        Write-Log ('Removing package group: {0}' -f $groupName)
        foreach ($packageName in $groups[$groupName]) {
            try {
                $packages = @(Get-AppxPackage -AllUsers -Name ($packageName + '*') -ErrorAction SilentlyContinue)

                foreach ($pkg in $packages) {
                    $removed = $false
                    try {
                        Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                        $removed = $true
                    } catch {
                        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction SilentlyContinue
                        $removed = $true
                    }
                    if ($removed) {
                        Write-Log ('Removed appx: {0}' -f $pkg.PackageFullName) 'OK'
                    }
                }

                $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                    Where-Object { $_.DisplayName -like ($packageName + '*') })

                foreach ($prov in $provisioned) {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction SilentlyContinue | Out-Null
                    Write-Log ('Removed provisioned: {0}' -f $prov.DisplayName) 'OK'
                }

                if ($packages.Count -eq 0 -and $provisioned.Count -eq 0) {
                    Write-Log ('Not installed, skipped: {0}' -f $packageName)
                }
            } catch {
                Write-Log ('Removal failed for {0}: {1}' -f $packageName, $_.Exception.Message) 'ERROR'
            }
        }
    }
}

function Disable-Telemetry {
    Write-Log 'Disabling telemetry and diagnostic tracking...'
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'AITEnable' -Value 0 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'DisableInventory' -Value 1 | Out-Null

    Set-ServiceSafe -Name 'DiagTrack' -StartType 'Disabled'
    Set-ServiceSafe -Name 'dmwappushservice' -StartType 'Disabled'

    $telemetryTasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\StartupAppTask',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Maps\MapsToastTask',
        '\Microsoft\Windows\Maps\MapsUpdateTask',
        '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem'
    )
    foreach ($taskPath in $telemetryTasks) {
        Disable-TaskSafe -TaskPath $taskPath
    }
}

function Disable-ExtraServices {
    Write-Log 'Disabling unneeded background services...'
    Set-ServiceSafe -Name 'MapsBroker' -StartType 'Disabled'
    Set-ServiceSafe -Name 'RetailDemo' -StartType 'Disabled'
    Set-ServiceSafe -Name 'WMPNetworkSvc' -StartType 'Disabled'
    Set-ServiceSafe -Name 'diagnosticshub.standardcollector.service' -StartType 'Disabled'
}

function Disable-Cortana {
    Write-Log 'Disabling Cortana and web search in the taskbar...'
    $searchPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-RegValue -Path $searchPolicy -Name 'AllowCortana' -Value 0 | Out-Null
    Set-RegValue -Path $searchPolicy -Name 'DisableWebSearch' -Value 1 | Out-Null
    Set-RegValue -Path $searchPolicy -Name 'ConnectedSearchUseWeb' -Value 0 | Out-Null
    Set-RegValue -Path $searchPolicy -Name 'AllowSearchToUseLocation' -Value 0 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent' -Value 0 | Out-Null
}

function Disable-BackgroundApps {
    Write-Log 'Disabling background apps globally...'
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BackgroundAppGlobalToggle' -Value 0 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name 'LetAppsRunInBackground' -Value 2 | Out-Null
}

function Disable-ConsumerFeatures {
    Write-Log 'Disabling consumer experiences, suggestions and ads...'
    $cloud = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    Set-RegValue -Path $cloud -Name 'DisableWindowsConsumerFeatures' -Value 1 | Out-Null
    Set-RegValue -Path $cloud -Name 'DisableSoftLanding' -Value 1 | Out-Null
    Set-RegValue -Path $cloud -Name 'DisableTailoredExperiencesWithDiagnosticData' -Value 1 | Out-Null

    $cdm = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    $cdmValues = @{
        'ContentDeliveryAllowed'         = 0
        'OemPreInstalledAppsEnabled'     = 0
        'PreInstalledAppsEnabled'        = 0
        'PreInstalledAppsEverEnabled'    = 0
        'SilentInstalledAppsEnabled'     = 0
        'SubscribedContent-338388Enabled' = 0
        'SubscribedContent-338389Enabled' = 0
        'SubscribedContent-338393Enabled' = 0
        'SubscribedContent-353694Enabled' = 0
        'SubscribedContent-353696Enabled' = 0
        'SystemPaneSuggestionsEnabled'   = 0
        'RotatingLockScreenOverlayEnabled' = 0
    }
    foreach ($entry in $cdmValues.GetEnumerator()) {
        Set-RegValue -Path $cdm -Name $entry.Key -Value $entry.Value | Out-Null
    }

    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSyncProviderNotifications' -Value 0 | Out-Null
}

function Disable-ActivityHistory {
    Write-Log 'Disabling activity history...'
    $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-RegValue -Path $sys -Name 'EnableActivityFeed' -Value 0 | Out-Null
    Set-RegValue -Path $sys -Name 'PublishUserActivities' -Value 0 | Out-Null
    Set-RegValue -Path $sys -Name 'UploadUserActivities' -Value 0 | Out-Null
}

function Disable-Widgets {
    Write-Log 'Disabling Widgets and News and Interests...'
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds' -Value 0 | Out-Null
    Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0 | Out-Null
}

function Disable-Copilot {
    Write-Log 'Disabling Windows Copilot...'
    Set-RegValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1 | Out-Null
}

function Disable-Recall {
    Write-Log 'Disabling Windows Recall and AI data analysis...'
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Value 1 | Out-Null
    Set-RegValue -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Value 1 | Out-Null
    Set-RegValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'AllowRecallEnablement' -Value 0 | Out-Null
}

function Disable-OneDriveAutostart {
    Write-Log 'Removing OneDrive autostart entry...'
    $runKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    try {
        $runProps = Get-ItemProperty -Path $runKey -ErrorAction Stop
        if ($runProps.PSObject.Properties.Name -contains 'OneDrive') {
            Remove-ItemProperty -Path $runKey -Name 'OneDrive' -ErrorAction Stop
            Write-Log 'OneDrive autostart entry removed' 'OK'
        } else {
            Write-Log 'OneDrive autostart entry not present, skipped'
        }
    } catch {
        Write-Log ('OneDrive autostart failed: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Invoke-DebloatTweaks {
    Write-Log '===== Debloat and Services: applying selected tweaks ====='
    if ($chkBloatBing.IsChecked -or $chkBloat3D.IsChecked -or $chkBloatGames.IsChecked -or $chkBloatMisc.IsChecked -or $chkBloatCortana.IsChecked) {
        Remove-BloatApps
    }
    if ($chkTelemetry.IsChecked)      { Disable-Telemetry }
    if ($chkServices.IsChecked)       { Disable-ExtraServices }
    if ($chkCortana.IsChecked)        { Disable-Cortana }
    if ($chkBackgroundApps.IsChecked) { Disable-BackgroundApps }
    if ($chkConsumer.IsChecked)       { Disable-ConsumerFeatures }
    if ($chkActivity.IsChecked)       { Disable-ActivityHistory }
    if ($chkWidgets.IsChecked)        { Disable-Widgets }
    if ($chkCopilot.IsChecked)        { Disable-Copilot }
    if ($chkRecall.IsChecked)         { Disable-Recall }
    if ($chkOneDrive.IsChecked)       { Disable-OneDriveAutostart }
    Write-Log '===== Debloat and Services: done =====' 'OK'
}

# ----------------------------------------------------------------------------
# System clean
# ----------------------------------------------------------------------------
function Clear-TempFiles {
    Write-Log 'Clearing temp files...'
    Clear-PathSafe -Path $env:TEMP -Label 'User temp'
    Clear-PathSafe -Path (Join-Path $env:WINDIR 'Temp') -Label 'Windows temp'
    Clear-PathSafe -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache') -Label 'IE / Edge cache'
}

function Clear-WindowsUpdateCache {
    Write-Log 'Clearing Windows Update cache...'
    try {
        Stop-Service -Name 'wuauserv' -Force -ErrorAction SilentlyContinue
        Stop-Service -Name 'bits' -Force -ErrorAction SilentlyContinue

        Clear-PathSafe -Path (Join-Path $env:WINDIR 'SoftwareDistribution\Download') -Label 'Windows Update download cache'

        Start-Service -Name 'bits' -ErrorAction SilentlyContinue
        Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
        Write-Log 'Windows Update services restarted' 'OK'
    } catch {
        Write-Log ('Windows Update cache cleanup failed: {0}' -f $_.Exception.Message) 'ERROR'
        Start-Service -Name 'bits' -ErrorAction SilentlyContinue
        Start-Service -Name 'wuauserv' -ErrorAction SilentlyContinue
    }
}

function Clear-PrefetchCache {
    Write-Log 'Clearing prefetch cache...'
    Clear-PathSafe -Path (Join-Path $env:WINDIR 'Prefetch') -Label 'Prefetch'
    Write-Log 'Prefetch repopulates itself over the next boots' 'INFO'
}

function Clear-DeliveryOptimization {
    Write-Log 'Clearing Delivery Optimization cache...'
    try {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
        Write-Log 'Delivery Optimization cache cleared' 'OK'
    } catch {
        Clear-PathSafe -Path (Join-Path $env:WINDIR 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache') -Label 'Delivery Optimization cache'
    }
}

function Clear-ErrorReports {
    Write-Log 'Clearing Windows Error Reporting data...'
    Clear-PathSafe -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive') -Label 'WER ReportArchive'
    Clear-PathSafe -Path (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue') -Label 'WER ReportQueue'
    Clear-PathSafe -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER') -Label 'WER user reports'
}

function Clear-RecycleBinSafe {
    Write-Log 'Emptying Recycle Bin...'
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        Write-Log 'Recycle Bin emptied' 'OK'
    } catch {
        Write-Log ('Recycle Bin: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Clear-DnsCache {
    Write-Log 'Flushing DNS cache...'
    try {
        & ipconfig.exe /flushdns 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'DNS cache flushed' 'OK'
        } else {
            Write-Log 'DNS cache flush returned a non zero exit code' 'WARN'
        }
    } catch {
        Write-Log ('DNS flush failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Disable-Hibernation {
    Write-Log 'Disabling hibernation...'
    & powercfg.exe /hibernate off 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Hibernation disabled, hiberfil.sys removed, Fast Startup is now off' 'OK'
    } else {
        Write-Log 'Could not disable hibernation' 'ERROR'
    }
}

function Invoke-FullCleanup {
    Write-Log '===== System Clean: running full cleanup ====='
    Clear-TempFiles
    Clear-WindowsUpdateCache
    Clear-PrefetchCache
    Clear-DeliveryOptimization
    Clear-ErrorReports
    Clear-RecycleBinSafe
    Clear-DnsCache
    Write-Log '===== System Clean: done =====' 'OK'
}

# ----------------------------------------------------------------------------
# Safety: system restore point
# ----------------------------------------------------------------------------
function New-RestorePointNow {
    Write-Log 'Creating system restore point...'
    try {
        Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
        $description = 'BaldyBeast Optimizer {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm')
        Checkpoint-Computer -Description $description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Log ('Restore point created: {0}' -f $description) 'OK'
        return $true
    } catch {
        Write-Log ('Restore point failed: {0}' -f $_.Exception.Message) 'ERROR'
        Write-Log 'Windows allows one restore point every 10 hours. An existing recent point still protects you.' 'WARN'
        return $false
    }
}

# ----------------------------------------------------------------------------
# One click preset
# ----------------------------------------------------------------------------
function Start-OptimizeAll {
    Write-Log '===== OPTIMIZE EVERYTHING (GAMING READY) ====='

    $answer = 'Yes'
    try {
        $answer = [System.Windows.MessageBox]::Show(
            $script:Window,
            "Create a system restore point first?`n`nYes    = create restore point, then optimize`nNo     = optimize without restore point`nCancel = do nothing",
            'Optimize Everything (Gaming Ready)',
            'YesNoCancel',
            'Question')
    } catch {
        $answer = 'Yes'
    }

    if ($answer -eq 'Cancel') {
        Write-Log 'Optimization cancelled by user' 'WARN'
        return
    }

    if ($answer -eq 'Yes') {
        if (-not (New-RestorePointNow)) {
            if (-not (Confirm-Action 'Continue without restore point?' 'The restore point could not be created. Apply the tweaks anyway?')) {
                Write-Log 'Optimization cancelled by user' 'WARN'
                return
            }
        }
    }

    # Select the recommended set so the GUI reflects what is being applied
    $recommended = @(
        'chkPowerPlan', 'chkMouseAccel', 'chkGameDVR', 'chkFullscreen', 'chkGameMode',
        'chkHAGS', 'chkMmcss', 'chkUsbSuspend', 'chkVisualFx',
        'chkBloatBing', 'chkBloat3D', 'chkBloatGames', 'chkBloatCortana',
        'chkTelemetry', 'chkServices', 'chkCortana', 'chkBackgroundApps',
        'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall'
    )
    foreach ($controlName in $recommended) {
        $control = $script:Window.FindName($controlName)
        if ($null -ne $control) { $control.IsChecked = $true }
    }

    Invoke-GamingTweaks
    Invoke-DebloatTweaks

    Write-Log '===== GAMING READY: all selected tweaks applied =====' 'OK'

    if ($script:NeedsReboot) {
        try {
            $restart = [System.Windows.MessageBox]::Show(
                $script:Window,
                'A restart is required for HAGS and some power changes to take effect. Restart now?',
                'Restart required',
                'YesNo',
                'Warning')
            if ($restart -eq 'Yes') {
                Write-Log 'Restarting the computer...'
                Restart-Computer -Force
            }
        } catch { }
    }
}

# ----------------------------------------------------------------------------
# Build the WPF window
# ----------------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = $xamlA + $xamlB

try {
    $window = [System.Windows.Markup.XamlReader]::Parse($xaml)
} catch {
    Write-Host ('[!] XAML parse error: {0}' -f $_.Exception.Message) -ForegroundColor Red
    try {
        [System.Windows.MessageBox]::Show(
            ('XAML parse error: {0}' -f $_.Exception.Message),
            'BALDYBEAST OPTIMIZER',
            'OK',
            'Error') | Out-Null
    } catch { }
    return
}

$script:Window = $window

# Wire every named control into script scope
$controlNames = @(
    'txtBanner', 'txtSubtitle', 'txtAbout', 'txtLog', 'tabMain',
    'btnRestorePoint', 'btnReboot', 'btnOptimizeAll', 'btnClearLog',
    'btnApplyGaming', 'btnApplyDebloat', 'btnSelectAllDebloat',
    'chkPowerPlan', 'chkMouseAccel', 'chkGameDVR', 'chkFullscreen', 'chkGameMode',
    'chkHAGS', 'chkMmcss', 'chkUsbSuspend', 'chkVisualFx',
    'chkBloatBing', 'chkBloat3D', 'chkBloatGames', 'chkBloatMisc', 'chkBloatCortana',
    'chkTelemetry', 'chkServices', 'chkCortana', 'chkBackgroundApps',
    'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall', 'chkOneDrive',
    'btnCleanTemp', 'btnCleanWU', 'btnCleanPrefetch', 'btnCleanDO',
    'btnCleanWER', 'btnCleanRecycle', 'btnCleanDNS', 'btnCleanAll', 'btnDisableHibernation'
)

$missingNames = @()
foreach ($controlName in $controlNames) {
    $control = $window.FindName($controlName)
    if ($null -eq $control) {
        $missingNames += $controlName
    } else {
        Set-Variable -Name $controlName -Value $control -Scope Script
    }
}

$script:LogBox = $txtLog

# Header content
$txtBanner.Text = Get-BaldyBanner
$txtSubtitle.Text = ('Windows 10 / 11 gaming optimizer, debloat and cleanup utility   |   v{0}' -f $script:AppVersion)

$aboutText = @"
BALDYBEAST OPTIMIZER v$($script:AppVersion)

Single file Windows 10 / 11 gaming optimization, debloat and cleanup utility.
Pure PowerShell + WPF. No external DLLs, no installers, no background services.

Quick start:
  1. Click "Create Restore Point" so you can always roll back.
  2. Tick the tweaks you want, or hit "Optimize Everything (Gaming Ready)".
  3. Watch the Console Log. Restart when the tool asks for one.

One line install from GitHub:
  irm "$($script:RepoRawUrl)" | iex

Safety notes:
  - Every change is logged to the Console Log and to $($script:LogFile).
  - Bloatware removal is opt-in per category. Gaming Services and Game Bar are kept.
  - Telemetry, background apps and Cortana are disabled by policy, not deleted.
  - The tool does not touch personal files, browsers, passwords or network settings.

Author: BaldyBeast   |   License: MIT   |   Use at your own risk.
"@
$txtAbout.Text = $aboutText

# ----------------------------------------------------------------------------
# Event handlers
# ----------------------------------------------------------------------------
$btnRestorePoint.Add_Click({ [void](New-RestorePointNow) })

$btnReboot.Add_Click({
    if (Confirm-Action 'Restart PC' 'Restart the computer now to finish applying the tweaks?') {
        Write-Log 'Restarting the computer...'
        Restart-Computer -Force
    }
})

$btnOptimizeAll.Add_Click({ Start-OptimizeAll })

$btnApplyGaming.Add_Click({ Invoke-GamingTweaks })
$btnApplyDebloat.Add_Click({ Invoke-DebloatTweaks })

$btnSelectAllDebloat.Add_Click({
    $recommendedDebloat = @(
        'chkBloatBing', 'chkBloat3D', 'chkBloatGames', 'chkBloatCortana',
        'chkTelemetry', 'chkServices', 'chkCortana', 'chkBackgroundApps',
        'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall'
    )
    foreach ($controlName in $recommendedDebloat) {
        $control = $window.FindName($controlName)
        if ($null -ne $control) { $control.IsChecked = $true }
    }
    Write-Log 'Recommended debloat selection applied to the checkboxes' 'OK'
})

$btnCleanTemp.Add_Click({ Clear-TempFiles })
$btnCleanWU.Add_Click({ Clear-WindowsUpdateCache })
$btnCleanPrefetch.Add_Click({ Clear-PrefetchCache })
$btnCleanDO.Add_Click({ Clear-DeliveryOptimization })
$btnCleanWER.Add_Click({ Clear-ErrorReports })
$btnCleanRecycle.Add_Click({ Clear-RecycleBinSafe })
$btnCleanDNS.Add_Click({ Clear-DnsCache })

$btnCleanAll.Add_Click({
    if (Confirm-Action 'Run Full Cleanup' 'Run every cleanup step now? This deletes temp files, update caches and the Recycle Bin contents.') {
        Invoke-FullCleanup
    }
})

$btnDisableHibernation.Add_Click({
    if (Confirm-Action 'Disable Hibernation' 'Disable hibernation? This deletes hiberfil.sys and turns off Fast Startup. You can turn it back on with: powercfg /hibernate on') {
        Disable-Hibernation
    }
})

$btnClearLog.Add_Click({ $txtLog.Clear() })

# ----------------------------------------------------------------------------
# Startup log
# ----------------------------------------------------------------------------
Write-Log ('BALDYBEAST OPTIMIZER v{0} started' -f $script:AppVersion) 'OK'
try {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    Write-Log ('System: {0} (build {1})' -f $osInfo.Caption, $osInfo.BuildNumber)
} catch {
    Write-Log 'System information unavailable' 'WARN'
}

$principalCheck = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
if ($principalCheck.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log 'Running with administrator rights' 'OK'
} else {
    Write-Log 'NOT running as administrator: system tweaks will fail' 'ERROR'
}

if ($missingNames.Count -gt 0) {
    Write-Log ('Missing XAML controls: {0}' -f ($missingNames -join ', ')) 'ERROR'
} else {
    Write-Log ('All {0} GUI controls wired successfully' -f $controlNames.Count) 'OK'
}

# ----------------------------------------------------------------------------
# Validation hook (BALDYBEAST_VALIDATE=1) or show the GUI
# ----------------------------------------------------------------------------
if ($script:ValidateMode) {
    Write-Host (Get-BaldyBanner) -ForegroundColor Yellow
    Write-Host ''

    # Safe self-test: exercise the registry helper against a throwaway key
    $testKey = 'HKCU:\Software\BaldyBeastValidateTest'
    try {
        $test1 = Set-RegValue -Path $testKey -Name 'DwordTest' -Value 2
        $test2 = Set-RegValue -Path $testKey -Name 'BinaryTest' -Value ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) -Type 'Binary'
        $test3 = Set-RegValue -Path $testKey -Name 'StringTest' -Value 'ok' -Type 'String'
        $test4 = (Get-BaldyBanner) -match '######'
        if ($test1 -and $test2 -and $test3 -and $test4) {
            Write-Host 'SELF-TEST OK - registry helper (DWord, Binary, String) and banner generator work' -ForegroundColor Green
        } else {
            Write-Host 'SELF-TEST FAILED' -ForegroundColor Red
        }
    } finally {
        Remove-Item -Path $testKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($missingNames.Count -gt 0) {
        Write-Host ('VALIDATION FAILED - missing controls: {0}' -f ($missingNames -join ', ')) -ForegroundColor Red
    } else {
        Write-Host 'VALIDATION OK - XAML parsed, all controls wired, functions defined' -ForegroundColor Green
    }
    return
}

Write-Log 'GUI ready. Create a restore point first, then apply your tweaks.' 'INFO'
[void]$window.ShowDialog()
