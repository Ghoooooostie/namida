$enc = [System.Text.Encoding]::UTF8
$baseDir = "d:/My_Project/namida"
$log = Get-Content -Encoding utf8 "$baseDir/analyze_log.txt"

$errs = $log | Where-Object { $_ -match "(getter|method|setter) '(\w+)' isn't defined for the type '(\w+)'" } | ForEach-Object {
  if ($_ -match "(getter|method|setter) '(\w+)' isn't defined for the type '(\w+)'") {
    [PSCustomObject]@{kind=$Matches[1]; member=$Matches[2]; type=$Matches[3]}
  }
}

$youtubeClasses = @('YoutubeID','QueueChipHeaderRow','YoutubeInfoController','YoutubeHistoryController','YoutubeController','YoutubePlaylistController','YoutubeSubscriptionsController','YoutubeAccountController','YoutubeImportController','YoutubeLocalSearchController','YtGeneratorsController','YoutubeMiniplayerUiController','SponsorBlockController','YtVideoLikeManager','NamidaYTGenerator','YTUtils','ReturnYoutubeDislikeSettings','SponsorBlockSettings','YoutubeSearchResultsPageState','YTHostedPlaylistSubpage','SeekReadyWidget','DownloadTaskFilename','YoutubeSubscription','VideoPlayerInfo','PlaylistRemoteSource','YoutubePlaylist','YoutubeSettings','PlayerConfigModificationScale','SeekReadyDimensions','YTMarkVideoWatchedResult')
$youtipieClasses = @('YoutiPie','StreamInfoItem','VideoStream','AudioStream','Caption','PlaylistBasicInfo','SearchFilters','ExecuteDetails','ResultWrapper','PlaylistResultBase','VideoStreamInfo','EndscreenItemBase','YTUrlUtils','YTLocalSearchController','ReturnYoutubeDislike','VideoEndScreenItem')
$namicoClasses = @('NamicoSubscriptionManager')

$keywords = @('assert','break','case','catch','class','const','continue','default','do','else','enum','extends','false','final','finally','for','if','in','is','new','null','rethrow','return','super','switch','this','throw','true','try','var','void','while','with','async','await','sync','yield','dynamic','typedef','abstract','external','factory','get','set','operator','static','late','required','covariant','hide','show','as','on','of','import','export','library','part','mixin')

$callLines = Get-ChildItem -Path "$baseDir/lib" -Recurse -Filter *.dart | Select-String -Pattern '\.\w+\(' -Encoding utf8

function Get-Named($member) {
  $lines = $callLines | Where-Object { $_.Line -match "\.$member\(" }
  $named = @{}
  foreach ($ln in $lines) {
    $line = $ln.Line
    if ($line -match "\.$member\(([^)]*)\)") {
      $args = $Matches[1]
      $n = [regex]::Matches($args, '(\w+)\s*:') | ForEach-Object { $_.Groups[1].Value }
      foreach ($x in $n) {
        if ($x -match '^[_a-zA-Z]\w*$' -and $keywords -notcontains $x) { $named[$x] = $true }
      }
    }
  }
  return ($named.Keys | ForEach-Object { "dynamic $_" }) -join ', '
}

function Class-Of($t) {
  if ($youtubeClasses -contains $t) { return 'youtube' }
  if ($youtipieClasses -contains $t) { return 'youtipie' }
  if ($namicoClasses -contains $t) { return 'namico' }
  return $null
}

# ---------------- persistent store (survives across runs) ----------------
# Persistence is achieved by SEEDING from the injected AUTO blocks already
# present in the stub files (the files themselves are the store), then merging
# the members the analyzer currently reports as undefined. isStatic records
# whether a member must be declared static (class access) or instance
# (instance access); it is driven by the static/instance access errors.
$store = @{}

# Seed the store from members already injected in the stub files, so that
# work done in prior runs (and style fixes like instance <-> static) is never
# lost when a member stops appearing in the log as 'undefined_*'.
function Seed-FromFile($relPath) {
  $full = "$baseDir/$relPath"
  if (-not (Test-Path $full)) { return }
  $lines = [System.IO.File]::ReadAllLines($full, $enc)
  $curClass = $null; $inBlock = $false
  foreach ($ln in $lines) {
    if ($ln -match '^\s*class (\w+)') { $curClass = $Matches[1]; $inBlock = $false }
    elseif ($ln -match '// === AUTO CLASS START ===') { $inBlock = $true }
    elseif ($ln -match '// === AUTO CLASS END ===') { $inBlock = $false }
    elseif ($inBlock) {
      $kind = $null; $mem = $null; $isStatic = $false
      if ($ln -match 'static dynamic get (\w+)') { $kind = 'getter'; $mem = $Matches[1]; $isStatic = $true }
      elseif ($ln -match 'dynamic get (\w+)') { $kind = 'getter'; $mem = $Matches[1] }
      elseif ($ln -match 'static set (\w+)\(') { $kind = 'setter'; $mem = $Matches[1]; $isStatic = $true }
      elseif ($ln -match 'set (\w+)\(') { $kind = 'setter'; $mem = $Matches[1] }
      elseif ($ln -match 'static dynamic (\w+)\(') { $kind = 'method'; $mem = $Matches[1]; $isStatic = $true }
      elseif ($ln -match 'dynamic (\w+)\(') { $kind = 'method'; $mem = $Matches[1] }
      if ($null -ne $kind -and $null -ne $curClass) {
        if (-not $store.ContainsKey($curClass)) { $store[$curClass] = @() }
        $exists = $false
        foreach ($m in $store[$curClass]) { if ($m.member -eq $mem) { $exists = $true; break } }
        if (-not $exists) { $store[$curClass] += @{ kind = $kind; member = $mem; isStatic = $isStatic } }
      }
    }
  }
}
Seed-FromFile "lib/youtube/_stubs_base.dart"
Seed-FromFile "external/shims/youtipie/lib/_stubs_base.dart"
Seed-FromFile "external/shims/namico_subscription_manager/lib/_stubs_base.dart"

# merge members reported as undefined in the current log into the persistent store
# (default: static, because these YouTube/youtipie/namico types are mostly
# singletons accessed via the class name; instance_access errors flip them back).
foreach ($e in $errs) {
  $set = Class-Of $e.type
  if ($null -eq $set) { continue }
  if ($e.member -eq 'import') { continue }
  if (-not $store.ContainsKey($e.type)) { $store[$e.type] = @() }
  $exists = $false
  foreach ($m in $store[$e.type]) { if ($m.member -eq $e.member) { $exists = $true; break } }
  if (-not $exists) { $store[$e.type] += @{ kind = $e.kind; member = $e.member; isStatic = $true } }
}

# Reverse-driven style fixes:
#  instance_access_to_static_member : member is STATIC but accessed via an
#    instance -> it must actually be an INSTANCE member. Flip isStatic -> false.
#  static_access_to_instance_member : member is INSTANCE but accessed via the
#    class -> it must be STATIC. Flip isStatic -> true.
foreach ($l in $log) {
  if ($l -match "static (?:getter|method|setter) '(\w+)' can't be accessed through an instance. Try using the class '(\w+)'") {
    $mem = $Matches[1]; $cls = $Matches[2]
    if ($store.ContainsKey($cls)) {
      foreach ($m in $store[$cls]) { if ($m.member -eq $mem) { $m.isStatic = $false } }
    }
  }
  if ($l -match "Instance member '(\w+)' can't be accessed using static access") {
    # no class name in the message; apply globally to any class that has the member
    $mem = $Matches[1]
    foreach ($cls in $store.Keys) {
      foreach ($m in $store[$cls]) { if ($m.member -eq $mem) { $m.isStatic = $true } }
    }
  }
}

function Inject-Class($content, $className, $members) {
  $idx = $content.IndexOf("class $className")
  if ($idx -lt 0) { return $content }
  $b = $content.IndexOf('{', $idx)
  if ($b -lt 0) { return $content }
  $depth = 0; $end = -1
  for ($i = $b; $i -lt $content.Length; $i++) {
    $c = $content[$i]
    if ($c -eq '{') { $depth++ }
    elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
  }
  if ($end -lt 0) { return $content }
  # members already declared in the class body (avoid duplicates within one class)
  $present = @{}
  $body = $content.Substring($b + 1, $end - $b - 1)
  foreach ($ln in ($body -split "`n")) {
    if ($ln -match '(?:static )?dynamic get (\w+)') { $present[$Matches[1]] = $true }
    elseif ($ln -match '(?:static )?set (\w+)\(') { $present[$Matches[1]] = $true }
    elseif ($ln -match '(?:static )?dynamic (\w+)\(') { $present[$Matches[1]] = $true }
  }
  $out = @()
  foreach ($mm in $members) {
    if ($present.ContainsKey($mm.member)) { continue }
    $present[$mm.member] = $true
    $p = if ($mm.isStatic) { "static " } else { "" }
    if ($mm.kind -eq 'getter') { $out += "  $p dynamic get $($mm.member) => null;" }
    elseif ($mm.kind -eq 'setter') { $out += "  $p set $($mm.member)(dynamic v) {}" }
    else {
      # Optional positional only (up to 8 slots). Dart forbids mixing optional
      # positional [...] with named {...} in one signature, so named args at
      # call sites are trimmed in later rounds if they surface as errors.
      $sig = "[dynamic a0, dynamic a1, dynamic a2, dynamic a3, dynamic a4, dynamic a5, dynamic a6, dynamic a7]"
      $out += "  $p dynamic $($mm.member)($sig) => null;"
    }
  }
  if ($out.Count -eq 0) { return $content }
  $insert = "`n  // === AUTO CLASS START ===`n" + ($out -join "`n") + "`n  // === AUTO CLASS END ===`n"
  return $content.Insert($end, $insert)
}

function Write-Stub($relPath, $setName, $store) {
  $full = "$baseDir/$relPath"
  $content = [System.IO.File]::ReadAllText($full, $enc)
  # strip ALL old auto blocks (single-line-aware) before re-injecting everything
  $content = [regex]::Replace($content, '// === AUTO[\s\S]*?END ===\r?\n', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  $injected = 0
  foreach ($className in $store.Keys) {
    if ((Class-Of $className) -ne $setName) { continue }
    $before = $content.Length
    $content = Inject-Class $content $className $store[$className]
    if ($content.Length -ne $before) { $injected++ }
  }
  Write-Host "  -> $relPath : $injected classes updated"
  [System.IO.File]::WriteAllText($full, $content, $enc)
}

Write-Stub "lib/youtube/_stubs_base.dart" 'youtube' $store
Write-Stub "external/shims/youtipie/lib/_stubs_base.dart" 'youtipie' $store
Write-Stub "external/shims/namico_subscription_manager/lib/_stubs_base.dart" 'namico' $store

$total = 0
foreach ($k in $store.Keys) { $total += $store[$k].Count }
Write-Output "classes tracked: $($store.Count)  total members: $total"
