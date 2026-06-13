param(
    [string]$SkillRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [int]$SearchPerQuery = 8,
    [int]$CommitPerRepo = 8,
    [int]$ReleasePerRepo = 3
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $script:LogPath -Value "[$stamp] $Message" -Encoding UTF8
}

function Invoke-GitHubApi {
    param([string]$Uri)
    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "codex-ai-enterprise-growth-monitor"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $token = $env:GITHUB_TOKEN
    if (-not $token) { $token = $env:GH_TOKEN }
    if ($token) { $headers["Authorization"] = "Bearer $token" }
    Invoke-RestMethod -Uri $Uri -Headers $headers -Method Get
}

function Get-KeywordScore {
    param(
        [string]$Text,
        [string[]]$Keywords
    )
    if (-not $Text) { return 0 }
    $score = 0
    foreach ($keyword in $Keywords) {
        if ($Text -match [regex]::Escape($keyword)) { $score++ }
    }
    return $score
}

function ConvertTo-SafeFileName {
    param([string]$Name)
    return ($Name -replace "[^a-zA-Z0-9._-]", "_")
}

$ReferencesDir = Join-Path $SkillRoot "references"
$KnowledgeDir = Join-Path $SkillRoot "knowledge"
$RawDir = Join-Path $SkillRoot "raw"
$LogsDir = Join-Path $SkillRoot "logs"
New-Item -ItemType Directory -Force -Path $ReferencesDir, $KnowledgeDir, $RawDir, $LogsDir | Out-Null

$script:LogPath = Join-Path $LogsDir "update.log"
$WatchlistPath = Join-Path $ReferencesDir "watchlist.json"
$LatestDigestPath = Join-Path $ReferencesDir "latest-digest.md"
$IndexPath = Join-Path $KnowledgeDir "index.md"

$today = Get-Date -Format "yyyy-MM-dd"
$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$sinceDate = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")
$digestPath = Join-Path $KnowledgeDir "$today-github-ai-knowledge.md"
$rawRunDir = Join-Path $RawDir $runStamp
New-Item -ItemType Directory -Force -Path $rawRunDir | Out-Null

Write-Log "Starting GitHub knowledge update."

if (-not (Test-Path $WatchlistPath)) {
    throw "Missing watchlist: $WatchlistPath"
}

$watchlist = Get-Content -Raw -Path $WatchlistPath -Encoding UTF8 | ConvertFrom-Json
$priorityKeywords = @($watchlist.priority_keywords)

$repoFindings = New-Object System.Collections.Generic.List[object]
$searchFindings = New-Object System.Collections.Generic.List[object]

foreach ($repo in @($watchlist.repositories)) {
    try {
        $repoSafe = ConvertTo-SafeFileName $repo
        $repoInfo = Invoke-GitHubApi "https://api.github.com/repos/$repo"
        $repoInfo | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $rawRunDir "$repoSafe-repo.json") -Encoding UTF8

        $releases = Invoke-GitHubApi "https://api.github.com/repos/$repo/releases?per_page=$ReleasePerRepo"
        $releases | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $rawRunDir "$repoSafe-releases.json") -Encoding UTF8

        $commits = Invoke-GitHubApi "https://api.github.com/repos/$repo/commits?since=$sinceDate`T00:00:00Z&per_page=$CommitPerRepo"
        $commits | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $rawRunDir "$repoSafe-commits.json") -Encoding UTF8

        $summaryText = @(
            $repoInfo.description,
            ($releases | ForEach-Object { $_.name; $_.body }) -join " ",
            ($commits | ForEach-Object { $_.commit.message }) -join " "
        ) -join " "

        $repoFindings.Add([pscustomobject]@{
            repo = $repo
            url = $repoInfo.html_url
            description = $repoInfo.description
            pushed_at = $repoInfo.pushed_at
            stars = $repoInfo.stargazers_count
            keyword_score = Get-KeywordScore $summaryText $priorityKeywords
            releases = @($releases | Select-Object -First $ReleasePerRepo | ForEach-Object {
                [pscustomobject]@{ name = $_.name; tag = $_.tag_name; url = $_.html_url; published_at = $_.published_at }
            })
            commits = @($commits | Select-Object -First $CommitPerRepo | ForEach-Object {
                [pscustomobject]@{ message = $_.commit.message; url = $_.html_url; date = $_.commit.author.date }
            })
        })
    }
    catch {
        Write-Log "Repo failed: $repo :: $($_.Exception.Message)"
    }
}

foreach ($query in @($watchlist.search_queries)) {
    try {
        $queryWithFreshness = "$query pushed:>=$sinceDate"
        $encoded = [System.Uri]::EscapeDataString($queryWithFreshness)
        $search = Invoke-GitHubApi "https://api.github.com/search/repositories?q=$encoded&sort=updated&order=desc&per_page=$SearchPerQuery"
        $safe = ConvertTo-SafeFileName $query
        $search | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $rawRunDir "$safe-search.json") -Encoding UTF8

        foreach ($item in @($search.items)) {
            $text = "$($item.full_name) $($item.description) $($item.topics -join ' ')"
            $searchFindings.Add([pscustomobject]@{
                query = $query
                repo = $item.full_name
                url = $item.html_url
                description = $item.description
                pushed_at = $item.pushed_at
                stars = $item.stargazers_count
                keyword_score = Get-KeywordScore $text $priorityKeywords
            })
        }
    }
    catch {
        Write-Log "Search failed: $query :: $($_.Exception.Message)"
    }
}

$topRepos = @($repoFindings | Sort-Object keyword_score, pushed_at -Descending)
$topSearch = @($searchFindings | Sort-Object keyword_score, stars -Descending | Select-Object -First 25)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# GitHub AI Knowledge Digest - $today")
$lines.Add("")
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$lines.Add("")
$lines.Add("## What This Run Monitored")
$lines.Add("")
$lines.Add("- Explicit repositories: $(@($watchlist.repositories).Count)")
$lines.Add("- Discovery searches: $(@($watchlist.search_queries).Count)")
$lines.Add("- Freshness window: repositories pushed since $sinceDate")
$lines.Add("")
$lines.Add("## Enterprise AI Delivery Signals")
$lines.Add("")
foreach ($item in $topRepos | Select-Object -First 10) {
    $lines.Add("### $($item.repo)")
    $lines.Add("")
    $lines.Add("- URL: $($item.url)")
    $lines.Add("- Stars: $($item.stars)")
    $lines.Add("- Last pushed: $($item.pushed_at)")
    $lines.Add("- Relevance score: $($item.keyword_score)")
    if ($item.description) { $lines.Add("- Description: $($item.description)") }
    if (@($item.releases).Count -gt 0) {
        $lines.Add("- Recent releases:")
        foreach ($release in @($item.releases)) {
            $lines.Add("  - $($release.name) / $($release.tag) / $($release.published_at): $($release.url)")
        }
    }
    if (@($item.commits).Count -gt 0) {
        $lines.Add("- Recent commits:")
        foreach ($commit in @($item.commits | Select-Object -First 5)) {
            $message = ($commit.message -split "`n")[0]
            $lines.Add("  - $($commit.date): $message")
        }
    }
    $lines.Add("")
}

$lines.Add("## Discovery Results")
$lines.Add("")
foreach ($item in $topSearch) {
    $lines.Add("- [$($item.repo)]($($item.url)) | stars: $($item.stars) | score: $($item.keyword_score) | query: $($item.query)")
    if ($item.description) { $lines.Add("  - $($item.description)") }
}
$lines.Add("")
$lines.Add("## Delivery Implications To Review")
$lines.Add("")
$lines.Add("- Check whether new examples can become enterprise delivery SOPs, templates, or reusable demos.")
$lines.Add("- Convert agent/RAG/MCP updates into validation checklists before using them in client delivery.")
$lines.Add("- Watch for creator-growth and acquisition repos that include repeatable scripts, workflows, or measurable funnel tactics.")
$lines.Add("- Prefer project-ready artifacts: docs, examples, release notes, eval methods, integration patterns, and deployment guidance.")
$lines.Add("")
$lines.Add("## Next Manual Refinement")
$lines.Add("")
$lines.Add("- Add exact GitHub repos for short-video operations and customer acquisition if the current discovery results are too broad.")
$lines.Add("- Add private notes or preferred source lists to `references/watchlist.json`.")

$digest = $lines -join "`r`n"
$digest | Set-Content -Path $digestPath -Encoding UTF8
$digest | Set-Content -Path $LatestDigestPath -Encoding UTF8

if (-not (Test-Path $IndexPath)) {
    "# AI Enterprise Delivery and Growth Knowledge Index`r`n" | Set-Content -Path $IndexPath -Encoding UTF8
}

$existingIndex = Get-Content -Raw -Path $IndexPath -Encoding UTF8
$entry = "- ${today}: [GitHub AI Knowledge Digest](./$today-github-ai-knowledge.md)"
if ($existingIndex -notmatch [regex]::Escape($entry)) {
    Add-Content -Path $IndexPath -Value $entry -Encoding UTF8
}

Write-Log "Completed GitHub knowledge update. Digest: $digestPath"
Write-Output $digestPath
