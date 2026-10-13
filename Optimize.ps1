#Requires -Version 5.1
<#
    BALDYBEAST OPTIMIZER
    Windows 10 / 11 gaming optimization, debloat and cleanup utility.

    Run from disk  : powershell -ExecutionPolicy Bypass -File Optimize.ps1
    Run from GitHub: irm "https://raw.githubusercontent.com/BaldyBeast/BALDYBEAST-OPTIMIZER/main/Optimize.ps1" | iex

    Single file. No external DLLs. Pure PowerShell + WPF.
    Copyright (c) 2026 BaldyBeast. All rights reserved. License: MIT
#>

$ErrorActionPreference = 'Continue'

$script:AppVersion   = '1.5.0'
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
        Title="BALDYBEAST OPTIMIZER" Height="860" Width="1140"
        MinHeight="700" MinWidth="960" WindowStartupLocation="CenterScreen"
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
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="tabBd" Background="Transparent" BorderBrush="#FF3A3A52"
                    BorderThickness="1,1,1,0" CornerRadius="8,8,0,0" Margin="0,0,4,0" Padding="12,8">
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
        <Button x:Name="btnRestorePoint" Style="{StaticResource DarkButton}" Content="Create Restore Point" Margin="0,0,8,0"
                ToolTip="Creates a Windows System Restore point before you change anything. Recommended first step."/>
        <Button x:Name="btnReboot" Style="{StaticResource DarkButton}" Content="Restart PC" Margin="0,0,8,0"
                ToolTip="Restarts the PC so HAGS and power plan changes take effect."/>
        <Button x:Name="btnOptimizeAll" Style="{StaticResource AccentButton}" Content="Optimize Everything (Gaming Ready)"
                ToolTip="Ticks the recommended gaming and debloat options and applies them in one batch."/>
      </StackPanel>
    </Grid>

    <!-- Tabs -->
    <TabControl x:Name="tabMain" Grid.Row="2" Margin="18,8,18,0" Background="#FF1F1F2E"
                BorderBrush="#FF3A3A52" Padding="6">

      <!-- ================= GAMING TWEAKS ================= -->
      <TabItem Header="Gaming" Style="{StaticResource DarkTab}">
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

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Custom Power Plan (active plan)"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Fine tune the power plan you are on right now. CPU min at 100 percent keeps clocks high for lowest input lag, at the cost of idle power."/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,2">
                  <TextBlock Text="CPU min state %" Width="150" VerticalAlignment="Center" Foreground="#FFE8E8F0"/>
                  <Slider x:Name="sldCpuMin" Width="260" Minimum="0" Maximum="100" Value="100"
                          TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,2">
                  <TextBlock Text="CPU max state %" Width="150" VerticalAlignment="Center" Foreground="#FFE8E8F0"/>
                  <Slider x:Name="sldCpuMax" Width="260" Minimum="5" Maximum="100" Value="100"
                          TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,2">
                  <TextBlock Text="PCIe power saving" Width="150" VerticalAlignment="Center" Foreground="#FFE8E8F0"/>
                  <ComboBox x:Name="cmbPcie" Width="200" Padding="7" FontSize="13"
                            Background="#FF0D0D14" Foreground="#FFE8E8F0" BorderBrush="#FF3A3A52">
                    <ComboBoxItem Content="Off (best latency)" IsSelected="True"/>
                    <ComboBoxItem Content="Moderate"/>
                    <ComboBoxItem Content="Maximum power savings"/>
                  </ComboBox>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <TextBlock Text="Display off after (min)" Width="150" VerticalAlignment="Center" Foreground="#FFE8E8F0"/>
                  <Slider x:Name="sldDisplayOff" Width="260" Minimum="0" Maximum="60" Value="0"
                          TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center"/>
                </StackPanel>
                <Button x:Name="btnApplyPower" Style="{StaticResource AccentButton}" Content="Apply to Active Power Plan"
                        HorizontalAlignment="Left" Margin="0,4,0,0"/>
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
      <TabItem Header="Debloat" Style="{StaticResource DarkTab}">
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
                <CheckBox x:Name="chkClassicMenu" Style="{StaticResource DarkCheck}"
                          Content="Windows 11 classic right-click menu (needs Explorer restart)"/>
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
      <TabItem Header="Clean" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="RAM Cache (standby list)"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Releases file data Windows keeps cached in RAM. Useful right before launching a game so it gets clean memory instantly. Full memory breakdown lives in the Hardware tab."/>
                <Button x:Name="btnPurgeStandbyQuick" Style="{StaticResource DangerButton}" Content="Purge Standby List"
                        HorizontalAlignment="Left"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Windows Recall Snapshots (privacy)"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Deletes snapshot data Recall already captured on this PC. The Debloat tab has the toggle that stops new snapshots from being taken."/>
                <Button x:Name="btnWipeRecall" Style="{StaticResource DangerButton}" Content="Delete Recall Snapshot Data"
                        HorizontalAlignment="Left"/>
              </StackPanel>
            </Border>

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
                         BorderBrush="#FF3A3A52" Padding="10" MinHeight="220"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                <Button x:Name="btnRefreshHw" Style="{StaticResource DarkButton}" Content="Refresh"
                        HorizontalAlignment="Left" Margin="0,10,0,0"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Memory (RAMMap style)"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Standby list is file data Windows keeps cached in RAM. Purging it frees that cache instantly, which can smooth stutter when a game needs memory right now. Windows re-fills the cache afterwards, so app launches may feel slightly slower for a while."/>
                <WrapPanel>
                  <Button x:Name="btnPurgeStandby" Style="{StaticResource DangerButton}" Content="Purge Standby List" Margin="0,0,8,8"/>
                  <Button x:Name="btnMemoryRefresh" Style="{StaticResource DarkButton}" Content="Refresh Memory Info" Margin="0,0,8,8"/>
                </WrapPanel>
                <StackPanel Margin="0,8,0,0">
                  <CheckBox x:Name="chkMonitorEnable" Style="{StaticResource DarkCheck}"
                            Content="Auto-purge standby list while this tool is open"/>
                  <StackPanel Orientation="Horizontal">
                    <TextBlock Text="Purge when free RAM under (MB)" Width="190" VerticalAlignment="Center" Foreground="#FFE8E8F0"/>
                    <Slider x:Name="sldMonitorThreshold" Width="220" Minimum="500" Maximum="8000" Value="3000"
                            TickFrequency="500" IsSnapToTickEnabled="True" VerticalAlignment="Center"/>
                  </StackPanel>
                  <TextBlock x:Name="txtMonitorStatus" Style="{StaticResource DimText}" Text="Monitor idle."/>
                </StackPanel>
                <TextBox x:Name="txtMemory" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap"
                         FontFamily="Consolas" FontSize="12" Background="#FF0D0D14" Foreground="#FFB8D8F0"
                         BorderBrush="#FF3A3A52" Padding="10" MinHeight="230" Margin="0,6,0,0"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
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

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Windows System Restore Points"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="The full Windows safety net. Restoring rolls back system files, drivers and registry to that moment and restarts the PC. Use the rollback points above for single tweaks, this one for big changes."/>
                <ListBox x:Name="listRestorePoints" Height="140" Background="#FF0D0D14" Foreground="#FFE8E8F0"
                         BorderBrush="#FF3A3A52" FontFamily="Consolas" FontSize="12"/>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                  <Button x:Name="btnRestorePointGo" Style="{StaticResource DangerButton}" Content="Restore PC to Selected Point" Margin="0,0,8,0"/>
                  <Button x:Name="btnRestorePointRefresh" Style="{StaticResource DarkButton}" Content="Refresh List"/>
                </StackPanel>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= STARTUP ================= -->
      <TabItem Header="Startup" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Startup Programs"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Programs that launch with Windows. Disabling one moves it to a quarantined registry key so it never starts again, and the Backups tab can restore it. Disabled entries show in amber."/>
                <ListBox x:Name="listStartup" Height="300" Background="#FF0D0D14" Foreground="#FFE8E8F0"
                         BorderBrush="#FF3A3A52" FontFamily="Consolas" FontSize="12"/>
                <WrapPanel Margin="0,10,0,0">
                  <Button x:Name="btnStartupDisable" Style="{StaticResource DangerButton}" Content="Disable Selected" Margin="0,0,8,8"/>
                  <Button x:Name="btnStartupEnable" Style="{StaticResource AccentButton}" Content="Enable Selected" Margin="0,0,8,8"/>
                  <Button x:Name="btnStartupRefresh" Style="{StaticResource DarkButton}" Content="Refresh" Margin="0,0,8,8"/>
                  <Button x:Name="btnStartupFolder" Style="{StaticResource DarkButton}" Content="Open Startup Folder" Margin="0,0,8,8"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= NETWORK ================= -->
      <TabItem Header="Network" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="DNS Servers"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Cloudflare is fastest for most people, Quad9 adds malware blocking. Every DNS change is recorded so the Backups tab can undo it."/>
                <StackPanel Orientation="Horizontal">
                  <ComboBox x:Name="cmbDnsProvider" Width="250" Padding="7" FontSize="13"
                            Background="#FF0D0D14" Foreground="#FFE8E8F0" BorderBrush="#FF3A3A52">
                    <ComboBoxItem Content="Cloudflare (1.1.1.1)" IsSelected="True"/>
                    <ComboBoxItem Content="Google (8.8.8.8)"/>
                    <ComboBoxItem Content="Quad9 (9.9.9.9)"/>
                    <ComboBoxItem Content="AdGuard (94.140.14.14)"/>
                    <ComboBoxItem Content="Automatic (DHCP)"/>
                  </ComboBox>
                  <Button x:Name="btnDnsApply" Style="{StaticResource AccentButton}" Content="Apply DNS" Margin="8,0,0,0"/>
                  <Button x:Name="btnDnsTest" Style="{StaticResource DarkButton}" Content="Test Latency" Margin="8,0,0,0"/>
                </StackPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Adapter and Latency"/>
                <CheckBox x:Name="chkWirelessPower" Style="{StaticResource DarkCheck}"
                          Content="Set wireless adapter power saving to Maximum Performance"/>
                <Button x:Name="btnWirelessPower" Style="{StaticResource DarkButton}" Content="Apply Wireless Power Setting"
                        HorizontalAlignment="Left" Margin="0,4,0,10"/>
                <TextBox x:Name="txtNetwork" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap"
                         FontFamily="Consolas" FontSize="12" Background="#FF0D0D14" Foreground="#FFB8D8F0"
                         BorderBrush="#FF3A3A52" Padding="10" MinHeight="190"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= BENCHMARK ================= -->
      <TabItem Header="Benchmark" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Performance Benchmark"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Runs CPU, memory and disk tests in about 10 seconds. The honest way to use it: run it, save a baseline, apply your tweaks, run it again and compare. Scores only compare on the same machine and PowerShell version."/>
                <WrapPanel>
                  <Button x:Name="btnBenchRun" Style="{StaticResource AccentButton}" Content="Run Benchmark" Margin="0,0,8,8"/>
                  <Button x:Name="btnBenchSave" Style="{StaticResource DarkButton}" Content="Save as Baseline" Margin="0,0,8,8"/>
                  <Button x:Name="btnBenchCompare" Style="{StaticResource DarkButton}" Content="Compare to Baseline" Margin="0,0,8,8"/>
                  <Button x:Name="btnBenchOpen" Style="{StaticResource DarkButton}" Content="Open Results Folder" Margin="0,0,8,8"/>
                </WrapPanel>
                <TextBox x:Name="txtBenchmark" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap"
                         FontFamily="Consolas" FontSize="12" Background="#FF0D0D14" Foreground="#FFB8D8F0"
                         BorderBrush="#FF3A3A52" Padding="10" MinHeight="240" Margin="0,8,0,0"
                         VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= RECOMMENDED ================= -->
      <TabItem Header="Recommended" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Taskbar (recommended layout)"/>
                <CheckBox x:Name="chkTaskbarLeft" Style="{StaticResource DarkCheck}"
                          Content="Align the taskbar to the left (classic position)"/>
                <CheckBox x:Name="chkTaskbarSearch" Style="{StaticResource DarkCheck}"
                          Content="Hide the taskbar search box"/>
                <CheckBox x:Name="chkTaskbarTaskView" Style="{StaticResource DarkCheck}"
                          Content="Hide the Task View button"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="These are pure preference settings, so nothing changes until you press Apply. Taskbar changes show up after Explorer restarts or you sign out."/>
                <Button x:Name="btnApplyRecommended" Style="{StaticResource AccentButton}"
                        Content="Apply Selected Taskbar Settings" HorizontalAlignment="Left" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Display Refresh Rate"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Many gaming monitors run at 60 Hz out of the box even when they support 144 Hz or more. Check Display settings, open Advanced display, and pick the highest refresh rate your monitor offers. This is one of the biggest free wins for smoothness and it takes ten seconds."/>
                <Button x:Name="btnOpenDisplay" Style="{StaticResource DarkButton}" Content="Open Display Settings" HorizontalAlignment="Left"/>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Windows Update Control"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Defer updates so a bad patch never lands mid ranked session, and stop Windows from swapping your GPU driver automatically. Security updates still arrive, just on your schedule."/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <TextBlock Text="Defer updates" VerticalAlignment="Center" Margin="0,0,8,0" Foreground="#FFE8E8F0"/>
                  <ComboBox x:Name="cmbWuDefer" Width="180" Padding="7" FontSize="13"
                            Background="#FF0D0D14" Foreground="#FFE8E8F0" BorderBrush="#FF3A3A52">
                    <ComboBoxItem Content="No defer" IsSelected="True"/>
                    <ComboBoxItem Content="Defer 7 days"/>
                    <ComboBoxItem Content="Defer 14 days"/>
                    <ComboBoxItem Content="Defer 30 days"/>
                  </ComboBox>
                </StackPanel>
                <CheckBox x:Name="chkWuNoDrivers" Style="{StaticResource DarkCheck}"
                          Content="Block driver updates through Windows Update"/>
                <CheckBox x:Name="chkWuNoReboot" Style="{StaticResource DarkCheck}"
                          Content="Never auto-restart while I am signed in"/>
                <Button x:Name="btnApplyWu" Style="{StaticResource AccentButton}" Content="Apply Update Settings"
                        HorizontalAlignment="Left" Margin="0,4,0,0"/>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= APPS ================= -->
      <TabItem Header="Apps" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Fresh Install Kit"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Tick the apps you want and install them all in one batch with winget, the Windows package manager. Needs internet. Nothing is bundled with this tool itself, installs come straight from the publishers."/>
                <WrapPanel x:Name="panelApps" Margin="0,0,0,6">
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Google Chrome" Tag="Google.Chrome" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Mozilla Firefox" Tag="Mozilla.Firefox" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Brave Browser" Tag="Brave.Brave" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Steam" Tag="Valve.Steam" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Epic Games Launcher" Tag="EpicGames.EpicGamesLauncher" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="GOG Galaxy" Tag="GOG.Galaxy" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Discord" Tag="Discord.Discord" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="7-Zip" Tag="7zip.7zip" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Notepad++" Tag="Notepad++.Notepad++" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="Everything Search" Tag="voidtools.Everything" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="PowerToys" Tag="Microsoft.PowerToys" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="VLC Player" Tag="VideoLAN.VLC" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="OBS Studio" Tag="OBSProject.OBSStudio" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="VC++ Redist x64" Tag="Microsoft.VCRedist.2015+.x64" Width="235"/>
                  <CheckBox Style="{StaticResource DarkCheck}" Content="VC++ Redist x86" Tag="Microsoft.VCRedist.2015+.x86" Width="235"/>
                </WrapPanel>
                <WrapPanel>
                  <Button x:Name="btnAppsAll" Style="{StaticResource DarkButton}" Content="Select All" Margin="0,0,8,8"/>
                  <Button x:Name="btnAppsNone" Style="{StaticResource DarkButton}" Content="Clear Selection" Margin="0,0,8,8"/>
                  <Button x:Name="btnAppsInstall" Style="{StaticResource AccentButton}" Content="Install Selected with winget" Margin="0,0,8,8"/>
                </WrapPanel>
              </StackPanel>
            </Border>
          </StackPanel>
        </ScrollViewer>
      </TabItem>

      <!-- ================= GAMES ================= -->
      <TabItem Header="Games" Style="{StaticResource DarkTab}">
        <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Padding="4">
          <StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Detected Games"/>
                <TextBlock Style="{StaticResource DimText}"
                           Text="Games found in your Steam libraries plus anything you add manually. Per-game flags are per Windows user and are recorded so the Backups tab can undo them."/>
                <ListBox x:Name="listGames" Height="220" Background="#FF0D0D14" Foreground="#FFE8E8F0"
                         BorderBrush="#FF3A3A52" FontFamily="Consolas" FontSize="12"/>
                <WrapPanel Margin="0,10,0,0">
                  <Button x:Name="btnGamesRefresh" Style="{StaticResource DarkButton}" Content="Refresh List" Margin="0,0,8,8"/>
                  <Button x:Name="btnGameAdd" Style="{StaticResource DarkButton}" Content="Add Custom EXE" Margin="0,0,8,8"/>
                  <Button x:Name="btnGameRemove" Style="{StaticResource DarkButton}" Content="Remove Selected from List" Margin="0,0,8,8"/>
                </WrapPanel>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Style="{StaticResource CardHeader}" Text="Tweaks for the Selected Game"/>
                <CheckBox x:Name="chkGameGpu" Style="{StaticResource DarkCheck}"
                          Content="Force high performance GPU for this game"/>
                <CheckBox x:Name="chkGameFse" Style="{StaticResource DarkCheck}"
                          Content="Disable fullscreen optimizations for this game"/>
                <Button x:Name="btnApplyGame" Style="{StaticResource AccentButton}" Content="Apply to Selected Game"
                        HorizontalAlignment="Left" Margin="0,4,0,0"/>
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
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <Button x:Name="btnCheckUpdate" Style="{StaticResource DarkButton}" Content="Check for Updates" Margin="0,0,8,0"/>
                  <Button x:Name="btnDoUpdate" Style="{StaticResource AccentButton}" Content="Download and Restart"
                          ToolTip="Downloads the newest version from GitHub and restarts the tool. Also works as a repair if something ever breaks."/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <Button x:Name="btnExportBundle" Style="{StaticResource DarkButton}" Content="Export Support Bundle" Margin="0,0,8,0"/>
                  <Button x:Name="btnMakeShortcut" Style="{StaticResource DarkButton}" Content="Create Desktop Shortcut"/>
                </StackPanel>
                <TextBlock x:Name="txtUpdateStatus" Style="{StaticResource DimText}" Text="Update status: not checked yet"/>
                <TextBlock x:Name="txtAbout" TextWrapping="Wrap" Foreground="#FFD0D0E0" FontSize="13" LineHeight="23" Margin="0,8,0,0"/>
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

    # Dry run preview: show exactly what would be removed before touching anything
    $previewNames = @()
    foreach ($groupName in $groups.Keys) {
        foreach ($packageName in $groups[$groupName]) {
            $foundPkgs = @(Get-AppxPackage -AllUsers -Name ($packageName + '*') -ErrorAction SilentlyContinue)
            foreach ($pkg in $foundPkgs) { $previewNames += $pkg.PackageFullName }
        }
    }
    $uniqueNames = @($previewNames | Select-Object -Unique)

    if ($uniqueNames.Count -eq 0) {
        Write-Log 'None of the selected apps are installed, nothing to remove'
        return
    }

    $previewText = 'About to remove these {0} app packages:' -f $uniqueNames.Count
    foreach ($line in ($uniqueNames | Select-Object -First 20)) {
        $previewText += ('{0}  {1}' -f "`n", $line)
    }
    if ($uniqueNames.Count -gt 20) {
        $previewText += ('{0}  ... and {1} more' -f "`n", ($uniqueNames.Count - 20))
    }
    $previewText += ('{0}{0}Nothing has been removed yet. Continue?' -f "`n")

    if (-not (Confirm-Action 'Remove bloatware' $previewText)) {
        Write-Log 'Bloatware removal cancelled, nothing was changed' 'WARN'
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
    if ($chkClassicMenu.IsChecked)    { Enable-ClassicContextMenu }
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
        'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall', 'chkClassicMenu'
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
                'Dns' {
                    if (@($rec.OldServers).Count -eq 0) {
                        Set-DnsClientServerAddress -InterfaceIndex ([int]$rec.InterfaceIndex) -ResetServerAddresses -ErrorAction Stop
                        Write-Log ('Reverted: DNS on {0} back to automatic' -f $rec.Name) 'OK'
                    } else {
                        Set-DnsClientServerAddress -InterfaceIndex ([int]$rec.InterfaceIndex) -ServerAddresses ([string[]]@($rec.OldServers)) -ErrorAction Stop
                        Write-Log ('Reverted: DNS on {0} restored to {1}' -f $rec.Name, (@($rec.OldServers) -join ', ')) 'OK'
                    }
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
        'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall', 'chkOneDrive', 'chkClassicMenu',
        'chkTaskbarLeft', 'chkTaskbarSearch', 'chkTaskbarTaskView'
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
            $txtUpdateStatus.Text = ('Update status: v{0} is available (you run v{1}). Press Download and Restart to update.' -f $script:LatestVersion, $running)
            Write-Log ('Update available: v{0}' -f $script:LatestVersion) 'WARN'
        } else {
            $txtUpdateStatus.Text = ('Update status: you are on the latest version (v{0}). The button below reinstalls it if you ever need a repair.' -f $running)
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
        # Integrity sanity check: refuse to run anything that does not look like this tool
        $rawText = [string]$raw
        if ($rawText -notmatch 'BALDYBEAST OPTIMIZER' -or
            $rawText -notmatch 'Get-BaldyBanner' -or
            $rawText -notmatch "AppVersion\s*=\s*'") {
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
# Startup manager: Run registry entries, with quarantine instead of deletion
# ----------------------------------------------------------------------------
$script:DisabledRunSuffix = '-DisabledByBaldyBeast'

function Get-StartupEntries {
    $runPaths = @(
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Hive = 'HKCU'; Disabled = $false },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Hive = 'HKLM'; Disabled = $false },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Hive = 'HKLM 32-bit'; Disabled = $false },
        @{ Path = ('HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' + $script:DisabledRunSuffix); Hive = 'HKCU'; Disabled = $true },
        @{ Path = ('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' + $script:DisabledRunSuffix); Hive = 'HKLM'; Disabled = $true }
    )

    $entries = @()
    foreach ($source in $runPaths) {
        if (-not (Test-Path -LiteralPath $source.Path)) { continue }
        $key = Get-Item -LiteralPath $source.Path -ErrorAction SilentlyContinue
        if ($null -eq $key) { continue }
        foreach ($valueName in $key.GetValueNames()) {
            $entries += [pscustomobject]@{
                Name     = $valueName
                Command  = [string]$key.GetValue($valueName, '')
                RunPath  = $source.Path
                Hive     = $source.Hive
                Disabled = $source.Disabled
            }
        }
    }
    return $entries
}

function Update-StartupList {
    if ($null -eq $listStartup) { return }
    $listStartup.Items.Clear()

    foreach ($entry in (Get-StartupEntries)) {
        $state = 'ON '
        if ($entry.Disabled) { $state = 'OFF' }
        $command = $entry.Command
        if ($command.Length -gt 70) { $command = $command.Substring(0, 70) + '...' }

        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = ('[{0}] {1,-24} {2}' -f $state, $entry.Name, $command)
        $item.Tag = $entry
        if ($entry.Disabled) { $item.Foreground = New-Object System.Windows.Media.SolidColorBrush([System.Windows.Media.ColorConverter]::ConvertFromString('#FFF5A97F')) }
        [void]$listStartup.Items.Add($item)
    }
    Write-Log ('Startup list refreshed: {0} entries' -f $listStartup.Items.Count)
}

function Disable-StartupEntry {
    param([Parameter(Mandatory = $true)]$Entry)

    $disabledPath = $Entry.RunPath + $script:DisabledRunSuffix
    try {
        Backup-RegValue -Path $Entry.RunPath -Name $Entry.Name
        Backup-RegValue -Path $disabledPath -Name $Entry.Name

        Set-RegValue -Path $disabledPath -Name $Entry.Name -Value $Entry.Command -Type 'String' | Out-Null
        Remove-ItemProperty -LiteralPath $Entry.RunPath -Name $Entry.Name -Force -ErrorAction Stop
        Write-Log ('Startup entry disabled: {0}' -f $Entry.Name) 'OK'
    } catch {
        Write-Log ('Could not disable {0}: {1}' -f $Entry.Name, $_.Exception.Message) 'ERROR'
    }
}

function Enable-StartupEntry {
    param([Parameter(Mandatory = $true)]$Entry)

    $livePath = $Entry.RunPath -replace [regex]::Escape($script:DisabledRunSuffix), ''
    try {
        Backup-RegValue -Path $Entry.RunPath -Name $Entry.Name
        Backup-RegValue -Path $livePath -Name $Entry.Name

        Set-RegValue -Path $livePath -Name $Entry.Name -Value $Entry.Command -Type 'String' | Out-Null
        Remove-ItemProperty -LiteralPath $Entry.RunPath -Name $Entry.Name -Force -ErrorAction Stop
        Write-Log ('Startup entry enabled: {0}' -f $Entry.Name) 'OK'
    } catch {
        Write-Log ('Could not enable {0}: {1}' -f $Entry.Name, $_.Exception.Message) 'ERROR'
    }
}

# ----------------------------------------------------------------------------
# Network: DNS switching, latency test, wireless power saving
# ----------------------------------------------------------------------------
function Get-NetworkSummary {
    $lines = @()
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        if ($adapters.Count -eq 0) {
            $lines += 'No active network adapter found.'
            return $lines
        }

        foreach ($adapter in $adapters) {
            $ipv4 = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $dnsList = 'automatic (DHCP)'
            if ($null -ne $ipv4 -and @($ipv4.ServerAddresses).Count -gt 0) {
                $dnsList = (@($ipv4.ServerAddresses) -join ', ')
            }
            $lines += ('Adapter  {0,-16} DNS: {1}' -f $adapter.Name, $dnsList)
        }

        $gateway = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_.IPv4DefaultGateway } |
            Select-Object -First 1
        if ($null -ne $gateway) {
            $lines += ('Gateway  {0}' -f $gateway.IPv4DefaultGateway.NextHop)
        }
    } catch {
        $lines += ('Network read failed: {0}' -f $_.Exception.Message)
    }
    return $lines
}

function Set-DnsProvider {
    param([Parameter(Mandatory = $true)][string]$ProviderName)

    $serverSets = @{
        'Cloudflare' = @('1.1.1.1', '1.0.0.1')
        'Google'     = @('8.8.8.8', '8.8.4.4')
        'Quad9'      = @('9.9.9.9', '149.112.112.112')
        'AdGuard'    = @('94.140.14.14', '94.140.15.15')
    }

    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
        foreach ($adapter in $adapters) {
            $current = Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $oldServers = @()
            if ($null -ne $current) { $oldServers = @($current.ServerAddresses) }

            Add-BackupRecord -Record @{
                Kind           = 'Dns'
                Name           = $adapter.Name
                InterfaceIndex = [int]$adapter.ifIndex
                OldServers     = $oldServers
            }

            if ($ProviderName -eq 'Automatic') {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
                Write-Log ('DNS on {0} reset to automatic' -f $adapter.Name) 'OK'
            } else {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $serverSets[$ProviderName] -ErrorAction Stop
                Write-Log ('DNS on {0} set to {1}: {2}' -f $adapter.Name, $ProviderName, ($serverSets[$ProviderName] -join ', ')) 'OK'
            }
        }
        Clear-DnsCache
    } catch {
        Write-Log ('DNS change failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Test-NetworkLatency {
    $targets = [ordered]@{
        'Cloudflare 1.1.1.1' = '1.1.1.1'
        'Google 8.8.8.8'     = '8.8.8.8'
        'Quad9 9.9.9.9'      = '9.9.9.9'
        'Microsoft 4.2.2.1'  = '4.2.2.1'
    }

    try {
        $gateway = Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_.IPv4DefaultGateway } |
            Select-Object -First 1
        if ($null -ne $gateway) {
            $targets['Default gateway'] = $gateway.IPv4DefaultGateway.NextHop
        }
    } catch { }

    $lines = @()
    $lines += ('Latency test at {0} (3 pings each)' -f (Get-Date -Format 'HH:mm:ss'))
    $lines += ''

    foreach ($label in $targets.Keys) {
        $address = $targets[$label]
        try {
            $replies = @(Test-Connection -ComputerName $address -Count 3 -ErrorAction SilentlyContinue)
            if ($replies.Count -gt 0) {
                $avg = [math]::Round(($replies | Measure-Object -Property ResponseTime -Average).Average, 1)
                $lines += ('{0,-22} {1,6} ms avg   ({2}/{3} replies)' -f $label, $avg, $replies.Count, 3)
            } else {
                $lines += ('{0,-22} timeout or blocked' -f $label)
            }
        } catch {
            $lines += ('{0,-22} failed: {1}' -f $label, $_.Exception.Message)
        }
    }

    $lines += ''
    $lines += 'Lower is better. Under 20 ms is great for gaming DNS.'
    $txtNetwork.Text = ($lines -join [System.Environment]::NewLine)
    Write-Log 'Latency test finished' 'OK'
}

function Set-WirelessMaxPerformance {
    Write-Log 'Setting wireless adapter power saving to Maximum Performance...'
    # Wireless Adapter Settings subgroup and Power Saving Mode setting
    & powercfg.exe /setacvalueindex scheme_current 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>$null | Out-Null
    & powercfg.exe /setdcvalueindex scheme_current 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 2>$null | Out-Null
    & powercfg.exe /setactive scheme_current 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Wireless power saving set to Maximum Performance on AC and battery' 'OK'
    } else {
        Write-Log 'Could not change the wireless power setting on this system' 'WARN'
    }
}

# ----------------------------------------------------------------------------
# Benchmark: CPU single, CPU multi, memory copy, disk write/read
# Scores are only comparable on the same machine and the same PowerShell
# version. Run before and after your tweaks to see real deltas.
# ----------------------------------------------------------------------------
$script:BenchmarkDir      = Join-Path $env:LOCALAPPDATA 'BaldyBeast\benchmarks'
$script:LastBenchFile     = Join-Path $script:BenchmarkDir 'last.json'
$script:BaselineBenchFile = Join-Path $script:BenchmarkDir 'baseline.json'

function Invoke-CpuSingleWork {
    param([int]$Rounds)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $acc = 0
    for ($i = 1; $i -le $Rounds; $i++) {
        $acc = ($acc + $i * 7) % 1000000007
    }
    $sw.Stop()
    return $sw.Elapsed.TotalMilliseconds
}

function Invoke-CpuMultiWork {
    param(
        [int]$Rounds,
        [int]$Threads
    )

    $work = {
        param([int]$n)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $acc = 0
        for ($i = 1; $i -le $n; $i++) {
            $acc = ($acc + $i * 7) % 1000000007
        }
        $sw.Stop()
        return $sw.Elapsed.TotalMilliseconds
    }

    $pool = [runspacefactory]::CreateRunspacePool(1, $Threads)
    $pool.Open()
    $pipes = @()
    for ($t = 0; $t -lt $Threads; $t++) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($work).AddArgument($Rounds)
        $pipes += [pscustomobject]@{ Pipe = $ps; Handle = $ps.BeginInvoke() }
    }

    $slowestMs = 0.0
    foreach ($entry in $pipes) {
        $result = $entry.Pipe.EndInvoke($entry.Handle)
        $ms = [double]$result[0]
        if ($ms -gt $slowestMs) { $slowestMs = $ms }
        $entry.Pipe.Dispose()
    }
    $pool.Close()
    return $slowestMs
}

function Invoke-MemoryWork {
    param([int]$SizeMB = 256)

    $size = [int]($SizeMB * 1MB)
    $source = New-Object byte[] $size
    $target = New-Object byte[] $size
    $rng = New-Object System.Random
    $rng.NextBytes($source)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    [System.Buffer]::BlockCopy($source, 0, $target, 0, $size)
    $sw.Stop()

    $seconds = [math]::Max($sw.Elapsed.TotalSeconds, 0.0001)
    return [math]::Round(($SizeMB / $seconds), 0)
}

function Invoke-DiskWork {
    param(
        [string]$Path,
        [int]$SizeMB = 256
    )

    $file = Join-Path $Path ('bb-bench-{0}.tmp' -f ([guid]::NewGuid().ToString('N').Substring(0, 6)))
    $chunk = New-Object byte[] (1MB)
    $rng = New-Object System.Random
    $rng.NextBytes($chunk)

    $writeMs = 0.0
    $readMs = 0.0
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $stream = New-Object System.IO.FileStream($file, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        try {
            for ($i = 0; $i -lt $SizeMB; $i++) {
                $stream.Write($chunk, 0, $chunk.Length)
            }
            $stream.Flush($true)
        } finally {
            $stream.Close()
        }
        $sw.Stop()
        $writeMs = $sw.Elapsed.TotalMilliseconds

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $stream = New-Object System.IO.FileStream($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        try {
            $readBuffer = New-Object byte[] (1MB)
            $read = 1
            while ($read -gt 0) {
                $read = $stream.Read($readBuffer, 0, $readBuffer.Length)
            }
        } finally {
            $stream.Close()
        }
        $sw.Stop()
        $readMs = $sw.Elapsed.TotalMilliseconds
    } finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        WriteMBps = [math]::Round(($SizeMB / ([math]::Max($writeMs, 0.0001) / 1000)), 0)
        ReadMBps  = [math]::Round(($SizeMB / ([math]::Max($readMs, 0.0001) / 1000)), 0)
    }
}

function Start-Benchmark {
    Write-Log 'Benchmark started, this takes about 10 seconds...'
    $txtBenchmark.Text = 'Running benchmark, please wait...'
    Update-Ui

    $threads = [Environment]::ProcessorCount
    $cpuRounds = 2000000

    $results = [ordered]@{
        Timestamp    = (Get-Date).ToString('s')
        PsVersion    = $PSVersionTable.PSVersion.ToString()
        CpuName      = ''
        Threads      = $threads
        CpuSingleMs  = 0.0
        CpuSingleIters = 0.0
        CpuMultiIters  = 0.0
        MemMBps      = 0.0
        DiskWriteMBps = 0.0
        DiskReadMBps  = 0.0
    }

    try {
        $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $results.CpuName = $cpu.Name
    } catch {
        $results.CpuName = 'unknown'
    }

    try {
        $txtBenchmark.Text = 'Running CPU single thread test...'
        Update-Ui
        $singleMs = Invoke-CpuSingleWork -Rounds $cpuRounds
        $results.CpuSingleMs = [math]::Round($singleMs, 1)
        $results.CpuSingleIters = [math]::Round(($cpuRounds / ([math]::Max($singleMs, 0.0001) / 1000)), 0)
    } catch {
        Write-Log ('CPU single test failed: {0}' -f $_.Exception.Message) 'ERROR'
    }

    try {
        $txtBenchmark.Text = ('Running CPU multi thread test ({0} threads)...' -f $threads)
        Update-Ui
        $multiMs = Invoke-CpuMultiWork -Rounds $cpuRounds -Threads $threads
        $results.CpuMultiIters = [math]::Round((($cpuRounds * $threads) / ([math]::Max($multiMs, 0.0001) / 1000)), 0)
    } catch {
        Write-Log ('CPU multi test failed: {0}' -f $_.Exception.Message) 'ERROR'
    }

    try {
        $txtBenchmark.Text = 'Running memory copy test...'
        Update-Ui
        $results.MemMBps = Invoke-MemoryWork -SizeMB 256
    } catch {
        Write-Log ('Memory test failed: {0}' -f $_.Exception.Message) 'ERROR'
    }

    try {
        $txtBenchmark.Text = 'Running disk write and read test...'
        Update-Ui
        $disk = Invoke-DiskWork -Path $env:TEMP -SizeMB 256
        $results.DiskWriteMBps = $disk.WriteMBps
        $results.DiskReadMBps = $disk.ReadMBps
    } catch {
        Write-Log ('Disk test failed: {0}' -f $_.Exception.Message) 'ERROR'
    }

    try {
        if (-not (Test-Path -LiteralPath $script:BenchmarkDir)) {
            New-Item -Path $script:BenchmarkDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        ConvertTo-Json -InputObject ([pscustomobject]$results) -Depth 4 | Set-Content -LiteralPath $script:LastBenchFile -Encoding UTF8
    } catch {
        Write-Log ('Could not save benchmark results: {0}' -f $_.Exception.Message) 'WARN'
    }

    $txtBenchmark.Text = (Format-BenchmarkReport -Results ([pscustomobject]$results))
    Write-Log ('Benchmark done. CPU single {0} iter/s, memory {1} MB/s' -f $results.CpuSingleIters, $results.MemMBps) 'OK'
}

function Format-BenchmarkReport {
    param([Parameter(Mandatory = $true)]$Results)

    $lines = @()
    $lines += ('BALDYBEAST BENCHMARK  {0}' -f $Results.Timestamp)
    $lines += ('CPU: {0}  ({1} threads, PowerShell {2})' -f $Results.CpuName, $Results.Threads, $Results.PsVersion)
    $lines += '---------------------------------------------------------'
    $lines += ('CPU single thread : {0} iter/s   ({1} ms for {2} rounds)' -f $Results.CpuSingleIters, $Results.CpuSingleMs, 2000000)
    $lines += ('CPU multi thread  : {0} iter/s   ({1} threads)' -f $Results.CpuMultiIters, $Results.Threads)
    $lines += ('Memory copy       : {0} MB/s' -f $Results.MemMBps)
    $lines += ('Disk write (temp) : {0} MB/s' -f $Results.DiskWriteMBps)
    $lines += ('Disk read  (temp) : {0} MB/s' -f $Results.DiskReadMBps)
    $lines += ''
    $lines += 'Scores compare on the same machine and PowerShell version only.'
    $lines += 'Run before and after your tweaks, then press Compare to Baseline.'
    return ($lines -join [System.Environment]::NewLine)
}

function Save-BenchmarkBaseline {
    if (-not (Test-Path -LiteralPath $script:LastBenchFile)) {
        Write-Log 'No benchmark results yet. Run the benchmark first.' 'WARN'
        return
    }
    try {
        Copy-Item -LiteralPath $script:LastBenchFile -Destination $script:BaselineBenchFile -Force
        Write-Log 'Baseline saved. Run the benchmark again after your tweaks to compare.' 'OK'
    } catch {
        Write-Log ('Could not save baseline: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Compare-BenchmarkToBaseline {
    if (-not (Test-Path -LiteralPath $script:BaselineBenchFile)) {
        Write-Log 'No baseline saved yet. Run a benchmark and press Save as Baseline.' 'WARN'
        return
    }
    if (-not (Test-Path -LiteralPath $script:LastBenchFile)) {
        Write-Log 'No current results yet. Run the benchmark first.' 'WARN'
        return
    }

    try {
        $base = Get-Content -LiteralPath $script:BaselineBenchFile -Raw | ConvertFrom-Json
        $last = Get-Content -LiteralPath $script:LastBenchFile -Raw | ConvertFrom-Json

        $metrics = @(
            @{ Label = 'CPU single thread'; Base = $base.CpuSingleIters; Last = $last.CpuSingleIters },
            @{ Label = 'CPU multi thread';  Base = $base.CpuMultiIters;  Last = $last.CpuMultiIters },
            @{ Label = 'Memory copy';       Base = $base.MemMBps;        Last = $last.MemMBps },
            @{ Label = 'Disk write';        Base = $base.DiskWriteMBps;  Last = $last.DiskWriteMBps },
            @{ Label = 'Disk read';         Base = $base.DiskReadMBps;   Last = $last.DiskReadMBps }
        )

        $lines = @()
        $lines += ('COMPARISON  baseline {0}  vs  current {1}' -f $base.Timestamp, $last.Timestamp)
        $lines += '---------------------------------------------------------'
        foreach ($metric in $metrics) {
            $delta = 0.0
            if ([double]$metric.Base -gt 0) {
                $delta = (([double]$metric.Last - [double]$metric.Base) / [double]$metric.Base) * 100
            }
            $sign = '+'
            if ($delta -lt 0) { $sign = '' }
            $lines += ('{0,-17} : {1}  ->  {2}   ({3}{4:N1}%)' -f $metric.Label, $metric.Base, $metric.Last, $sign, $delta)
        }
        $lines += ''
        $lines += 'Positive is better. Small single digit swings are normal noise.'

        $txtBenchmark.Text = (($txtBenchmark.Text) + [System.Environment]::NewLine + [System.Environment]::NewLine + ($lines -join [System.Environment]::NewLine))
        Write-Log 'Benchmark comparison added to the results box' 'OK'
    } catch {
        Write-Log ('Comparison failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

# ----------------------------------------------------------------------------
# Support bundle, desktop shortcut, classic context menu
# ----------------------------------------------------------------------------
function Export-SupportBundle {
    Write-Log 'Building support bundle...'
    try {
        $staging = Join-Path $env:TEMP ('BaldyBeast-support-{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 6)))
        New-Item -Path $staging -ItemType Directory -Force -ErrorAction Stop | Out-Null

        $report = @()
        $report += ('BALDYBEAST OPTIMIZER support bundle')
        $report += ('Created  : {0}' -f (Get-Date).ToString('s'))
        $report += ('Version  : {0}' -f $script:AppVersion)
        $report += ('PowerShell: {0}' -f $PSVersionTable.PSVersion)
        $report += ''
        $report += 'HARDWARE'
        $report += ($txtHardware.Text -split "`r?`n")
        $report += ''
        $report += 'TWEAK SELECTION'
        foreach ($controlName in (Get-AllTweakNames)) {
            $control = $script:Window.FindName($controlName)
            $state = '[ ]'
            if ($null -ne $control -and $control.IsChecked -eq $true) { $state = '[x]' }
            $report += ('{0} {1}' -f $state, $controlName)
        }
        $report += ''
        $report += 'LAST BENCHMARK'
        if (Test-Path -LiteralPath $script:LastBenchFile) {
            $report += (Get-Content -LiteralPath $script:LastBenchFile -Raw)
        } else {
            $report += '(none run)'
        }
        $report += ''
        $report += 'LOG'
        if (Test-Path -LiteralPath $script:LogFile) {
            $report += (Get-Content -LiteralPath $script:LogFile -Tail 300)
        }

        Set-Content -LiteralPath (Join-Path $staging 'report.txt') -Value ($report -join [System.Environment]::NewLine) -Encoding UTF8
        if (Test-Path -LiteralPath $script:LogFile) {
            Copy-Item -LiteralPath $script:LogFile -Destination (Join-Path $staging 'BaldyBeast-Optimizer.log') -ErrorAction SilentlyContinue
        }

        $zipPath = Join-Path ([Environment]::GetFolderPath('Desktop')) ('BaldyBeast-support-{0}.zip' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zipPath -Force
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue

        Write-Log ('Support bundle saved to your Desktop: {0}' -f [System.IO.Path]::GetFileName($zipPath)) 'OK'
    } catch {
        Write-Log ('Support bundle failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function New-DesktopShortcut {
    Write-Log 'Creating Desktop shortcut...'
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnkPath = Join-Path $desktop 'BALDYBEAST OPTIMIZER.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($lnkPath)

        if (-not [string]::IsNullOrWhiteSpace($PSCommandPath) -and (Test-Path -LiteralPath $PSCommandPath)) {
            $shortcut.TargetPath = 'powershell.exe'
            $shortcut.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath)
        } else {
            $shortcut.TargetPath = 'powershell.exe'
            $shortcut.Arguments = ('-NoProfile -WindowStyle Hidden -Command "irm ''{0}'' | iex"' -f $script:RepoRawUrl)
        }

        $shortcut.WorkingDirectory = $desktop
        $shortcut.Description = 'BALDYBEAST OPTIMIZER - Windows gaming optimization utility'
        $shortcut.Save()
        Write-Log 'Desktop shortcut created: BALDYBEAST OPTIMIZER.lnk' 'OK'
    } catch {
        Write-Log ('Shortcut creation failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Enable-ClassicContextMenu {
    Write-Log 'Enabling the classic Windows 11 right-click menu...'
    Set-RegValue -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Name '(default)' -Value '' -Type 'String' | Out-Null
    Write-Log 'Restart Explorer or sign out to see the classic menu. The Backups tab undoes this.' 'INFO'
}

# ----------------------------------------------------------------------------
# Memory: RAMMap style breakdown and standby list purge
# The purge uses NtSetSystemInformation(SystemMemoryListInformation) with the
# SeProfileSingleProcessPrivilege, the same mechanism RAMMap and ISLC use.
# No external tools involved.
# ----------------------------------------------------------------------------
if (-not ('BaldyBeast.Memory' -as [type])) {
    Add-Type -Namespace BaldyBeast -Name Memory -MemberDefinition @'
[System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
public struct TOKEN_PRIVILEGES
{
    public uint PrivilegeCount;
    public uint LuidLow;
    public int LuidHigh;
    public uint Attributes;
}

[DllImport("ntdll.dll")]
public static extern int NtSetSystemInformation(int infoClass, System.IntPtr info, int length);

[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool OpenProcessToken(System.IntPtr processHandle, int access, out System.IntPtr tokenHandle);

[DllImport("kernel32.dll")]
public static extern System.IntPtr GetCurrentProcess();

[DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern bool LookupPrivilegeValue(string systemName, string name, out long luid);

[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool AdjustTokenPrivileges(System.IntPtr tokenHandle, bool disableAll, ref TOKEN_PRIVILEGES newState, int bufferLength, System.IntPtr previousState, System.IntPtr returnLength);

public static string PurgeStandbyList()
{
    System.IntPtr token;
    if (!OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out token))
    {
        return "OpenProcessToken failed: " + System.Runtime.InteropServices.Marshal.GetLastWin32Error();
    }

    long luidValue;
    if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luidValue))
    {
        return "LookupPrivilegeValue failed: " + System.Runtime.InteropServices.Marshal.GetLastWin32Error();
    }

    TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
    tp.PrivilegeCount = 1;
    tp.LuidLow = (uint)(luidValue & 0xFFFFFFFF);
    tp.LuidHigh = (int)(luidValue >> 32);
    tp.Attributes = 0x00000002;

    if (!AdjustTokenPrivileges(token, false, ref tp, 0, System.IntPtr.Zero, System.IntPtr.Zero))
    {
        return "AdjustTokenPrivileges failed: " + System.Runtime.InteropServices.Marshal.GetLastWin32Error();
    }
    if (System.Runtime.InteropServices.Marshal.GetLastWin32Error() == 1300)
    {
        return "privilege SeProfileSingleProcessPrivilege was not assigned to this token";
    }

    System.IntPtr buffer = System.Runtime.InteropServices.Marshal.AllocHGlobal(4);
    try
    {
        // MemoryPurgeStandbyList is 4 in the WDK / ISLC enum and 12 in some
        // reconstructed API enums. Try both, first success wins.
        int[] commands = new int[2] { 4, 12 };
        int status = -1;
        for (int i = 0; i < commands.Length; i++)
        {
            System.Runtime.InteropServices.Marshal.WriteInt32(buffer, 0, commands[i]);
            status = NtSetSystemInformation(80, buffer, 4);
            if (status == 0)
            {
                return "ok";
            }
        }
        return ("NtSetSystemInformation status 0x" + status.ToString("X8"));
    }
    finally
    {
        System.Runtime.InteropServices.Marshal.FreeHGlobal(buffer);
    }
}
'@
}

function Update-MemoryInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $lines = @()
        $lines += ('Physical memory   : {0:N1} GB total / {1:N1} GB free' -f ($os.TotalVisibleMemorySize * 1KB / 1GB), ($os.FreePhysicalMemory * 1KB / 1GB))

        $counterPaths = @(
            '\Memory\Standby Cache Normal Priority Bytes',
            '\Memory\Standby Cache Reserve Bytes',
            '\Memory\Standby Cache Core Bytes',
            '\Memory\Modified Page List Bytes',
            '\Memory\Cache Bytes',
            '\Memory\Free & Zero Page List Bytes'
        )
        try {
            $samples = Get-Counter -Counter $counterPaths -ErrorAction Stop
            foreach ($sample in $samples.CounterSamples) {
                $label = $sample.Path -replace '^.*\\Memory\\', '' -replace ' Bytes$', ''
                $lines += ('{0,-20}: {1,8:N0} MB' -f $label, ($sample.CookedValue / 1MB))
            }
        } catch {
            $lines += '(memory counters unavailable on this system)'
        }

        $lines += ''
        $lines += 'Top processes by working set:'
        $top = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8
        foreach ($proc in $top) {
            $lines += ('  {0,-22} {1,7:N0} MB' -f $proc.ProcessName, ($proc.WorkingSet64 / 1MB))
        }

        $txtMemory.Text = ($lines -join [System.Environment]::NewLine)
    } catch {
        Write-Log ('Memory info failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Clear-StandbyList {
    Write-Log 'Purging standby list (emptying cached file pages)...'
    try {
        $outcome = [BaldyBeast.Memory]::PurgeStandbyList()
        if ($outcome -eq 'ok') {
            Write-Log 'Standby list purged. Cached file pages were released.' 'OK'
        } else {
            Write-Log ('Standby purge: {0}' -f $outcome) 'ERROR'
        }
    } catch {
        Write-Log ('Standby purge failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
    Update-MemoryInfo
}

# ----------------------------------------------------------------------------
# Recommended settings: taskbar layout (pure preference, never auto applied)
# ----------------------------------------------------------------------------
function Invoke-RecommendedTweaks {
    Write-Log '===== Recommended Settings: applying selected tweaks ====='
    $applied = $false

    if ($chkTaskbarLeft.IsChecked) {
        Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarAl' -Value 0 | Out-Null
        $applied = $true
    }
    if ($chkTaskbarSearch.IsChecked) {
        Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0 | Out-Null
        $applied = $true
    }
    if ($chkTaskbarTaskView.IsChecked) {
        Set-RegValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowTaskViewButton' -Value 0 | Out-Null
        $applied = $true
    }

    if ($applied) {
        Write-Log 'Taskbar settings applied. Restart Explorer or sign out to see them.' 'INFO'
    } else {
        Write-Log 'No taskbar settings were ticked, nothing changed'
    }
    Write-Log '===== Recommended Settings: done =====' 'OK'
}

# ----------------------------------------------------------------------------
# Windows System Restore points, build awareness, Recall snapshot wipe
# ----------------------------------------------------------------------------
function Update-RestorePointList {
    if ($null -eq $listRestorePoints) { return }
    $listRestorePoints.Items.Clear()
    try {
        $points = @(Get-ComputerRestorePoint -ErrorAction Stop)
        foreach ($point in $points) {
            $created = $point.CreationTime
            if ($created -is [string]) {
                try {
                    $created = [System.Management.ManagementDateTimeConverter]::ToDateTime($created)
                } catch {
                    $created = $null
                }
            }
            $stamp = 'unknown time'
            if ($null -ne $created) { $stamp = $created.ToString('yyyy-MM-dd HH:mm') }

            $item = New-Object System.Windows.Controls.ListBoxItem
            $item.Content = ('{0}   seq {1}   {2}' -f $stamp, $point.SequenceNumber, $point.Description)
            $item.Tag = [int]$point.SequenceNumber
            [void]$listRestorePoints.Items.Add($item)
        }
        Write-Log ('Windows restore points found: {0}' -f $listRestorePoints.Items.Count)
    } catch {
        Write-Log ('Restore point list unavailable: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Restore-ComputerToPoint {
    param([Parameter(Mandatory = $true)][int]$SequenceNumber)

    Write-Log ('Starting System Restore to restore point seq {0}...' -f $SequenceNumber) 'WARN'
    try {
        Restore-Computer -RestorePoint $SequenceNumber -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Log ('System Restore failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

function Set-TweakAvailability {
    $build = 0
    try {
        $build = [int]((Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).BuildNumber)
    } catch {
        return
    }

    $isWin11 = ($build -ge 22000)
    $is24H2  = ($build -ge 26100)

    $rules = @(
        @{ Name = 'chkClassicMenu'; Require = $isWin11; Reason = 'this is a Windows 11 only setting' },
        @{ Name = 'chkCopilot';     Require = $isWin11; Reason = 'Copilot does not exist on Windows 10' },
        @{ Name = 'chkRecall';      Require = $is24H2;  Reason = 'Recall needs Windows 11 version 24H2 or newer' },
        @{ Name = 'chkTaskbarLeft'; Require = $isWin11; Reason = 'Windows 10 already has a left aligned taskbar' }
    )

    $disabled = 0
    foreach ($rule in $rules) {
        $control = $script:Window.FindName($rule.Name)
        if ($null -eq $control) { continue }
        if (-not $rule.Require) {
            $control.IsChecked = $false
            $control.IsEnabled = $false
            $control.ToolTip = ('Not applicable on this system: {0}' -f $rule.Reason)
            $disabled++
        }
    }

    if ($disabled -gt 0) {
        Write-Log ('{0} options greyed out because they do not apply to this Windows build ({1})' -f $disabled, $build) 'INFO'
    }
}

function Remove-RecallSnapshots {
    Write-Log 'Deleting Windows Recall snapshot data...'
    try {
        $aiDirs = @(Get-ChildItem -Path $env:LOCALAPPDATA -Directory -Filter 'CoreAIPlatform*' -ErrorAction SilentlyContinue)
        if ($aiDirs.Count -eq 0) {
            Write-Log 'No Recall snapshot storage found. Recall may never have run on this PC.' 'INFO'
            return
        }

        foreach ($dir in $aiDirs) {
            Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log ('Cleared Recall storage: {0}' -f $dir.Name) 'OK'
        }
    } catch {
        Write-Log ('Recall cleanup failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

# ----------------------------------------------------------------------------
# Fresh install kit (winget) and per-game tuning
# ----------------------------------------------------------------------------
function Install-SelectedApps {
    $selected = @()
    foreach ($box in $panelApps.Children) {
        if ($box -is [System.Windows.Controls.CheckBox] -and $box.IsChecked -eq $true) {
            $selected += [pscustomobject]@{ Name = [string]$box.Content; Id = [string]$box.Tag }
        }
    }

    if ($selected.Count -eq 0) {
        Write-Log 'No apps ticked, nothing to install' 'WARN'
        return
    }

    $winget = Get-Command -Name 'winget' -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        Write-Log 'winget is not available on this system. Install "App Installer" from the Microsoft Store first.' 'ERROR'
        return
    }

    $names = ($selected | ForEach-Object { $_.Name }) -join ', '
    if (-not (Confirm-Action 'Install apps' ('Install {0} app(s) with winget?{1}{2}{1}{1}This needs internet and each installer may show its own window.' -f $selected.Count, "`n", $names))) {
        Write-Log 'App install cancelled' 'WARN'
        return
    }

    foreach ($app in $selected) {
        Write-Log ('Installing {0} ({1})...' -f $app.Name, $app.Id)
        try {
            $output = & winget.exe install --id $app.Id --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                Write-Log ('Installed {0}' -f $app.Name) 'OK'
            } elseif ($output -match 'already installed') {
                Write-Log ('{0} is already installed' -f $app.Name) 'INFO'
            } else {
                Write-Log ('{0} failed (winget exit code {1})' -f $app.Name, $LASTEXITCODE) 'ERROR'
            }
        } catch {
            Write-Log ('{0} failed: {1}' -f $app.Name, $_.Exception.Message) 'ERROR'
        }
    }
    Write-Log 'Batch install finished' 'OK'
}

function Get-SteamLibraries {
    $roots = @()
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam', 'HKCU:\SOFTWARE\Valve\Steam')) {
        if (Test-Path -LiteralPath $key) {
            $installPath = (Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue).InstallPath
            if (-not [string]::IsNullOrWhiteSpace($installPath)) { $roots += $installPath }
        }
    }

    $libraries = @()
    foreach ($root in ($roots | Select-Object -Unique)) {
        $libraries += $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in (Get-Content -LiteralPath $vdf -ErrorAction SilentlyContinue)) {
                if ($line -match '"path"\s*"([^"]+)"') {
                    $libraries += ($Matches[1] -replace '\\\\', '\')
                }
            }
        }
    }
    return @($libraries | Select-Object -Unique)
}

function Update-GameList {
    if ($null -eq $listGames) { return }

    $customGames = @()
    foreach ($item in $listGames.Items) {
        if ($item.Tag.Source -eq 'custom') { $customGames += $item.Tag }
    }
    $listGames.Items.Clear()

    $detected = @()
    foreach ($library in (Get-SteamLibraries)) {
        $steamApps = Join-Path $library 'steamapps'
        if (-not (Test-Path -LiteralPath $steamApps)) { continue }
        $manifests = Get-ChildItem -LiteralPath $steamApps -Filter 'appmanifest_*.acf' -ErrorAction SilentlyContinue
        foreach ($manifest in $manifests) {
            $text = Get-Content -LiteralPath $manifest.FullName -Raw -ErrorAction SilentlyContinue
            $name = $null
            $dir = $null
            if ($text -match '"name"\s*"([^"]+)"') { $name = $Matches[1] }
            if ($text -match '"installdir"\s*"([^"]+)"') { $dir = $Matches[1] }
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($dir)) { continue }

            $gameDir = Join-Path (Join-Path $steamApps 'common') $dir
            if (-not (Test-Path -LiteralPath $gameDir)) { continue }
            $mainExe = Get-ChildItem -LiteralPath $gameDir -Filter '*.exe' -File -ErrorAction SilentlyContinue |
                Sort-Object Length -Descending | Select-Object -First 1
            if ($null -eq $mainExe) { continue }

            $detected += [pscustomobject]@{ Name = $name; ExePath = $mainExe.FullName; Source = 'Steam' }
        }
    }

    foreach ($game in ($detected | Sort-Object Name)) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = ('{0}   [{1}]' -f $game.Name, $game.Source)
        $item.Tag = $game
        [void]$listGames.Items.Add($item)
    }
    foreach ($game in $customGames) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = ('{0}   [custom]' -f $game.Name)
        $item.Tag = $game
        [void]$listGames.Items.Add($item)
    }

    Write-Log ('Games in the list: {0} ({1} from Steam)' -f $listGames.Items.Count, $detected.Count)
}

function Add-CustomGame {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Filter = 'Game executables (*.exe)|*.exe'
    $dialog.Title = 'Select the game executable'
    if ($dialog.ShowDialog() -eq $true) {
        $game = [pscustomobject]@{
            Name    = [System.IO.Path]::GetFileNameWithoutExtension($dialog.FileName)
            ExePath = $dialog.FileName
            Source  = 'custom'
        }
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = ('{0}   [custom]' -f $game.Name)
        $item.Tag = $game
        [void]$listGames.Items.Add($item)
        Write-Log ('Game added: {0}' -f $game.Name) 'OK'
    }
}

function Update-GameCheckboxes {
    if ($null -eq $listGames.SelectedItem) { return }
    $game = [pscustomobject]$listGames.SelectedItem.Tag

    $gpuVal = $null
    $gpuProps = Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences' -ErrorAction SilentlyContinue
    if ($null -ne $gpuProps) {
        $match = $gpuProps.PSObject.Properties | Where-Object { $_.Name -eq $game.ExePath }
        if ($null -ne $match) { $gpuVal = $match.Value }
    }
    $chkGameGpu.IsChecked = ($gpuVal -eq 'GpuPreference=2;')

    $fseVal = $null
    $layerProps = Get-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' -ErrorAction SilentlyContinue
    if ($null -ne $layerProps) {
        $match = $layerProps.PSObject.Properties | Where-Object { $_.Name -eq $game.ExePath }
        if ($null -ne $match) { $fseVal = $match.Value }
    }
    $chkGameFse.IsChecked = ($fseVal -match 'DISABLEDXMAXIMIZEDWINDOWEDMODE')
}

function Apply-GameTweaks {
    if ($null -eq $listGames.SelectedItem) {
        Write-Log 'Select a game in the list first' 'WARN'
        return
    }
    $game = [pscustomobject]$listGames.SelectedItem.Tag
    Write-Log ('Applying per-game tweaks for {0}' -f $game.Name)

    $gpuKey = 'HKCU:\SOFTWARE\Microsoft\DirectX\UserGpuPreferences'
    $layerKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'

    if ($chkGameGpu.IsChecked) {
        Set-RegValue -Path $gpuKey -Name $game.ExePath -Value 'GpuPreference=2;' -Type 'String' | Out-Null
    } else {
        Backup-RegValue -Path $gpuKey -Name $game.ExePath
        Remove-ItemProperty -Path $gpuKey -Name $game.ExePath -ErrorAction SilentlyContinue
        Write-Log 'High performance GPU flag removed' 'OK'
    }

    if ($chkGameFse.IsChecked) {
        Set-RegValue -Path $layerKey -Name $game.ExePath -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' -Type 'String' | Out-Null
    } else {
        Backup-RegValue -Path $layerKey -Name $game.ExePath
        Remove-ItemProperty -Path $layerKey -Name $game.ExePath -ErrorAction SilentlyContinue
        Write-Log 'Fullscreen optimizations flag removed' 'OK'
    }

    Write-Log 'Per-game tweaks applied. Restart the game to pick them up.' 'OK'
}

# ----------------------------------------------------------------------------
# Windows Update control, power plan editor, standby monitor
# ----------------------------------------------------------------------------
function Apply-WuSettings {
    Write-Log 'Applying Windows Update settings...'
    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'

    $deferDays = 0
    switch ($cmbWuDefer.SelectedIndex) {
        1 { $deferDays = 7 }
        2 { $deferDays = 14 }
        3 { $deferDays = 30 }
        default { $deferDays = 0 }
    }

    if ($deferDays -gt 0) {
        Set-RegValue -Path $wu -Name 'DeferQualityUpdates' -Value 1 | Out-Null
        Set-RegValue -Path $wu -Name 'DeferQualityUpdatesPeriodInDays' -Value $deferDays | Out-Null
        Set-RegValue -Path $wu -Name 'DeferFeatureUpdates' -Value 1 | Out-Null
        Set-RegValue -Path $wu -Name 'DeferFeatureUpdatesPeriodInDays' -Value $deferDays | Out-Null
    } else {
        Set-RegValue -Path $wu -Name 'DeferQualityUpdates' -Value 0 | Out-Null
        Set-RegValue -Path $wu -Name 'DeferFeatureUpdates' -Value 0 | Out-Null
    }

    if ($chkWuNoDrivers.IsChecked) {
        Set-RegValue -Path $wu -Name 'ExcludeWUDriversInQualityUpdate' -Value 1 | Out-Null
    } else {
        Set-RegValue -Path $wu -Name 'ExcludeWUDriversInQualityUpdate' -Value 0 | Out-Null
    }

    if ($chkWuNoReboot.IsChecked) {
        Set-RegValue -Path $wu -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 | Out-Null
    } else {
        Set-RegValue -Path $wu -Name 'NoAutoRebootWithLoggedOnUsers' -Value 0 | Out-Null
    }

    Write-Log ('Windows Update settings applied (defer {0} days). They take effect after the next update scan.' -f $deferDays) 'OK'
}

function Apply-PowerPlanEditor {
    Write-Log 'Writing custom values to the active power plan...'

    $subProc   = '54533251-82be-4824-96c1-47b60b740d00'
    $procMin   = '893dee8e-2bef-41e0-89c6-b55d0929964c'
    $procMax   = '75b0ae3f-bce0-45a7-8c89-c9611c25e100'
    $subPcie   = '501a4d13-42af-4429-9fd1-a8218c268e20'
    $pcieAspm  = 'ee12f906-d277-404b-b6da-e5fa1a576df5'
    $subVideo  = '7516b95f-f776-4464-8c53-06167f40cc99'
    $videoIdle = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'

    $cpuMin = [int]$sldCpuMin.Value
    $cpuMax = [int]$sldCpuMax.Value
    $pcie = $cmbPcie.SelectedIndex
    $idleSeconds = [int]($sldDisplayOff.Value * 60)

    if ($cpuMin -gt $cpuMax) {
        Write-Log 'CPU min state cannot exceed CPU max state' 'WARN'
        return
    }

    & powercfg.exe /setacvalueindex scheme_current $subProc $procMin $cpuMin 2>$null | Out-Null
    & powercfg.exe /setacvalueindex scheme_current $subProc $procMax $cpuMax 2>$null | Out-Null
    & powercfg.exe /setacvalueindex scheme_current $subPcie $pcieAspm $pcie 2>$null | Out-Null
    & powercfg.exe /setacvalueindex scheme_current $subVideo $videoIdle $idleSeconds 2>$null | Out-Null
    & powercfg.exe /setactive scheme_current 2>$null | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Log ('Power plan set: CPU {0}-{1} percent, PCIe mode {2}, display off after {3} min' -f $cpuMin, $cpuMax, $pcie, $sldDisplayOff.Value) 'OK'
    } else {
        Write-Log 'Power plan values applied with a warning, check the plan in Windows settings' 'WARN'
    }
}

$script:MonitorTimer = $null
$script:LastPurgeLog = [datetime]::MinValue

function Start-StandbyMonitor {
    if ($null -ne $script:MonitorTimer) { return }

    $script:MonitorTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:MonitorTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:MonitorTimer.Add_Tick({
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            $freeMb = [int]($os.FreePhysicalMemory / 1KB)
            $thresholdMb = [int]$sldMonitorThreshold.Value
            $txtMonitorStatus.Text = ('Monitoring: {0} MB free, purge under {1} MB' -f $freeMb, $thresholdMb)

            if ($chkMonitorEnable.IsChecked -and $freeMb -lt $thresholdMb) {
                $outcome = [BaldyBeast.Memory]::PurgeStandbyList()
                if (((Get-Date) - $script:LastPurgeLog) -gt [TimeSpan]::FromSeconds(60)) {
                    Write-Log ('Auto-purge at {0} MB free (threshold {1} MB): {2}' -f $freeMb, $thresholdMb, $outcome) 'OK'
                    $script:LastPurgeLog = Get-Date
                }
            }
        } catch { }
    })
    $script:MonitorTimer.Start()
    Write-Log 'Standby monitor armed. It only acts while this tool is open and the box is ticked.' 'INFO'
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
    'btnCheckUpdate', 'btnDoUpdate', 'txtUpdateStatus',
    'listStartup', 'btnStartupDisable', 'btnStartupEnable', 'btnStartupRefresh', 'btnStartupFolder',
    'cmbDnsProvider', 'btnDnsApply', 'btnDnsTest', 'chkWirelessPower', 'btnWirelessPower', 'txtNetwork',
    'txtBenchmark', 'btnBenchRun', 'btnBenchSave', 'btnBenchCompare', 'btnBenchOpen',
    'btnExportBundle', 'btnMakeShortcut', 'chkClassicMenu',
    'txtMemory', 'btnPurgeStandby', 'btnMemoryRefresh', 'btnPurgeStandbyQuick',
    'chkTaskbarLeft', 'chkTaskbarSearch', 'chkTaskbarTaskView', 'btnApplyRecommended', 'btnOpenDisplay',
    'listRestorePoints', 'btnRestorePointGo', 'btnRestorePointRefresh', 'btnWipeRecall',
    'panelApps', 'btnAppsAll', 'btnAppsNone', 'btnAppsInstall',
    'listGames', 'btnGamesRefresh', 'btnGameAdd', 'btnGameRemove', 'chkGameGpu', 'chkGameFse', 'btnApplyGame',
    'cmbWuDefer', 'chkWuNoDrivers', 'chkWuNoReboot', 'btnApplyWu',
    'sldCpuMin', 'sldCpuMax', 'cmbPcie', 'sldDisplayOff', 'btnApplyPower',
    'chkMonitorEnable', 'sldMonitorThreshold', 'txtMonitorStatus'
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

Startup and Network:
  The Startup tab disables programs that launch with Windows (quarantined in the
  registry, never deleted). The Network tab switches DNS providers and tests
  latency so you can pick the fastest resolver for your line.

Benchmark and Memory:
  The Benchmark tab measures CPU, memory and disk so you can prove what a tweak
  actually changed (run, save baseline, tweak, run, compare). The Hardware tab
  has a RAMMap style memory breakdown and a Purge Standby List button that
  releases cached file pages instantly.

Support:
  The About tab exports a support bundle (hardware, tweaks, benchmark, log) for
  GitHub issues and creates a Desktop shortcut so you never need the one-liner
  again.

Safety and compatibility:
  The Backups tab lists Windows System Restore points and can restore the whole
  PC to any of them. Options that do not apply to your Windows build are greyed
  out automatically. The Clean tab can delete Windows Recall snapshot data.

Fresh install and games:
  The Apps tab installs a curated essentials list through winget in one batch.
  The Games tab detects your Steam games and sets per-game flags (high
  performance GPU, fullscreen optimizations off). Bloatware removal shows an
  exact preview before deleting anything.

One line install from GitHub:
  irm "$($script:RepoRawUrl)" | iex

Safety notes:
  - Every change is logged to the Console Log and to $($script:LogFile).
  - Bloatware removal is opt-in per category. Gaming Services and Game Bar are kept.
  - Telemetry, background apps and Cortana are disabled by policy, not deleted.
  - The tool does not touch personal files, browsers, passwords or network settings.

Copyright (c) 2026 BaldyBeast. All rights reserved.   |   License: MIT   |   Use at your own risk.
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
        'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall', 'chkClassicMenu'
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
    Set-CheckboxSelection -Names @('chkBloatBing', 'chkBloat3D', 'chkBloatGames', 'chkBloatCortana', 'chkTelemetry', 'chkServices', 'chkCortana', 'chkBackgroundApps', 'chkConsumer', 'chkActivity', 'chkWidgets', 'chkCopilot', 'chkRecall', 'chkClassicMenu')
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

$btnStartupRefresh.Add_Click({ Update-StartupList })
$btnStartupFolder.Add_Click({
    $startupFolder = [Environment]::GetFolderPath('Startup')
    Start-Process -FilePath 'explorer.exe' -ArgumentList $startupFolder
})
$btnStartupDisable.Add_Click({
    if ($null -eq $listStartup.SelectedItem) {
        Write-Log 'Select a startup entry first' 'WARN'
        return
    }
    $entry = [pscustomobject]$listStartup.SelectedItem.Tag
    if ($entry.Disabled) {
        Write-Log ('{0} is already disabled' -f $entry.Name) 'WARN'
        return
    }
    if (Confirm-Action 'Disable startup entry' ('Stop "{0}" from starting with Windows? You can enable it again at any time.' -f $entry.Name)) {
        Disable-StartupEntry -Entry $entry
        Update-StartupList
    }
})
$btnStartupEnable.Add_Click({
    if ($null -eq $listStartup.SelectedItem) {
        Write-Log 'Select a startup entry first' 'WARN'
        return
    }
    $entry = [pscustomobject]$listStartup.SelectedItem.Tag
    if (-not $entry.Disabled) {
        Write-Log ('{0} is already enabled' -f $entry.Name) 'WARN'
        return
    }
    Enable-StartupEntry -Entry $entry
    Update-StartupList
})

$btnDnsApply.Add_Click({
    $providerLabels = @('Cloudflare', 'Google', 'Quad9', 'AdGuard', 'Automatic')
    $providerName = $providerLabels[$cmbDnsProvider.SelectedIndex]
    if (Confirm-Action 'Change DNS' ('Switch DNS on all active adapters to {0}?' -f $providerName)) {
        Set-DnsProvider -ProviderName $providerName
        $txtNetwork.Text = ((Get-NetworkSummary) -join [System.Environment]::NewLine)
    }
})
$btnDnsTest.Add_Click({ Test-NetworkLatency })
$btnWirelessPower.Add_Click({ Set-WirelessMaxPerformance })

$btnBenchRun.Add_Click({ Start-Benchmark })
$btnBenchSave.Add_Click({ Save-BenchmarkBaseline })
$btnBenchCompare.Add_Click({ Compare-BenchmarkToBaseline })
$btnBenchOpen.Add_Click({
    if (-not (Test-Path -LiteralPath $script:BenchmarkDir)) {
        New-Item -Path $script:BenchmarkDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList $script:BenchmarkDir
})

$btnExportBundle.Add_Click({
    if (Confirm-Action 'Export Support Bundle' 'Create a zip on your Desktop with the hardware info, tweak selection, benchmark results and the log? This is what you attach to a GitHub issue.') {
        Export-SupportBundle
    }
})
$btnMakeShortcut.Add_Click({ New-DesktopShortcut })

$btnPurgeStandby.Add_Click({
    if (Confirm-Action 'Purge Standby List' 'Release all cached file pages from RAM now? Safe to do, Windows re-caches as needed. The next app launches may be slightly slower for a few minutes.') {
        Clear-StandbyList
    }
})
$btnPurgeStandbyQuick.Add_Click({
    if (Confirm-Action 'Purge Standby List' 'Release all cached file pages from RAM now? Safe to do, Windows re-caches as needed. The next app launches may be slightly slower for a few minutes.') {
        Clear-StandbyList
    }
})
$btnMemoryRefresh.Add_Click({ Update-MemoryInfo })

$btnApplyRecommended.Add_Click({ Invoke-RecommendedTweaks })
$btnOpenDisplay.Add_Click({
    try {
        Start-Process 'ms-settings:display' | Out-Null
        Write-Log 'Opened Windows Display settings. Check Advanced display and pick the highest refresh rate.' 'INFO'
    } catch {
        Write-Log ('Could not open display settings: {0}' -f $_.Exception.Message) 'ERROR'
    }
})

$btnRestorePointRefresh.Add_Click({ Update-RestorePointList })
$btnRestorePointGo.Add_Click({
    if ($null -eq $listRestorePoints.SelectedItem) {
        Write-Log 'Select a restore point in the list first' 'WARN'
        return
    }
    $seq = [int]$listRestorePoints.SelectedItem.Tag
    $question = 'Restore the whole PC to restore point seq {0}?' -f $seq
    $question += ' This restarts the computer and rolls back system files, drivers and registry to that moment. Personal files are not affected.'
    if (Confirm-Action 'System Restore' $question) {
        Restore-ComputerToPoint -SequenceNumber $seq
    }
})
$btnWipeRecall.Add_Click({
    if (Confirm-Action 'Delete Recall snapshots' 'Delete all Windows Recall snapshot data on this PC? This cannot be undone, but Recall stays disabled while the Debloat toggle is applied.') {
        Remove-RecallSnapshots
    }
})

$btnAppsAll.Add_Click({
    foreach ($box in $panelApps.Children) {
        if ($box -is [System.Windows.Controls.CheckBox]) { $box.IsChecked = $true }
    }
    Write-Log 'All apps in the kit are ticked' 'OK'
})
$btnAppsNone.Add_Click({
    foreach ($box in $panelApps.Children) {
        if ($box -is [System.Windows.Controls.CheckBox]) { $box.IsChecked = $false }
    }
    Write-Log 'App selection cleared' 'OK'
})
$btnAppsInstall.Add_Click({ Install-SelectedApps })

$btnGamesRefresh.Add_Click({ Update-GameList })
$btnGameAdd.Add_Click({ Add-CustomGame })
$btnGameRemove.Add_Click({
    if ($null -ne $listGames.SelectedItem) {
        $name = [string]$listGames.SelectedItem.Tag.Name
        [void]$listGames.Items.Remove($listGames.SelectedItem)
        Write-Log ('Game removed from the list: {0} (its registry flags are untouched)' -f $name) 'OK'
    } else {
        Write-Log 'Select a game in the list first' 'WARN'
    }
})
$listGames.Add_SelectionChanged({ Update-GameCheckboxes })
$btnApplyGame.Add_Click({ Apply-GameTweaks })

$btnApplyWu.Add_Click({ Apply-WuSettings })
$btnApplyPower.Add_Click({ Apply-PowerPlanEditor })

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
    'chkWirelessPower'  = @('Recommended', 'Stops Windows from lowering wireless adapter power, which keeps ping and packet loss steadier on WiFi. Uses a bit more battery on laptops.')
    'chkClassicMenu'    = @('Recommended', 'Brings back the full Windows 10 style right-click menu on Windows 11. Restart Explorer or sign out to see it.')
    'chkTaskbarLeft'    = @('Safe', 'Moves the taskbar icons back to the left like Windows 10. Pure looks, Windows 11 only.')
    'chkTaskbarSearch'  = @('Safe', 'Removes the search box from the taskbar. You can still press the Windows key and type.')
    'chkTaskbarTaskView' = @('Safe', 'Removes the Task View button from the taskbar. Win plus Tab still works.')
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
$window.Title = ('BALDYBEAST OPTIMIZER v{0}' -f $script:AppVersion)
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

Set-TweakAvailability
Update-HardwareInfo
Update-MemoryInfo
Update-ProfileList
Update-BackupList
Update-RestorePointList
Update-StartupList
Update-GameList
Start-StandbyMonitor
$txtNetwork.Text = ((Get-NetworkSummary) -join [System.Environment]::NewLine)
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

    # Read-only smoke tests for the v1.2 tabs
    try {
        $startupEntries = @(Get-StartupEntries)
        Write-Host ('STARTUP TEST OK - {0} startup entries discovered' -f $startupEntries.Count) -ForegroundColor Green
    } catch {
        Write-Host ('STARTUP TEST FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
    try {
        $networkLines = @(Get-NetworkSummary)
        Write-Host ('NETWORK TEST OK - {0} summary lines produced' -f $networkLines.Count) -ForegroundColor Green
    } catch {
        Write-Host ('NETWORK TEST FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }

    # v1.3 smoke tests: tiny benchmark run, memory read, registry default value mapping
    try {
        $benchMs = Invoke-CpuSingleWork -Rounds 20000
        $multiMs = Invoke-CpuMultiWork -Rounds 20000 -Threads 2
        $memMBps = Invoke-MemoryWork -SizeMB 8
        $disk = Invoke-DiskWork -Path $env:TEMP -SizeMB 4
        if ($benchMs -gt 0 -and $multiMs -gt 0 -and $memMBps -gt 0 -and $disk.WriteMBps -gt 0 -and $disk.ReadMBps -gt 0) {
            Write-Host ('BENCHMARK TEST OK - cpu {0} ms, memory {1} MB/s, disk write {2} MB/s' -f $benchMs, $memMBps, $disk.WriteMBps) -ForegroundColor Green
        } else {
            Write-Host 'BENCHMARK TEST FAILED - a phase returned zero' -ForegroundColor Red
        }
    } catch {
        Write-Host ('BENCHMARK TEST FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
    try {
        $memLines = @()
        $osMem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $memLines += ('{0:N1} GB total' -f ($osMem.TotalVisibleMemorySize * 1KB / 1GB))
        Write-Host ('MEMORY TEST OK - {0}' -f ($memLines -join '; ')) -ForegroundColor Green
    } catch {
        Write-Host ('MEMORY TEST FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }
    try {
        $defaultKey = 'HKCU:\Software\BaldyBeastValidateTestDefault\InprocServer32'
        New-Item -Path $defaultKey -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $defaultKey -Name '(default)' -Value '' -PropertyType String -Force -ErrorAction Stop | Out-Null
        $defaultNames = @((Get-Item -LiteralPath $defaultKey).GetValueNames())
        if ($defaultNames -contains '') {
            Write-Host 'DEFAULT VALUE TEST OK - (default) maps to the real registry default value' -ForegroundColor Green
        } else {
            Write-Host ('DEFAULT VALUE TEST FAILED - names present: [{0}]' -f ($defaultNames -join ',')) -ForegroundColor Red
        }
        Remove-Item -Path 'HKCU:\Software\BaldyBeastValidateTestDefault' -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host ('DEFAULT VALUE TEST FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Remove-Item -Path 'HKCU:\Software\BaldyBeastValidateTestDefault' -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Standby purge smoke test: exercises the interop end to end. Non-elevated
    # runs report a clean privilege message instead of crashing.
    try {
        $purgeOutcome = [BaldyBeast.Memory]::PurgeStandbyList()
        Write-Host ('PURGE SMOKE OK - interop returned: {0}' -f $purgeOutcome) -ForegroundColor Green
    } catch {
        Write-Host ('PURGE SMOKE FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }

    # Optional visual QA: render every tab to PNG (BALDYBEAST_RENDER=1)
    if ($env:BALDYBEAST_RENDER -eq '1') {
        $renderDir = Join-Path $env:TEMP 'bb-ui'
        if (Test-Path -LiteralPath $renderDir) {
            Remove-Item -LiteralPath $renderDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -Path $renderDir -ItemType Directory -Force | Out-Null
        try {
            $window.Width = 1140
            $window.Height = 820
            $window.WindowStartupLocation = 'Manual'
            $window.Left = -4000
            $window.Top = -4000
            $window.Show()
            $window.UpdateLayout()

            for ($t = 0; $t -lt $tabMain.Items.Count; $t++) {
                $tabMain.SelectedIndex = $t
                $window.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
                $window.UpdateLayout()

                $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth, [int]$window.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
                $bmp.Render($window)
                $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
                $safeName = ('{0:D2}-{1}.png' -f $t, ([string]$tabMain.Items[$t].Header -replace '[^A-Za-z0-9]', ''))
                $stream = [System.IO.File]::Create((Join-Path $renderDir $safeName))
                $encoder.Save($stream)
                $stream.Close()
            }

            $window.Close()
            Write-Host ('UI RENDER OK - {0} tab images in {1}' -f $tabMain.Items.Count, $renderDir) -ForegroundColor Green
        } catch {
            Write-Host ('UI RENDER FAILED: {0}' -f $_.Exception.Message) -ForegroundColor Red
            try { $window.Close() } catch { }
        }
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
