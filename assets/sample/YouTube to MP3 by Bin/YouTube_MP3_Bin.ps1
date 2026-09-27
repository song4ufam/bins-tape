# YouTube -> MP3 Bin Edition
$ErrorActionPreference = "Stop"
$MyInitial = "Bin"

$AppRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$Runtime = Join-Path $AppRoot "runtime"
$Bin = Join-Path $Runtime "bin"
$Out = Join-Path ([Environment]::GetFolderPath("MyMusic")) "YouTube MP3"
New-Item -ItemType Directory -Force -Path $Bin, $Out | Out-Null

$YtDlp = Join-Path $Bin "yt-dlp.exe"
$Deno = Join-Path $Bin "deno.exe"
$FFmpeg = Join-Path $Bin "ffmpeg.exe"

function Download-File($Url, $Path) {
    $tmp = "$Path.download"
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing
    Move-Item $tmp $Path -Force
}

function Ensure-Tools {
    $need = @()
    if (!(Test-Path $YtDlp)) { $need += "yt-dlp" }
    if (!(Test-Path $Deno)) { $need += "Deno" }
    if (!(Test-Path $FFmpeg)) { $need += "FFmpeg" }

    if ($need.Count -gt 0) {
        $setup = New-Object System.Windows.Forms.Form
        $setup.Text = "YouTube → MP3 | 처음 실행 준비"
        $setup.Size = New-Object System.Drawing.Size(520,210)
        $setup.StartPosition = "CenterScreen"
        $setup.TopMost = $true

        $label = New-Object System.Windows.Forms.Label
        $label.Text = "필요한 구성요소를 준비합니다.`r`n인터넷 연결이 필요합니다.`r`n`r`n준비 중..."
        $label.Location = New-Object System.Drawing.Point(25,25)
        $label.Size = New-Object System.Drawing.Size(450,75)
        $setup.Controls.Add($label)

        $bar = New-Object System.Windows.Forms.ProgressBar
        $bar.Location = New-Object System.Drawing.Point(25,110)
        $bar.Size = New-Object System.Drawing.Size(450,24)
        $bar.Style = "Marquee"
        $setup.Controls.Add($bar)
        $setup.Show()
        $setup.Refresh()

        try {
            if (!(Test-Path $YtDlp)) {
                $label.Text = "yt-dlp를 준비하는 중..."
                $setup.Refresh()
                Download-File "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" $YtDlp
            }

            if (!(Test-Path $Deno)) {
                $label.Text = "Deno를 준비하는 중..."
                $setup.Refresh()
                $zip = Join-Path $Runtime "deno.zip"
                Download-File "https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip" $zip
                Expand-Archive -Path $zip -DestinationPath $Runtime -Force
                $denoFound = Get-ChildItem $Runtime -Filter "deno.exe" -Recurse | Select-Object -First 1
                if (!$denoFound) { throw "Deno 압축파일 오류" }
                Copy-Item $denoFound.FullName $Deno -Force
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
            }

            if (!(Test-Path $FFmpeg)) {
                $label.Text = "FFmpeg를 준비하는 중..."
                $setup.Refresh()
                $zip = Join-Path $Runtime "ffmpeg.zip"
                Download-File "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" $zip
                $extract = Join-Path $Runtime "ffmpeg_extract"
                if (Test-Path $extract) { Remove-Item $extract -Recurse -Force }
                Expand-Archive -Path $zip -DestinationPath $extract -Force
                $ff = Get-ChildItem $extract -Filter "ffmpeg.exe" -Recurse | Select-Object -First 1
                $fp = Get-ChildItem $extract -Filter "ffprobe.exe" -Recurse | Select-Object -First 1
                if (!$ff) { throw "FFmpeg 압축파일 오류" }
                Copy-Item $ff.FullName $FFmpeg -Force
                if ($fp) { Copy-Item $fp.FullName (Join-Path $Bin "ffprobe.exe") -Force }
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                Remove-Item $extract -Recurse -Force -ErrorAction SilentlyContinue
            }
            $setup.Close()
        } catch {
            $setup.Close()
            [System.Windows.Forms.MessageBox]::Show("구성요소 준비 실패: $($_.Exception.Message)", "오류", "OK", "Error") | Out-Null
            throw
        }
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Ensure-Tools

$form = New-Object System.Windows.Forms.Form
$form.Text = "YouTube → MP3 ($MyInitial)"
$form.Size = New-Object System.Drawing.Size(680,390)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = "YouTube → MP3  by $MyInitial"
$title.Font = New-Object System.Drawing.Font("Malgun Gothic",18,[System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(25,18)
$title.Size = New-Object System.Drawing.Size(500,40)
$form.Controls.Add($title)

$lab = New-Object System.Windows.Forms.Label
$lab.Text = "유튜브 주소"
$lab.Location = New-Object System.Drawing.Point(28,72)
$lab.Size = New-Object System.Drawing.Size(120,25)
$form.Controls.Add($lab)

$url = New-Object System.Windows.Forms.TextBox
$url.Location = New-Object System.Drawing.Point(28,98)
$url.Size = New-Object System.Drawing.Size(610,32)
$url.Font = New-Object System.Drawing.Font("Malgun Gothic",10)
$form.Controls.Add($url)

$paste = New-Object System.Windows.Forms.Button
$paste.Text = "붙여넣기"
$paste.Location = New-Object System.Drawing.Point(528,136)
$paste.Size = New-Object System.Drawing.Size(110,32)
$paste.Add_Click({
    try { $url.Text = [Windows.Forms.Clipboard]::GetText() } catch {}
})
$form.Controls.Add($paste)

$folderLabel = New-Object System.Windows.Forms.Label
$folderLabel.Text = "저장 위치"
$folderLabel.Location = New-Object System.Drawing.Point(28,174)
$folderLabel.Size = New-Object System.Drawing.Size(100,25)
$form.Controls.Add($folderLabel)

$folder = New-Object System.Windows.Forms.TextBox
$folder.Text = $Out
$folder.Location = New-Object System.Drawing.Point(28,200)
$folder.Size = New-Object System.Drawing.Size(500,30)
$form.Controls.Add($folder)

$choose = New-Object System.Windows.Forms.Button
$choose.Text = "폴더 선택"
$choose.Location = New-Object System.Drawing.Point(538,198)
$choose.Size = New-Object System.Drawing.Size(100,32)
$choose.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.SelectedPath = $folder.Text
    if ($d.ShowDialog() -eq "OK") { $folder.Text = $d.SelectedPath }
})
$form.Controls.Add($choose)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(28,248)
$progress.Size = New-Object System.Drawing.Size(610,25)
$form.Controls.Add($progress)

$status = New-Object System.Windows.Forms.Label
$status.Text = "대기 중"
$status.Location = New-Object System.Drawing.Point(28,280)
$status.Size = New-Object System.Drawing.Size(610,25)
$form.Controls.Add($status)

$start = New-Object System.Windows.Forms.Button
$start.Text = "MP3 변환 시작"
$start.Font = New-Object System.Drawing.Font("Malgun Gothic",11,[System.Drawing.FontStyle]::Bold)
$start.Location = New-Object System.Drawing.Point(28,315)
$start.Size = New-Object System.Drawing.Size(610,38)
$form.Controls.Add($start)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 250
$timer.Add_Tick({
    if ($script:proc -and !$script:proc.HasExited) {
        try {
            while (!$script:proc.StandardOutput.EndOfStream) {
                $line = $script:proc.StandardOutput.ReadLine()
                if ($line -match '(\d+(?:\.\d+)?)%') {
                    $v = [math]::Min(100,[math]::Max(0,[double]$Matches[1]))
                    $progress.Value = [int]$v
                }
                if ($line -match '\[download\]') { $status.Text = "다운로드 중..." }
                if ($line -match 'Destination:|Merging|ExtractAudio') { $status.Text = "MP3 변환 중..." }
            }
        } catch {}
    } elseif ($script:proc) {
        $timer.Stop()
        if ($script:proc.ExitCode -eq 0) {
            $progress.Value = 100
            $status.Text = "변환 완료"
            [System.Windows.Forms.MessageBox]::Show("MP3 저장이 완료되었습니다.`r`n`r`n$($folder.Text)", "완료", "OK", "Information") | Out-Null
        } else {
            $status.Text = "변환 실패"
            [System.Windows.Forms.MessageBox]::Show("변환에 실패했습니다.", "실패", "OK", "Error") | Out-Null
        }
        $start.Enabled = $true
        $script:proc = $null
    }
})

$start.Add_Click({
    $u = $url.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($u)) {
        [System.Windows.Forms.MessageBox]::Show("유튜브 주소를 입력하세요.","경고","OK","Warning") | Out-Null
        return
    }

    $dest = $folder.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($dest)) { $dest = $Out }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    $start.Enabled = $false
    $progress.Value = 0
    $status.Text = "준비 중..."

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $YtDlp
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $Bin
    $psi.Arguments = "--no-playlist --newline --progress --js-runtimes `"" + "deno:$Deno" + "`" --ffmpeg-location `"" + $Bin + "`" -x --audio-format mp3 --audio-quality 192K -o `"" + $dest + "\%(title)s.%(ext)s`" `"" + $u + "`""

    $script:proc = New-Object System.Diagnostics.Process
    $script:proc.StartInfo = $psi
    [void]$script:proc.Start()
    $timer.Start()
})

$form.Add_Shown({ $url.Focus() })
[void]$form.ShowDialog()