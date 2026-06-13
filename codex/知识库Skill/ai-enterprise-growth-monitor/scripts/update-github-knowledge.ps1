param(
    [string]$SkillRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [int]$SearchPerQuery = 8,
    [int]$CommitPerRepo = 8,
    [int]$ReleasePerRepo = 3,
    [string]$AutoPushRepoRoot = "D:\Code\ai-office-training",
    [switch]$SkipAutoPush
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

function Get-UseExplanation {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Query,
        [string[]]$Keywords
    )

    $text = "$Name $Description $Query".ToLowerInvariant()
    $function = "跟踪该项目的最新文档、示例、release 和 commit，判断是否能沉淀为可复用的 AI 办公/企业交付能力。"
    $impact = "用于补充本地 Codex Skill 的案例库、交付检查清单和项目方案素材。"

    if ($text -match "browser|web|网页|automation") {
        $function = "用于浏览器自动化、网页任务执行、表单操作、资料采集和端到端流程自动执行。"
        $impact = "可用于企业内部系统自动操作、获客资料收集、竞品调研、网页工作流机器人和短视频运营后台自动化。"
    }
    elseif ($text -match "crew|autogen|agent|agents|multi-agent") {
        $function = "用于构建多智能体协作流程，让不同角色的 AI 分工完成研究、执行、复核和交付。"
        $impact = "可沉淀为企业 AI 项目的交付流水线，例如需求分析、方案生成、自动质检、客户交付材料生成。"
    }
    elseif ($text -match "rag|llama|index|document|ocr|retrieval") {
        $function = "用于文档知识库、RAG 检索、OCR、企业资料问答和知识型应用搭建。"
        $impact = "适合做企业私有知识库、培训资料问答、合同/制度/产品手册检索和 AI 办公助理。"
    }
    elseif ($text -match "memory|mem0|记忆") {
        $function = "用于给 AI agent 增加长期记忆、用户偏好记忆和跨会话上下文管理。"
        $impact = "可提升企业助手、销售助手、运营助手的连续服务能力，让系统记住客户背景和项目历史。"
    }
    elseif ($text -match "mcp|server|tool") {
        $function = "用于扩展 AI 工具调用能力，把外部系统、API、文件、数据库或工作台连接给 Codex/agent 使用。"
        $impact = "可作为企业 AI 落地的集成层，把 CRM、知识库、自动化脚本和内部服务接入 AI 工作流。"
    }
    elseif ($text -match "cookbook|example|beginner|training|lesson") {
        $function = "用于学习最新 AI 应用范式、代码样例、最佳实践和教学型项目结构。"
        $impact = "可转化为 AI 办公培训课程、交付模板、演示案例和团队内部 SOP。"
    }
    elseif ($text -match "video|creator|content|short") {
        $function = "用于短视频内容生产、素材处理、脚本生成、发布流程或创作者运营自动化。"
        $impact = "可补充短视频运营 Skill，形成选题、脚本、批量生产、数据复盘和矩阵号运营方法。"
    }
    elseif ($text -match "sales|lead|growth|outbound|customer|acquisition") {
        $function = "用于销售线索发现、获客自动化、外呼/外联流程、增长实验和漏斗优化。"
        $impact = "可补充获客 Skill，形成从线索采集、触达话术、跟进节奏到成交转化的自动化 SOP。"
    }

    if ($Keywords -and (Get-KeywordScore "$Name $Description $Query" $Keywords) -ge 3) {
        $impact = "$impact 优先级较高，建议人工复核后加入可执行交付清单。"
    }

    [pscustomobject]@{
        function = $function
        impact = $impact
    }
}

function Sync-ToGitHubRepo {
    param(
        [string]$SourceSkillRoot,
        [string]$RepoRoot,
        [string]$Today
    )

    if (-not (Test-Path $RepoRoot)) {
        Write-Log "Auto push skipped: repo root not found: $RepoRoot"
        return
    }

    $gitDir = Join-Path $RepoRoot ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Log "Auto push skipped: not a git repository: $RepoRoot"
        return
    }

    $repoStatus = (& git -C $RepoRoot status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Auto push skipped: git status failed in $RepoRoot"
        return
    }
    if ($repoStatus) {
        Write-Log "Auto push skipped: target repository has existing local changes."
        return
    }

    & git -C $RepoRoot pull --ff-only origin main | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Auto push skipped: git pull --ff-only failed."
        return
    }

    $targetSkillRoot = Join-Path $RepoRoot "codex\知识库Skill\ai-enterprise-growth-monitor"
    New-Item -ItemType Directory -Force -Path $targetSkillRoot | Out-Null

    foreach ($name in @("SKILL.md", "agents", "knowledge", "references", "scripts")) {
        $source = Join-Path $SourceSkillRoot $name
        $target = Join-Path $targetSkillRoot $name
        if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
    }

    & git -C $RepoRoot add "README.md" ".gitignore" "codex/知识库Skill/ai-enterprise-growth-monitor/SKILL.md" "codex/知识库Skill/ai-enterprise-growth-monitor/agents/openai.yaml" "codex/知识库Skill/ai-enterprise-growth-monitor/knowledge" "codex/知识库Skill/ai-enterprise-growth-monitor/references" "codex/知识库Skill/ai-enterprise-growth-monitor/scripts/update-github-knowledge.ps1"
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Auto push skipped: git add failed."
        return
    }

    $staged = (& git -C $RepoRoot diff --cached --name-only)
    if (-not $staged) {
        Write-Log "Auto push: no GitHub changes to commit."
        return
    }

    $userName = (& git -C $RepoRoot config user.name)
    if (-not $userName) { & git -C $RepoRoot config user.name "Codex Automation" | Out-Null }
    $userEmail = (& git -C $RepoRoot config user.email)
    if (-not $userEmail) { & git -C $RepoRoot config user.email "codex@local" | Out-Null }

    & git -C $RepoRoot commit -m "Update Codex AI knowledge digest $Today" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Auto push skipped: git commit failed."
        return
    }

    & git -C $RepoRoot push origin main | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Auto push failed: git push failed."
        return
    }

    Write-Log "Auto push completed for $RepoRoot."
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
        $explanation = Get-UseExplanation $repo $repoInfo.description "" $priorityKeywords

        $repoFindings.Add([pscustomobject]@{
            repo = $repo
            url = $repoInfo.html_url
            description = $repoInfo.description
            pushed_at = $repoInfo.pushed_at
            stars = $repoInfo.stargazers_count
            keyword_score = Get-KeywordScore $summaryText $priorityKeywords
            use_function = $explanation.function
            use_impact = $explanation.impact
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
            $explanation = Get-UseExplanation $item.full_name $item.description $query $priorityKeywords
            $searchFindings.Add([pscustomobject]@{
                query = $query
                repo = $item.full_name
                url = $item.html_url
                description = $item.description
                pushed_at = $item.pushed_at
                stars = $item.stargazers_count
                keyword_score = Get-KeywordScore $text $priorityKeywords
                use_function = $explanation.function
                use_impact = $explanation.impact
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
    $lines.Add("- 使用功能: $($item.use_function)")
    $lines.Add("- 作用: $($item.use_impact)")
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
    $lines.Add("  - 使用功能: $($item.use_function)")
    $lines.Add("  - 作用: $($item.use_impact)")
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
if (-not $SkipAutoPush) {
    Sync-ToGitHubRepo -SourceSkillRoot $SkillRoot -RepoRoot $AutoPushRepoRoot -Today $today
}
Write-Output $digestPath

