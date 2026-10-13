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

$script:AppVersion   = '1.1.0'
$script:RepoRawUrl   = 'https://raw.githubusercontent.com/BaldyBeast/BALDYBEAST-OPTIMIZER/main/Optimize.ps1'
$script:LogFile      = Join-Path $env:TEMP 'BaldyBeast-Optimizer.log'
$script:LogBox       = $null
$script:Window       = $null
$script:NeedsReboot  = $false
$script:ValidateMode = ($env:BALDYBEAST_VALIDATE -eq '1')
$script:BackupRoot   = Join-Path $env:LOCALAPPDATA 'BaldyBeast\backups'
$script:ProfileRoot  = Join-Path $env:LOCALAPPDATA 'BaldyBeast\profiles'
$script:BackupFile   = $null
$script:LatestVersion = $null

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
        Backup-RegValue -Path $Path -Name $Name
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
        Backup-Service -Name $Name
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
        Backup-Task -TaskName $name -TaskPath $folder
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
      <Style.Triggers>
        <DataTrigger Binding="{Binding Tag, RelativeSource={RelativeSource Self}}" Value="Safe">
          <Setter Property="Foreground" Value="#FF7CE38B"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding Tag, RelativeSource={RelativeSource Self}}" Value="Advanced">
          <Setter Property="Foreground" Value="#FFF5A97F"/>
        </DataTrigger>
      </Style.Triggers>
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
        <StackPanel Orientation="Horizontal" Margin="2,6,0,0">
          <TextBlock Text="RISK" Foreground="#FF6B6B88" FontSize="11" Margin="0,0,8,0"/>
          <TextBlock Text="Safe" Foreground="#FF7CE38B" FontSize="11" Margin="0,0,12,0"/>
          <TextBlock Text="Recommended" Foreground="#FFE8E8F0" FontSize="11" Margin="0,0,12,0"/>
          <TextBlock Text="Advanced" Foreground="#FFF5A97F" FontSize="11" Margin="0,0,12,0"/>
          <TextBlock Text="hover any option for what it does" Foreground="#FF6B6B88" FontSize="11"/>
        </StackPanel>
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

      <!-- ================= HARDWARE ================= -->
      <TabItem Header="Hardware" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="System Information"/>
                <TextBox x:Name="txtHardware" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap"
                         FontFamily="Consolas" FontSize="12.5" Background="#FF0D0D14" Foreground="#FFB8D8F0"
                         BorderBrush="#FF3A3A52" Padding="10" MinHeight="270"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                <Button x:Name="btnRefreshHw" Style="{StaticResource DarkButton}" Content="Refresh"
                        HorizontalAlignment="Left" Margin="0,10,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= PROFILES ================= -->
      <TabItem Header="Profiles" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Built-in Presets"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Presets only tick the checkboxes so you can review them. Press an Apply button afterwards to actually run them."/>
                <WrapPanel>
                  <Button x:Name="btnPresetCompetitive" Style="{StaticResource DarkButton}" Content="Competitive FPS" Margin="0,0,8,8"/>
                  <Button x:Name="btnPresetStreaming" Style="{StaticResource DarkButton}" Content="Streaming" Margin="0,0,8,8"/>
                  <Button x:Name="btnPresetCleanInstall" Style="{StaticResource DarkButton}" Content="Clean Install Debloat" Margin="0,0,8,8"/>
                  <Button x:Name="btnPresetUncheckAll" Style="{StaticResource DarkButton}" Content="Uncheck Everything" Margin="0,0,8,8"/>
                </WrapPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Your Profiles"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Profiles store which boxes are ticked. They live in %LOCALAPPDATA%\BaldyBeast\profiles as JSON you can share."/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                  <TextBox x:Name="txtProfileName" Width="250" Padding="7" FontSize="13"
                           Background="#FF0D0D14" Foreground="#FFE8E8F0" BorderBrush="#FF3A3A52"
                           ToolTip="Profile name"/>
                  <Button x:Name="btnSaveProfile" Style="{StaticResource DarkButton}" Content="Save Current Selection" Margin="8,0,0,0"/>
                </StackPanel>
                <ListBox x:Name="listProfiles" Height="150" Background="#FF0D0D14" Foreground="#FFE8E8F0"
                         BorderBrush="#FF3A3A52" FontFamily="Consolas" FontSize="12"/>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                  <Button x:Name="btnLoadProfile" Style="{StaticResource AccentButton}" Content="Load Selected" Margin="0,0,8,0"/>
                  <Button x:Name="btnDeleteProfile" Style="{StaticResource DangerButton}" Content="Delete Selected"/>
                </StackPanel>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= BACKUPS ================= -->
      <TabItem Header="Backups" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Rollback Points"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Every registry, service and scheduled task change is recorded automatically before it is applied. Reverting restores the exact previous state. App removals and power plan switches are not covered here, use System Restore or reinstall the app for those."/>
                <ListBox x:Name="listBackups" Height="220" Background="#FF0D0D14" Foreground="#FFE8E8F0"
                         BorderBrush="#FF3A3A52" FontFamily="Consolas" FontSize="12"/>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                  <Button x:Name="btnRevertBackup" Style="{StaticResource DangerButton}" Content="Revert Selected Backup" Margin="0,0,8,0"/>
                  <Button x:Name="btnRefreshBackups" Style="{StaticResource DarkButton}" Content="Refresh List" Margin="0,0,8,0"/>
                  <Button x:Name="btnOpenBackupFolder" Style="{StaticResource DarkButton}" Content="Open Backup Folder"/>
                </StackPanel>
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
                <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
                  <Button x:Name="btnCheckUpdate" Style="{StaticResource DarkButton}" Content="Check for Updates" Margin="0,0,8,0"/>
                  <Button x:Name="btnDoUpdate" Style="{StaticResource AccentButton}" Content="Download and Restart" IsEnabled="False"/>
                </StackPanel>
                <TextBlock x:Name="txtUpdateStatus" Style="{StaticResource DimText}" Text="Update status: not checked yet"/>
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
# Rollback backups: every registry, service and task change is recorded before
# it is applied so it can be reverted from the Backups tab
# ----------------------------------------------------------------------------
function Get-BackupStore {
    if ($null -eq $script:BackupFile) {
        if (-not (Test-Path -LiteralPath $script:BackupRoot)) {
            New-Item -Path $script:BackupRoot -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        }
        $script:BackupFile = Join-Path $script:BackupRoot ('backup-{0}.jsonl' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -Path $script:BackupFile -ItemType File -Force -ErrorAction Stop | Out-Null
        Write-Log ('Rollback point file: {0}' -f $script:BackupFile)
    }
    return $script:BackupFile
}

function Add-BackupRecord {
    param([Parameter(Mandatory = $true)][hashtable]$Record)
    try {
        $file = Get-BackupStore
        $Record['Timestamp'] = (Get-Date).ToString('s')
        $line = [pscustomobject]$Record | ConvertTo-Json -Compress -Depth 4
        Add-Content -LiteralPath $file -Value $line -Encoding UTF8
    } catch {
        Write-Log ('Backup record failed: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Read-BackupRecords {
    param([Parameter(Mandatory = $true)][string]$File)
    # One JSON object per line keeps every record flat. Windows PowerShell 5.1
    # wraps whole JSON arrays when they are parsed, which broke array storage.
    $records = @()
    foreach ($line in (Get-Content -LiteralPath $File -ErrorAction Stop)) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            $records += ($line | ConvertFrom-Json)
        }
    }
    return $records
}

function Backup-RegValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )
    try {
        $keyExisted   = Test-Path -LiteralPath $Path
        $valueExisted = $false
        $oldValue     = $null
        $oldType      = 'String'

        if ($keyExisted) {
            $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
            if ($null -ne $key -and ($key.GetValueNames() -contains $Name)) {
                $valueExisted = $true
                $oldValue     = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
                $oldType      = $key.GetValueKind($Name).ToString()
            }
        }

        Add-BackupRecord -Record @{
            Kind        = 'Registry'
            Path        = $Path
            Name        = $Name
            KeyExisted  = [bool]$keyExisted
            ValueExisted = [bool]$valueExisted
            OldValue    = $oldValue
            OldType     = $oldType
        }
    } catch {
        Write-Log ('Backup capture failed for {0}\{1}' -f $Path, $Name) 'WARN'
    }
}

function Backup-Service {
    param([Parameter(Mandatory = $true)][string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $svc) { return }
        Add-BackupRecord -Record @{
            Kind         = 'Service'
            Name         = $Name
            OldStartType = $svc.StartType.ToString()
            OldStatus    = $svc.Status.ToString()
        }
    } catch { }
}

function Backup-Task {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$TaskPath
    )
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -TaskPath $TaskPath -ErrorAction SilentlyContinue
        if ($null -eq $task) { return }
        Add-BackupRecord -Record @{
            Kind      = 'Task'
            Name      = $TaskName
            Path      = $TaskPath
            OldState  = $task.State.ToString()
        }
    } catch { }
}

function Restore-BackupFile {
    param([Parameter(Mandatory = $true)][string]$File)

    try {
        $records = @(Read-BackupRecords -File $File)
    } catch {
        Write-Log ('Could not read backup file: {0}' -f $_.Exception.Message) 'ERROR'
        return $false
    }

    $allOk = $true
    for ($i = $records.Count - 1; $i -ge 0; $i--) {
        $rec = $records[$i]
        try {
            switch ($rec.Kind) {
                'Registry' {
                    if (-not $rec.KeyExisted) {
                        Remove-Item -LiteralPath $rec.Path -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Log ('Reverted: removed key we created {0}' -f $rec.Path) 'OK'
                    } elseif (-not $rec.ValueExisted) {
                        Remove-ItemProperty -LiteralPath $rec.Path -Name $rec.Name -Force -ErrorAction SilentlyContinue
                        Write-Log ('Reverted: removed {0}\{1}' -f $rec.Path, $rec.Name) 'OK'
                    } else {
                        if (-not (Test-Path -LiteralPath $rec.Path)) {
                            New-Item -Path $rec.Path -Force -ErrorAction Stop | Out-Null
                        }
                        $restoreValue = $rec.OldValue
                        if ($rec.OldType -eq 'Binary') { $restoreValue = [byte[]]$rec.OldValue }
                        New-ItemProperty -LiteralPath $rec.Path -Name $rec.Name -Value $restoreValue -PropertyType $rec.OldType -Force -ErrorAction Stop | Out-Null
                        Write-Log ('Reverted: {0}\{1} restored' -f $rec.Path, $rec.Name) 'OK'
                    }
                }
                'Service' {
                    Set-Service -Name $rec.Name -StartupType $rec.OldStartType -ErrorAction Stop
                    if ($rec.OldStatus -eq 'Running') {
                        Start-Service -Name $rec.Name -ErrorAction SilentlyContinue
                    }
                    Write-Log ('Reverted: service {0} restored' -f $rec.Name) 'OK'
                }
                'Task' {
                    if ($rec.OldState -eq 'Enabled') {
                        Enable-ScheduledTask -TaskName $rec.Name -TaskPath $rec.Path -ErrorAction Stop | Out-Null
                    } else {
                        Disable-ScheduledTask -TaskName $rec.Name -TaskPath $rec.Path -ErrorAction Stop | Out-Null
                    }
                    Write-Log ('Reverted: task {0} restored' -f $rec.Name) 'OK'
                }
            }
        } catch {
            Write-Log ('Revert step failed ({0}): {1}' -f $rec.Kind, $_.Exception.Message) 'ERROR'
            $allOk = $false
        }
    }
    return $allOk
}

function Update-BackupList {
    if ($null -eq $listBackups) { return }
    $listBackups.Items.Clear()
    if (-not (Test-Path -LiteralPath $script:BackupRoot)) { return }

    $files = Get-ChildItem -LiteralPath $script:BackupRoot -Filter 'backup-*.jsonl' -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending

    foreach ($file in $files) {
        $count = 0
        try {
            $count = @(Read-BackupRecords -File $file.FullName).Count
        } catch { }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = ('{0}   ({1} recorded changes)' -f $file.BaseName, $count)
        $item.Tag = $file.FullName
        [void]$listBackups.Items.Add($item)
    }
}

# ----------------------------------------------------------------------------
# Profiles: save and load checkbox selections as JSON
# ----------------------------------------------------------------------------
function Get-AllTweakNames {
    return @(
        'chkPowerPlan', 'chkMouseAccel', 'chkGameDVR', 'chkFullscreen', 'chkGameMode',
        'chkHAGS', 'chkMmcss', 'chkUsbSuspend', 'chkVisualFx',
        'chkBloatBing', 'chkBloat3D', 'chkBloatGames', 'chkBloatMisc', 'chkBloatCortana',
        'chkTelemetry', 'chkServices', 'chkCortana', 'chkBackgroundApps',
        'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall', 'chkOneDrive'
    )
}

function Set-CheckboxSelection {
    param(
        [Parameter(Mandatory = $true)][string[]]$Names,
        [bool]$State = $true
    )
    foreach ($controlName in $Names) {
        $control = $script:Window.FindName($controlName)
        if ($null -ne $control) { $control.IsChecked = $State }
    }
}

function Save-CurrentProfile {
    param([Parameter(Mandatory = $true)][string]$Name)

    $cleanName = ($Name -replace '[^A-Za-z0-9 _-]', '').Trim()
    if ([string]::IsNullOrWhiteSpace($cleanName)) {
        Write-Log 'Enter a profile name first' 'WARN'
        return
    }

    try {
        if (-not (Test-Path -LiteralPath $script:ProfileRoot)) {
            New-Item -Path $script:ProfileRoot -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        $checked = @()
        foreach ($controlName in (Get-AllTweakNames)) {
            $control = $script:Window.FindName($controlName)
            if ($null -ne $control -and $control.IsChecked -eq $true) { $checked += $controlName }
        }

        $profile = [pscustomobject]@{
            Name       = $cleanName
            Version    = $script:AppVersion
            CreatedUtc = (Get-Date).ToUniversalTime().ToString('s')
            Checked    = $checked
        }

        $file = Join-Path $script:ProfileRoot ($cleanName + '.json')
        ConvertTo-Json -InputObject $profile -Depth 4 | Set-Content -LiteralPath $file -Encoding UTF8
        Write-Log ('Profile saved: {0} ({1} tweaks selected)' -f $cleanName, $checked.Count) 'OK'
        Update-ProfileList
    } catch {
        Write-Log ('Profile save failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Load-Profile {
    param([Parameter(Mandatory = $true)][string]$Name)

    $file = Join-Path $script:ProfileRoot ($Name + '.json')
    if (-not (Test-Path -LiteralPath $file)) {
        Write-Log ('Profile not found: {0}' -f $Name) 'WARN'
        return
    }

    try {
        $profile = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
        Set-CheckboxSelection -Names (Get-AllTweakNames) -State $false
        Set-CheckboxSelection -Names @($profile.Checked) -State $true
        Write-Log ('Profile loaded: {0} ({1} tweaks ticked)' -f $Name, @($profile.Checked).Count) 'OK'
        Write-Log 'Press an Apply button to actually run the ticked tweaks' 'INFO'
    } catch {
        Write-Log ('Profile load failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Remove-Profile {
    param([Parameter(Mandatory = $true)][string]$Name)
    try {
        $file = Join-Path $script:ProfileRoot ($Name + '.json')
        if (Test-Path -LiteralPath $file) {
            Remove-Item -LiteralPath $file -Force -ErrorAction Stop
            Write-Log ('Profile deleted: {0}' -f $Name) 'OK'
        }
        Update-ProfileList
    } catch {
        Write-Log ('Profile delete failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Update-ProfileList {
    if ($null -eq $listProfiles) { return }
    $listProfiles.Items.Clear()
    if (-not (Test-Path -LiteralPath $script:ProfileRoot)) { return }

    $files = Get-ChildItem -LiteralPath $script:ProfileRoot -Filter '*.json' -ErrorAction SilentlyContinue |
        Sort-Object Name

    foreach ($file in $files) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = $file.BaseName
        $item.Tag = $file.BaseName
        [void]$listProfiles.Items.Add($item)
    }
}

# ----------------------------------------------------------------------------
# Hardware dashboard
# ----------------------------------------------------------------------------
function Update-HardwareInfo {
    try {
        $os   = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $cpu  = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $gpu  = Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop | Select-Object -First 1
        $cs   = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue

        $uptime = (Get-Date) - $os.LastBootUpTime
        $lines = @()
        $lines += ('OS            : {0} (build {1})' -f $os.Caption, $os.BuildNumber)
        $lines += ('CPU           : {0}' -f $cpu.Name.Trim())
        $lines += ('Cores/Threads : {0} cores / {1} threads' -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
        $lines += ('GPU           : {0}' -f $gpu.Name)
        $lines += ('GPU driver    : {0}' -f $gpu.DriverVersion)
        $lines += ('Memory        : {0:N1} GB total / {1:N1} GB in use' -f ($cs.TotalPhysicalMemory / 1GB), (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 1KB / 1GB))

        foreach ($disk in $disks) {
            $lines += ('Disk {0,-9} : {1:N0} GB total / {2:N0} GB free' -f ($disk.DeviceID + ':'), ($disk.Size / 1GB), ($disk.FreeSpace / 1GB))
        }

        try {
            $pageFiles = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
            if ($pageFiles.Count -gt 0) {
                $lines += ('Page file     : {0} ({1} MB allocated)' -f $pageFiles[0].Name, $pageFiles[0].AllocatedBaseSize)
            } else {
                $lines += 'Page file     : system managed or not present'
            }
        } catch {
            $lines += 'Page file     : unknown'
        }

        $lines += ('Uptime        : {0}h {1}m' -f [int][math]::Floor($uptime.TotalHours), $uptime.Minutes)
        $lines += ('Computer name : {0}' -f $cs.Name)

        try {
            $plan = & powercfg.exe /getactivescheme 2>$null
            if ($plan -match '\((.+)\)') {
                $lines += ('Power plan    : {0}' -f $Matches[1])
            } elseif ($null -ne $plan) {
                $lines += ('Power plan    : {0}' -f ([string]$plan).Trim())
            }
        } catch {
            $lines += 'Power plan    : unknown'
        }

        $txtHardware.Text = ($lines -join [System.Environment]::NewLine)
        Write-Log 'Hardware info refreshed' 'OK'
    } catch {
        Write-Log ('Hardware info failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

# ----------------------------------------------------------------------------
# Self update
# ----------------------------------------------------------------------------
function Test-ForUpdate {
    try {
        $raw = Invoke-RestMethod -Uri $script:RepoRawUrl -TimeoutSec 8 -ErrorAction Stop
        $match = [regex]::Match([string]$raw, "AppVersion\s*=\s*'([0-9\.]+)'")

        if (-not $match.Success) {
            $txtUpdateStatus.Text = 'Update status: version marker not found in the GitHub file'
            return
        }

        $script:LatestVersion = [version]$match.Groups[1].Value
        $running = [version]$script:AppVersion

        if ($script:LatestVersion -gt $running) {
            $txtUpdateStatus.Text = ('Update status: v{0} is available (you run v{1})' -f $script:LatestVersion, $running)
            $btnDoUpdate.IsEnabled = $true
            Write-Log ('Update available: v{0}' -f $script:LatestVersion) 'WARN'
        } else {
            $txtUpdateStatus.Text = ('Update status: you are on the latest version (v{0})' -f $running)
            Write-Log 'Running the latest version' 'OK'
        }
    } catch {
        $txtUpdateStatus.Text = 'Update status: could not reach GitHub (offline?)'
        Write-Log 'Update check skipped, no connection to GitHub' 'WARN'
    }
}

function Install-Update {
    try {
        $raw = Invoke-RestMethod -Uri $script:RepoRawUrl -TimeoutSec 20 -ErrorAction Stop
        if ([string]$raw -notmatch 'BALDYBEAST OPTIMIZER') {
            throw 'downloaded file failed the content check'
        }

        $temp = Join-Path $env:TEMP 'BaldyBeast-Optimize-update.ps1'
        Set-Content -LiteralPath $temp -Value $raw -Encoding UTF8
        Write-Log 'Update downloaded, restarting with the new version...' 'OK'

        Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $temp) | Out-Null
        $window.Close()
    } catch {
        Write-Log ('Update failed: {0}' -f $_.Exception.Message) 'ERROR'
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
    'btnCleanWER', 'btnCleanRecycle', 'btnCleanDNS', 'btnCleanAll', 'btnDisableHibernation',
    'txtHardware', 'btnRefreshHw',
    'txtProfileName', 'listProfiles', 'btnSaveProfile', 'btnLoadProfile', 'btnDeleteProfile',
    'btnPresetCompetitive', 'btnPresetStreaming', 'btnPresetCleanInstall', 'btnPresetUncheckAll',
    'listBackups', 'btnRevertBackup', 'btnRefreshBackups', 'btnOpenBackupFolder',
    'btnCheckUpdate', 'btnDoUpdate', 'txtUpdateStatus'
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
  1. Click "Create Restore Point" so you can always roll back everything.
  2. Tick the tweaks you want (hover any option to see what it does), or hit
     "Optimize Everything (Gaming Ready)".
  3. Watch the Console Log. Restart when the tool asks for one.

Rollback:
  Every registry, service and task change is recorded automatically before it
  is applied. Open the Backups tab to restore the exact previous state of any
  session. App removals and power plan switches are not covered there.

Profiles:
  Save your checkbox selection as a JSON profile in
  %LOCALAPPDATA%\BaldyBeast\profiles and share the file with friends.

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

$btnRefreshHw.Add_Click({ Update-HardwareInfo })

$btnSaveProfile.Add_Click({ Save-CurrentProfile -Name $txtProfileName.Text })
$btnLoadProfile.Add_Click({
    if ($null -eq $listProfiles.SelectedItem) {
        Write-Log 'Select a profile in the list first' 'WARN'
        return
    }
    Load-Profile -Name ([string]$listProfiles.SelectedItem.Tag)
})
$btnDeleteProfile.Add_Click({
    if ($null -eq $listProfiles.SelectedItem) {
        Write-Log 'Select a profile in the list first' 'WARN'
        return
    }
    $profileName = [string]$listProfiles.SelectedItem.Tag
    if (Confirm-Action 'Delete profile' ('Delete the profile "{0}"?' -f $profileName)) {
        Remove-Profile -Name $profileName
    }
})

$btnPresetCompetitive.Add_Click({
    Set-CheckboxSelection -Names (Get-AllTweakNames) -State $false
    Set-CheckboxSelection -Names @('chkPowerPlan', 'chkMouseAccel', 'chkGameDVR', 'chkFullscreen', 'chkGameMode', 'chkHAGS', 'chkMmcss', 'chkUsbSuspend', 'chkVisualFx', 'chkTelemetry', 'chkBackgroundApps')
    Write-Log 'Preset Competitive FPS ticked. Review the Gaming tab, then press Apply Selected Gaming Tweaks' 'OK'
})
$btnPresetStreaming.Add_Click({
    Set-CheckboxSelection -Names (Get-AllTweakNames) -State $false
    Set-CheckboxSelection -Names @('chkPowerPlan', 'chkGameMode', 'chkMmcss', 'chkUsbSuspend', 'chkVisualFx', 'chkTelemetry', 'chkBackgroundApps')
    Write-Log 'Preset Streaming ticked (Game DVR and capture stay enabled for clips). Press Apply to run it' 'OK'
})
$btnPresetCleanInstall.Add_Click({
    Set-CheckboxSelection -Names (Get-AllTweakNames) -State $false
    Set-CheckboxSelection -Names @('chkBloatBing', 'chkBloat3D', 'chkBloatGames', 'chkBloatCortana', 'chkTelemetry', 'chkServices', 'chkCortana', 'chkBackgroundApps', 'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall')
    Write-Log 'Preset Clean Install Debloat ticked. Press Apply Selected Debloat Tweaks to run it' 'OK'
})
$btnPresetUncheckAll.Add_Click({
    Set-CheckboxSelection -Names (Get-AllTweakNames) -State $false
    Write-Log 'All tweak checkboxes cleared' 'OK'
})

$btnRevertBackup.Add_Click({
    if ($null -eq $listBackups.SelectedItem) {
        Write-Log 'Select a backup in the list first' 'WARN'
        return
    }
    $backupPath = [string]$listBackups.SelectedItem.Tag
    $question = 'Restore the previous state recorded in {0}?' -f [System.IO.Path]::GetFileName($backupPath)
    if (Confirm-Action 'Revert changes' $question) {
        Write-Log ('Reverting from {0} ...' -f [System.IO.Path]::GetFileName($backupPath))
        if (Restore-BackupFile -File $backupPath) {
            Write-Log 'Rollback completed. Reboot if services behave oddly.' 'OK'
            Update-HardwareInfo
        }
    }
})
$btnRefreshBackups.Add_Click({ Update-BackupList })
$btnOpenBackupFolder.Add_Click({
    if (-not (Test-Path -LiteralPath $script:BackupRoot)) {
        New-Item -Path $script:BackupRoot -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList $script:BackupRoot
})

$btnCheckUpdate.Add_Click({ Test-ForUpdate })
$btnDoUpdate.Add_Click({
    if (Confirm-Action 'Update BALDYBEAST OPTIMIZER' 'Download the newest version from GitHub and restart the tool?') {
        Install-Update
    }
})

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
# Risk badges and tooltips: one plain sentence per option
# ----------------------------------------------------------------------------
$script:TweakInfo = @{
    'chkPowerPlan'      = @('Safe', 'Keeps the CPU at full speed for games. Falls back to High Performance on Windows editions without Ultimate Performance.')
    'chkMouseAccel'     = @('Safe', 'Turns off Enhance Pointer Precision so mouse movement matches physical distance one to one. Standard for FPS players.')
    'chkGameMode'       = @('Safe', 'Lets Windows prioritize games and stops Game Bar popups.')
    'chkVisualFx'       = @('Safe', 'Trades window animations for responsiveness. Font smoothing stays on.')
    'chkUsbSuspend'     = @('Recommended', 'Stops Windows from sleeping USB devices so mouse polling stays steady. Slightly higher idle power draw.')
    'chkGameDVR'        = @('Recommended', 'Disables background recording and Game DVR capture hooks. Skip this if you use Xbox Game Bar to record clips.')
    'chkFullscreen'     = @('Recommended', 'Games render in exclusive fullscreen instead of a borderless hybrid, which lowers input lag.')
    'chkMmcss'          = @('Recommended', 'Removes the multimedia network throttling limit and raises the Games task GPU and IO priority.')
    'chkHAGS'           = @('Advanced', 'Lets the GPU manage its own memory scheduling. Needs a modern GPU driver and a reboot. Helps some rigs, hurts none.')
    'chkBloatBing'      = @('Recommended', 'Removes Bing News, Bing Weather, Get Help, Get Started and the Office Hub from all users.')
    'chkBloat3D'        = @('Recommended', 'Removes 3D Builder, 3D Viewer and the Mixed Reality Portal.')
    'chkBloatGames'     = @('Recommended', 'Removes Solitaire and the old Xbox Console Companion. Game Bar and Gaming Services stay installed.')
    'chkBloatMisc'      = @('Advanced', 'Removes consumer apps including Mail and Calendar. Skip this if you use them.')
    'chkBloatCortana'   = @('Recommended', 'Removes the Cortana app package.')
    'chkTelemetry'      = @('Recommended', 'Disables telemetry data collection, the DiagTrack service and CEIP scheduled tasks.')
    'chkServices'       = @('Recommended', 'Disables Maps Broker, Retail Demo and WMP Network Sharing. None of them are needed for gaming.')
    'chkCortana'        = @('Recommended', 'Disables Cortana and Bing web results inside the taskbar search.')
    'chkBackgroundApps' = @('Recommended', 'Stops Store apps from running silently in the background.')
    'chkConsumer'       = @('Recommended', 'Disables suggested apps, tips, ads in Start and tailored experiences.')
    'chkActivity'       = @('Recommended', 'Stops Windows from collecting and uploading your activity history.')
    'chkWidgets'        = @('Recommended', 'Removes the Widgets button and the News and Interests feed.')
    'chkCopilot'        = @('Recommended', 'Disables the Windows Copilot button and feature.')
    'chkRecall'         = @('Recommended', 'Prevents Windows Recall from snapshotting your screen and disables AI data analysis.')
    'chkOneDrive'       = @('Advanced', 'Stops OneDrive from starting with Windows. Your files are untouched and you can re-enable it anytime.')
}

foreach ($infoEntry in $script:TweakInfo.GetEnumerator()) {
    $infoControl = $window.FindName($infoEntry.Key)
    if ($null -ne $infoControl) {
        $infoControl.Tag = $infoEntry.Value[0]
        $infoControl.ToolTip = ('{0}: {1}' -f $infoEntry.Value[0].ToUpper(), $infoEntry.Value[1])
    }
}

# ----------------------------------------------------------------------------
# Startup initialization
# ----------------------------------------------------------------------------
Update-HardwareInfo
Update-ProfileList
Update-BackupList
Test-ForUpdate

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

    # Rollback round-trip: seed a value, overwrite through the backup-aware
    # helper, revert, and confirm the seed came back
    $rollbackKey = 'HKCU:\Software\BaldyBeastValidateTestRollback'
    try {
        New-Item -Path $rollbackKey -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $rollbackKey -Name 'Seed' -Value 5 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        Set-RegValue -Path $rollbackKey -Name 'Seed' -Value 9 | Out-Null
        $sessionBackup = $script:BackupFile
        $reverted = Restore-BackupFile -File $sessionBackup
        $seedKey = Get-Item -Path $rollbackKey -ErrorAction SilentlyContinue
        $seedNow = $null
        if ($null -ne $seedKey) { $seedNow = $seedKey.GetValue('Seed') }
        if ($reverted -and $seedNow -eq 5) {
            Write-Host 'ROLLBACK TEST OK - previous registry state restored exactly' -ForegroundColor Green
        } else {
            Write-Host ('ROLLBACK TEST FAILED - seed is [{0}], reverted flag [{1}]' -f $seedNow, $reverted) -ForegroundColor Red
        }
        Remove-Item -Path $rollbackKey -Recurse -Force -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($sessionBackup)) {
            Remove-Item -LiteralPath $sessionBackup -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host ('ROLLBACK TEST FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Remove-Item -Path $rollbackKey -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Profile round-trip: save a selection, clear it, load it back
    try {
        $probe = $window.FindName('chkPowerPlan')
        $probe.IsChecked = $true
        Save-CurrentProfile -Name 'selftest'
        $probe.IsChecked = $false
        Load-Profile -Name 'selftest'
        if ($probe.IsChecked -eq $true) {
            Write-Host 'PROFILE TEST OK - saved selection restored' -ForegroundColor Green
        } else {
            Write-Host 'PROFILE TEST FAILED - checkbox did not come back' -ForegroundColor Red
        }
        Remove-Profile -Name 'selftest'
        $probe.IsChecked = $false
    } catch {
        Write-Host ('PROFILE TEST FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
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
