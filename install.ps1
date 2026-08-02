
param(
    [switch]$Yes,
    [string]$Firmware
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root     = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Config   = Join-Path $Root 'config.yaml'
$RepoUrl  = if ($env:REPO_URL) { $env:REPO_URL } else { 'https://github.com/enricleon-selfhosted/bticino-c100x.git' }
$FwzVer   = if ($env:FWZ_VERSION) { $env:FWZ_VERSION } else { 'v1.0.0' }
$FwzBase  = if ($env:FWZ_BASE_URL) { $env:FWZ_BASE_URL }
            else { "https://github.com/enricleon-selfhosted/bticino-c100x/releases/download/$FwzVer" }

function Say($t)  { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Step($t) { Write-Host "   $t" }
function Die($t)  { Write-Host ''; Write-Host "STOP: $t" -ForegroundColor Red; exit 1 }

function Read-ConfigFile($path) {
    $map = @{}
    if (-not (Test-Path $path)) { return $map }
    $section = ''
    foreach ($line in Get-Content $path) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^(\S+):\s*$')            { $section = $Matches[1]; continue }
        if ($line -match '^\s+(\S+):\s*(.*)$') {
            $name = $Matches[1]
            $v    = $Matches[2].Trim()
            if ($v -match '^"(.*)"$' -or $v -match "^'(.*)'$") { $v = $Matches[1] }
            $map["$section.$name"] = $v
        }
        elseif ($line -match '^(\S+):\s*(.+)$')    { $map[$Matches[1]] = $Matches[2].Trim() }
    }
    return $map
}

function Read-Config { return Read-ConfigFile $Config }

$answers = Read-Config
$given   = @{}

function Ask($key, $question, $fallback, [switch]$Secret) {
    $current = if ($answers.ContainsKey($key)) { $answers[$key] } else { $fallback }
    if ($Yes) { $given[$key] = $current; return $current }

    $shown = if ($Secret -and $current) { '*' * 8 } else { $current }
    $reply = Read-Host "   $question [$shown]"
    if ([string]::IsNullOrWhiteSpace($reply)) { $reply = $current }
    $given[$key] = $reply
    return $reply
}

function Write-Config {
    $out = @('# Written by install.ps1. Edit it by hand if you prefer.', '')
    foreach ($section in @('mqtt','device','cloud','door','video')) {
        $keys = $given.Keys | Where-Object { $_ -like "$section.*" } | Sort-Object
        if (-not $keys) { continue }
        $out += "${section}:"
        foreach ($k in $keys) {
            $name = $k.Substring($section.Length + 1)
            $out += "  ${name}: `"$($given[$k])`""
        }
        $out += ''
    }
    $text = ($out -join "`n") + "`n"
    [IO.File]::WriteAllText($Config, $text, (New-Object Text.UTF8Encoding $false))
}

function Guess-Ip {
    try {
        $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
             Sort-Object RouteMetric | Select-Object -First 1
        return (Get-NetIPAddress -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -ErrorAction Stop |
                Select-Object -First 1).IPAddress
    } catch { return '' }
}

function Get-Fwz {
    if ($env:FWZ -and (Test-Path $env:FWZ)) { return $env:FWZ }
    foreach ($p in @("$Root\build\Release\fwz.exe", "$Root\build\fwz.exe")) {
        if (Test-Path $p) { Step 'using the fwz you built'; return $p }
    }

    $dir  = Join-Path $Root '.tools'
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { Die 'fwz is only built for 64-bit Windows' }
    $name = "fwz-windows-$arch.exe"
    $tool = Join-Path $dir $name
    if (Test-Path $tool) { return $tool }

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Step "fetching fwz for windows $arch"
    try { Invoke-WebRequest -Uri "$FwzBase/$name" -OutFile "$tool.part" -UseBasicParsing }
    catch { Die "could not download $FwzBase/$name`n      Check your connection, or build it: cmake -B build tools\fwz; cmake --build build" }

    try {
        $sums = (Invoke-WebRequest -Uri "$FwzBase/sha256sums.txt" -UseBasicParsing).Content
        $want = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($name) } |
                 Select-Object -First 1) -split '\s+' | Select-Object -First 1
        if ($want) {
            $got = (Get-FileHash "$tool.part" -Algorithm SHA256).Hash.ToLower()
            if ($got -ne $want.ToLower()) {
                Remove-Item "$tool.part" -Force
                Die "the downloaded fwz is not the published one.`n      expected $want`n      got      $got"
            }
            Step 'checksum ok'
        }
    } catch {
        Step 'WARNING: no checksum list published, cannot verify'
    }
    Move-Item "$tool.part" $tool -Force

    Assert-FwzRuns $tool
    return $tool
}

function Die-AntivirusTookIt($path, $what) {
    Die @"
$what

      Windows Defender does this. The program is small, written in C, signed by nobody, and
      it writes to disk images, which together is enough for the guesswork to call it a
      threat. It is not one. Defender's name for it is something like
      Trojan:Win32/Bearfoos.A!ml, and the ml on the end means a guess made by a model rather
      than a match against anything known.

      There is no arguing with it from here, so there are two ways forward.

      Allow it. Windows Security, then Virus and threat protection, then Protection history.
      Find the item, choose Allow, and run this again.

      Or build it yourself, which downloads nothing:
          cmake -B build tools\fwz
          cmake --build build --config Release
          .\install.ps1

      The program: $path
"@
}

function Assert-FwzRuns($path) {
    if (-not (Test-Path $path)) {
        Die-AntivirusTookIt $path 'the fwz program is gone from the disk.'
    }
    $ok = $true
    try {
        $null = & $path version 2>&1
        if ($LASTEXITCODE -ne 0) { $ok = $false }
    } catch { $ok = $false }
    if (-not $ok) {
        Die-AntivirusTookIt $path 'the fwz program is on disk, but Windows will not run it.'
    }
}

function Write-Answers($configPath, $outPath) {
    $c = Read-ConfigFile $configPath
    $lines = @('# Written by the installer. Edit config.yaml and build again instead of this.')
    $map = [ordered]@{
        MQTT_HOST              = 'mqtt.host'
        MQTT_PORT              = 'mqtt.port'
        MQTT_USER              = 'mqtt.username'
        MQTT_PASS              = 'mqtt.password'
        MQTT_TOPIC             = 'mqtt.topic'
        MQTT_INTERVAL          = 'mqtt.status_interval'
        CLOUD_MODE             = 'cloud.mode'
        BLOCK_FIRMWARE_UPDATES = 'cloud.block_updates'
        VIDEO_FMTP             = 'video.fmtp'
        DOOR_OPEN              = 'door.open_sequence'
        DOOR_CLOSE             = 'door.close_sequence'
        STARTUP_DELAY          = 'device.startup_delay'
    }
    foreach ($k in $map.Keys) {
        $v = if ($c.ContainsKey($map[$k])) { $c[$map[$k]] } else { '' }
        $lines += "$k='" + ($v -replace "'", "'\''") + "'"
    }
    [IO.File]::WriteAllText($outPath, ($lines -join "`n") + "`n")
}

function Build-Payload($payloadDir, $fwz) {
    $cache = Join-Path $Root 'firmware\build\cache'
    New-Item -ItemType Directory -Force -Path $cache, $payloadDir, "$payloadDir\payload" | Out-Null

    $bundle = Join-Path $Root 'device\controller\bundle.js'
    if (-not (Test-Path $bundle)) { Die 'device/controller/bundle.js is missing from this copy' }
    $wantSum = (Get-Content "$bundle.md5" -Raw).Trim()
    $gotSum = (Get-FileHash $bundle -Algorithm MD5).Hash.ToLower()
    if ($wantSum -and $gotSum -ne $wantSum) {
        Die "device/controller/bundle.js is not the file this project shipped.`n      expected $wantSum`n      got      $gotSum"
    }
    Copy-Item $bundle "$payloadDir\payload\bundle.js" -Force
    Step 'controller  the one shipped with this project'

    foreach ($f in @('run.sh', 'patch-aswm.sh')) {
        $src = Join-Path $Root "device\$(if ($f -eq 'run.sh') { 'payload\' } else { '' })$f"
        Copy-Item $src "$payloadDir\payload\$f" -Force
    }
    Copy-Item (Join-Path $Root 'device\setup.sh') "$payloadDir\setup.sh" -Force
    Copy-Item (Join-Path $Root 'device\go2rtc.yaml') "$payloadDir\payload\go2rtc.yaml" -Force

    New-Item -ItemType Directory -Force -Path "$payloadDir\converge.d" | Out-Null
    Copy-Item (Join-Path $Root 'device\converge.d\*') "$payloadDir\converge.d\" -Force
    Step "converge    $((Get-ChildItem "$payloadDir\converge.d" -File | Measure-Object).Count) steps"

    $out = "$payloadDir\payload\runtime.tar.gz"
    if (Test-Path $out) { Step 'runtime     already assembled' }
    else {
        $stage = Join-Path ([IO.Path]::GetTempPath()) ("fwz-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path "$stage\node", "$stage\lib", "$stage\bin" | Out-Null
        $execArgs = @('--exec', 'node/bin/node', '--exec', 'node/bin/node.bin')

        $w = New-Object Net.WebClient
        foreach ($line in Get-Content (Join-Path $Root 'firmware\steps\runtime.manifest')) {
            if (-not $line.Trim() -or $line.Trim().StartsWith('#')) { continue }
            $name, $kind, $dest, $exec, $sha, $url = $line -split '\|'
            $winDest = $dest.Replace('/', '\')

            $supplied = [Environment]::GetEnvironmentVariable($name.ToUpper().Replace('-', '_'))
            $built = Join-Path $Root "tools\$name\build\$name-linux-armv7"
            if ($supplied -and (Test-Path $supplied)) {
                $src = $supplied; Step "$name`: using the one you supplied"
            } elseif (Test-Path $built) {
                $src = $built;    Step "$name`: using the one you built"
            } else {
                $src = "$cache\$name"
                if (-not (Test-Path $src)) {
                    Step "downloading $name"
                    $w.DownloadFile($url, $src)
                }
                $got = (Get-FileHash $src -Algorithm SHA256).Hash.ToLower()
                if ($got -ne $sha) {
                    Die ("$name is not the file expected.`n" +
                         "      expected $sha`n      got      $got`n" +
                         "This goes inside the firmware and runs on your intercom. Delete it from`n" +
                         "$cache and try again.")
                }
            }

            if ($kind -eq 'archive') {
                tar -xzf $src --strip-components 1 -C "$stage\$winDest"
            } else {
                New-Item -ItemType Directory -Force -Path (Split-Path "$stage\$winDest") | Out-Null
                Copy-Item $src "$stage\$winDest" -Force
            }
            if ($exec -eq '1') { $execArgs += @('--exec', $dest) }
        }
        Step 'runtime checksums ok'

        Move-Item "$stage\node\bin\node" "$stage\node\bin\node.bin" -Force

        $wrapper = "#!/bin/sh`nexport LD_LIBRARY_PATH=/home/bticino/cfg/extra/lib:`$LD_LIBRARY_PATH`nexec /home/bticino/cfg/extra/node/bin/node.bin `"`$@`"`n"
        [IO.File]::WriteAllText("$stage\node\bin\node", $wrapper)

        foreach ($junk in @('node\include','node\share','node\lib\node_modules\npm',
                            'node\lib\node_modules\corepack','node\bin\npm',
                            'node\bin\npx','node\bin\corepack')) {
            Remove-Item -Recurse -Force "$stage\$junk" -EA SilentlyContinue
        }
        & $fwz pack --root $stage --out $out @execArgs
        if ($LASTEXITCODE -ne 0) { Die 'could not pack the runtime' }
        Remove-Item -Recurse -Force $stage -EA SilentlyContinue
        Step ("runtime     " + [math]::Round((Get-Item $out).Length / 1MB, 1) + " MB")
    }

    Write-Answers $Config "$payloadDir\setup.conf"
    Step 'answers     written'
}

function Write-Ops($payload, $overlay, $sshKey, $passHash, $path) {
    $L = New-Object System.Collections.Generic.List[string]
    $T = [char]9

    $parent = Split-Path $payload -Parent
    if (-not $parent) { $parent = '.' }
    $keyfile = Join-Path $parent 'authorized_keys'
    if ($sshKey) {
        Set-Content -Path $keyfile -Value $sshKey -NoNewline -Encoding ASCII
        Add-Content -Path $keyfile -Value "`n" -NoNewline
    }

    foreach ($line in Get-Content (Join-Path $Root 'firmware\image.manifest')) {
        if (-not $line.Trim() -or $line.Trim().StartsWith('#')) { continue }
        $f = @($line -split '\|' | ForEach-Object { $_.Trim() })
        $g = { param($i) if ($i -lt $f.Count) { $f[$i] } else { '' } }
        $kind = & $g 0; $a = & $g 1; $b = & $g 2; $c = & $g 3; $d = & $g 4

        switch ($kind) {
            'note'    { $L.Add($a) }
            'append'  {
                $L.Add("append${T}$a${T}$($b.Replace('{HASH}', $passHash))${T}$c")
            }
            'mkdir'   { $L.Add("mkdir${T}$a${T}$b${T}0${T}0") }
            'keydir'  { if ($sshKey) { $L.Add("mkdir${T}$a${T}$b${T}0${T}0") } }
            'key'     { if ($sshKey) { $L.Add("put${T}${keyfile}${T}$a${T}$b${T}0${T}0") } }
            'put'     { $L.Add("put${T}$(Join-Path $payload $a)${T}$b${T}$c${T}0${T}0") }
            'symlink' { $L.Add("symlink${T}$a${T}$b") }
            'rm'      { $L.Add("rm${T}$a") }
            'overlay' {
                $src = Join-Path $overlay $a
                if (Test-Path $src) {
                    if ($d) { $L.Add("mkdir${T}$((Split-Path $b -Parent) -replace '\\','/')${T}$d${T}0${T}0") }
                    $L.Add("put${T}${src}${T}$b${T}$c${T}0${T}0")
                }
            }
            'putdir'  {
                $dir = Join-Path $payload $a
                if (-not (Test-Path $dir)) { Die "image.manifest needs $a in the payload, and Build-Payload did not stage it" }
                Get-ChildItem $dir -File | Sort-Object Name | ForEach-Object {
                    $mode = if ($c -eq 'auto') { if ($_.Name -like '*.sh') { '0755' } else { '0644' } } else { $c }
                    $L.Add("put${T}$(Join-Path $dir $_.Name)${T}$b/$($_.Name)${T}${mode}${T}0${T}0")
                }
            }
            default   { Die "image.manifest has an unknown kind: $kind" }
        }
    }

    [IO.File]::WriteAllText($path, (($L -join "`n") -replace '\\', '/') + "`n")
}

function Main {
    if (-not (Test-Path (Join-Path $Root 'firmware'))) {
        Say 'Fetching the project'
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die 'this needs git to fetch the project.' }
        $target = Join-Path $HOME 'bticino-c100x-local'
        if (Test-Path (Join-Path $target '.git')) { git -C $target pull --ff-only }
        else { git clone --depth 1 $RepoUrl $target }
        & (Join-Path $target 'install.ps1') @PSBoundParameters
        exit $LASTEXITCODE
    }

    Write-Host ''
    Write-Host '  This builds a firmware image for your intercom.' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  A few questions, once. They are saved, so building again asks nothing.'
    Write-Host '  Press enter to keep what is in the brackets.'

    Say 'Your MQTT broker'
    Ask 'mqtt.host' 'address' (Guess-Ip) | Out-Null
    Ask 'mqtt.port' 'port' '1883' | Out-Null
    Ask 'mqtt.username' 'username' '' | Out-Null
    Ask 'mqtt.password' 'password' '' -Secret | Out-Null
    Ask 'mqtt.topic' 'topic prefix' 'bticinocontroller' | Out-Null
    Ask 'mqtt.status_interval' 'seconds between health reports' '60' | Out-Null

    Say 'Getting in'
    if (-not $Yes) {
        Write-Host '   A key is the safe way. The password is a fallback, and the one this'
        Write-Host '   project ships with is PUBLIC. Change it, or know what you are leaving.'
    }
    $defaultKey = ''
    foreach ($k in @("$HOME\.ssh\id_rsa.pub", "$HOME\.ssh\id_ecdsa.pub")) {
        if (Test-Path $k) { $defaultKey = (Get-Content $k -Raw).Trim(); break }
    }
    $sshKey = Ask 'device.ssh_public_key' 'your public ssh key' $defaultKey
    $defaultPass = if ($answers.ContainsKey('device.root_password')) { $answers['device.root_password'] } else { '' }
    $generatedPass = $false
    if (-not $defaultPass) {
        $bytes = [byte[]]::new(16)
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        $defaultPass = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
        $generatedPass = $true
    }
    $rootPass = Ask 'device.root_password' 'fallback password' $defaultPass
    if ($rootPass -ne $defaultPass) { $generatedPass = $false }

    Say "Bticino's cloud"
    Ask 'cloud.mode' "cut Bticino's cloud? (off = cut, on = keep)" 'off' | Out-Null
    Ask 'cloud.block_updates' 'also stop it downloading new firmware? (yes/no)' 'no' | Out-Null

    Say 'The door'
    Ask 'door.open_sequence' 'the command that opens it' '*8*19*20##' | Out-Null
    Ask 'door.close_sequence' 'the command that closes it' '*8*20*20##' | Out-Null

    Say 'The picture'
    Ask 'video.fmtp' 'video parameters' 'packetization-mode=1;profile-level-id=42401E;sprop-parameter-sets=Z0JAHqaAoD2Q,aM48gA==' | Out-Null

    Say 'Starting up'
    Ask 'device.startup_delay' 'seconds to wait before starting' '60' | Out-Null
    $model   = Ask 'device.model' 'model' 'C100X'
    $version = Ask 'device.firmware' 'firmware version' '1.5.8'

    Write-Config
    Say 'Saved your answers'
    Step $Config

    if ($generatedPass) {
        Write-Host ''
        Write-Host "  The fallback password for this unit is:  $rootPass"
        Write-Host '  It is in config.yaml as well. You need it only if you lose the ssh key.'
    }

    if ($rootPass -eq 'pwned123') {
        Write-Host ''
        Write-Host '  You kept the default password.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  It is published in the projects this one is built on, so anybody who'
        Write-Host '  knows about them knows it. On a device that sits on your network all'
        Write-Host '  the time, that is worth a moment of thought.'
        Write-Host ''
        Write-Host '  Change it in config.yaml and build again, or carry on knowingly.'
        Write-Host ''
    }

    $work = Join-Path $Root 'firmware\build'
    New-Item -ItemType Directory -Force -Path $work, "$work\unpack", "$Root\.tools" | Out-Null

    Say "Building for $model $version"
    $stock = Join-Path $work 'stock.fwz'
    if ($Firmware) { Copy-Item $Firmware $stock -Force; Step "using $Firmware" }
    elseif (Test-Path $stock) { Step 'already downloaded' }
    else {
        $versions = Get-Content (Join-Path $Root 'firmware\steps\firmware-versions.sh') -Raw
        $m = [regex]::Match($versions, [regex]::Escape("${model}:${version}") + '\)\s*echo\s*"([^"]+)"')
        if (-not $m.Success) { Die "no download known for $model $version. Fetch it and pass it with -Firmware." }
        Step 'downloading (about 100 MB)'
        try { (New-Object Net.WebClient).DownloadFile($m.Groups[1].Value, $stock) }
        catch { Die "the download failed. Fetch the file yourself and pass it with -Firmware." }
    }

    $mm = [regex]::Match((Get-Content (Join-Path $Root 'firmware\steps\firmware-versions.sh') -Raw),
                         [regex]::Escape("${model}:${version}") + '\)\s*echo\s*"([0-9a-f]{32})"')
    if ($mm.Success) {
        $got = (Get-FileHash $stock -Algorithm MD5).Hash.ToLower()
        if ($got -ne $mm.Groups[1].Value) {
            Die "the firmware is not the one expected.`n      expected $($mm.Groups[1].Value)`n      got      $got`nEither it changed at the source, or the download was damaged."
        }
        Step "checksum $got"
    }

    $fwz = Get-Fwz
    Assert-FwzRuns $fwz
    $hash = & $fwz passwd root $rootPass
    if (-not $hash) { Die 'fwz could not make the password hash' }

    Say 'Gathering what goes inside'
    $payload = Join-Path $work 'payload'
    Build-Payload $payload $fwz

    $ops = Join-Path $work 'changes.txt'
    Write-Ops $payload (Join-Path $Root 'firmware\overlay') $sshKey $hash $ops
    Step "$((Get-Content $ops | Where-Object { $_ -notmatch '^#|^$' }).Count) changes to make"

    $out = Join-Path $work "$model-$version-local.fwz"
    & $fwz build --in $stock --out $out --model $model --changes $ops --work "$work\unpack"
    if ($LASTEXITCODE -ne 0) { Die 'the firmware could not be built' }

    Say 'Done'
    Step $out
    Write-Host ''
    Write-Host 'Flash it with MyHomeSuite, which is Bticino''s own tool.'
}

Main
