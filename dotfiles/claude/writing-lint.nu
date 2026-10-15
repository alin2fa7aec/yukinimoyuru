#!/usr/bin/env nu

# Checks the writing-style skill rules that can be judged mechanically.
#
#   check  Check files and print violations as <path>:<line>: [<rule>] <message>. Exits with code 1 if there are any
#   hook   Called from the PostToolUse hook. If the range rewritten by Write or Edit has violations, send it back to Claude
#
# Checks the body of markdown documents and the source code comment lines that contain Japanese.
# Code blocks, inline code, URLs, and HTML comments are not checked.
# In markdown, anything between <!-- writing-lint: off --> and <!-- writing-lint: on --> is not checked either.
#
# Rules whose wording or judgment varies a lot (backticks on identifiers, whether to rephrase a symbol) are not handled.

const JA = '[\p{Han}\p{Hiragana}\p{Katakana}ー々]'

# Symbols replaced with ASCII under rule 1. Full-width ASCII (U+FF01-FF5E) is handled as a range, excluding only 「，」 and 「．」, which the punctuation rule checks.
const SYMBOLS = '[⇔↔→←⇒※—―–‐〜①-⑳\x{3000}\x{FF01}-\x{FF0B}\x{FF0D}\x{FF0F}-\x{FF5E}]'

# Counters, Latin units, and % that take no space after a number.
const COUNTERS = '本|個|回|件|台|枚|つ|人|秒|分|時間|時|日|か月|月|年|倍|度|割|番|行|列|桁|文字|ページ|箇所|段階|種類'
const UNITS = 'mm|cm|km|m|px|pt|em|rem|dB|Hz|kHz|MHz|GHz|ms|us|ns|s|sec|min|byte|bytes|KB|MB|GB|TB|KiB|MiB|GiB|bit|bits|ch|fps|bpm|dpi|%'

# Latin abbreviations that attach to Japanese as a suffix to form one word (the G in 「ソフトG」). Add new ones here when you use them.
const ABBREV_SUFFIXES = 'G'

# Katakana words whose trailing long vowel is often dropped. Not exhaustive.
const LONG_VOWEL = 'ユーザ|サーバ|エンコーダ|デコーダ|パラメータ|コンピュータ|フォルダ|ブラウザ|プリンタ|コントローラ|スキャナ|ドライバ|マネージャ|レイヤ|フィルタ|バッファ|コンパイラ|エディタ|ヘッダ|ポインタ|イテレータ|メンバ|モニタ|プロセッサ|コンバータ|アダプタ'

# A line ending with one of these is considered broken mid-sentence.
const MID_SENTENCE = '(、|,|[はがをにでとのもへや]|から|まで|より|ので|けど|ため|って)$'

# The start of a list item.
const LIST_MARKER = '^([-*+]|[0-9]+[.)])\s'

# Comment syntax per file extension.
const COMMENT_STYLES = {
  slash: [c cc cpp cxx h hh hpp hxx qml js mjs cjs ts tsx jsx rs go java kt swift cs css scss]
  hash: [py sh bash nu toml yaml yml ps1 rb pl cmake conf]
  dash: [lua]
  semicolon: [ahk kbd]
}

# Show how to use writing-lint.nu.
def main [] {
  help main
}

# Check files. Without files, check stdin as text.
def "main check" [
  ...files: path
  --as: string # Kind of check (md, code, text). Determined by the extension when omitted
] {
  let stdin = $in
  let found = if ($files | is-empty) {
    if $stdin == null {
      error make {msg: "Specify files to check or pass text on stdin"}
    }
    lint-text $stdin ($as | default text) "" | insert path "<stdin>"
  } else {
    $files | each {|f|
      let mode = $as | default (mode-of $f | default text)
      lint-text (open --raw $f) $mode ($f | path parse | get extension) | insert path $f
    } | flatten
  }
  for f in $found {
    print $"($f.path):($f.line): [($f.rule)] ($f.message)"
  }
  if ($found | is-not-empty) {
    exit 1
  }
}

# Take the PostToolUse hook input on stdin and return violations in the rewritten range to Claude.
def "main hook" [] {
  let input = $in | from json
  let file = $input.tool_input.file_path? | default ""
  let mode = mode-of $file
  if $mode == null or not ($file | path exists) {
    return
  }
  let content = open --raw $file
  let ranges = changed-ranges $input.tool_name $input.tool_input $content
  if ($ranges | is-empty) {
    return
  }
  # linebreak and line-end findings are attached to the first of two adjacent lines, so include one line before the range.
  let found = lint-text $content $mode ($file | path parse | get extension)
  | where {|f| $ranges | any {|r| $f.line >= ($r.first - 1) and $f.line <= $r.last } }
  if ($found | is-empty) {
    return
  }
  let report = $found | each {|f| $"($f.line): [($f.rule)] ($f.message)" } | str join "\n"
  {
    decision: block
    reason: $"Some text does not follow the writing-style rules \(($file)\). Fix it, or leave it as is with a reason if it is intended. If unsure how to fix it, read the section named after the rule in reference.md of the writing-style skill \(synced from claude.ai under ~/.claude/skills/synced/\).\n($report)"
  }
  | to json --raw
  | print
}

# Determine the kind of check from the extension. Returns null for unhandled extensions.
def mode-of [file: string]: nothing -> any {
  let ext = $file | path parse | get extension | str downcase
  if $ext in [md markdown] {
    "md"
  } else if ($COMMENT_STYLES | values | flatten | any {|e| $e == $ext }) {
    "code"
  } else {
    null
  }
}

# Return the list of line ranges {first, last} rewritten in the hook.
# If the Edit's new_string appears more than once in the file, all occurrences are ranges. Deletion-only Edits are not checked.
def changed-ranges [tool: string, input: record, content: string]: nothing -> list {
  let all = [{first: 1, last: ($content | lines | length)}]
  if $tool == "Write" {
    return $all
  }
  if $tool != "Edit" {
    return []
  }
  let new = $input.new_string? | default ""
  if ($new | is-empty) {
    return []
  }
  let parts = $content | split row $new
  if ($parts | length) < 2 {
    return $all
  }
  let height = $new | newline-count
  $parts
  | drop 1
  | reduce --fold {start: 1, ranges: []} {|part, acc|
    let first = $acc.start + ($part | newline-count)
    {start: ($first + $height), ranges: ($acc.ranges | append {first: $first, last: ($first + $height)})}
  }
  | get ranges
}

def newline-count []: string -> int {
  ($in | split row "\n" | length) - 1
}

# Check the text and return the list of violations {line, rule, message}.
def lint-text [content: string, mode: string, ext: string]: nothing -> table {
  let records = match $mode {
    "md" => (md-records $content)
    "code" => (comment-records $content (comment-style $ext))
    "text" => (text-records $content)
    _ => (error make {msg: $"unknown mode: ($mode)"})
  }
  [
    ($records | each {|r| inline-findings $r } | flatten)
    (wrap-findings $records $mode)
    (if $mode == "md" { bold-findings $records } else { [] })
  ]
  | flatten
  | sort-by line
}

def comment-style [ext: string]: nothing -> string {
  let e = $ext | str downcase
  let style = $COMMENT_STYLES | transpose style exts | where {|s| $e in $s.exts } | get --optional 0.style
  if $style == null {
    error make {msg: $"unknown comment syntax for extension: ($ext)"}
  }
  $style
}

# Turn markdown lines into a list of lines to check {line, raw, kind, text}.
# kind is one of heading, table, list, prose. text is the body with inline code and the like removed.
# Indented code blocks (lines starting with four spaces or a tab after a blank line) are also dropped. This drops continuation paragraphs of lists too, erring on the side of missing checks.
def md-records [content: string]: nothing -> table {
  mut fence = ""
  mut front = false
  mut off = false
  mut comment = false
  mut icode = false
  mut blank = true
  mut out = []
  for row in ($content | lines | enumerate) {
    let n = $row.index + 1
    let t = $row.item | str trim
    let was_blank = $blank
    $blank = ($t | is-empty)
    if $n == 1 and $t == "---" {
      $front = true
      continue
    }
    if $front {
      if $t in ["---" "..."] { $front = false }
      continue
    }
    if $fence != "" {
      if ($t | str starts-with $fence) { $fence = "" }
      continue
    }
    let open_fence = $t | parse -r '^(`{3,}|~{3,})'
    if ($open_fence | is-not-empty) {
      $fence = $open_fence.0.capture0
      continue
    }
    if $comment {
      if ($t | str contains "-->") { $comment = false }
      continue
    }
    if $t =~ '^<!--\s*writing-lint:\s*off\s*-->' {
      $off = true
      continue
    }
    if $t =~ '^<!--\s*writing-lint:\s*on\s*-->' {
      $off = false
      continue
    }
    if ($t | str starts-with "<!--") and not ($t | str contains "-->") {
      $comment = true
      continue
    }
    if ($t | is-empty) {
      continue
    }
    if ($row.item =~ '^( {4}|\t)') and ($was_blank or $icode) and not ($t =~ $LIST_MARKER) {
      $icode = true
      continue
    }
    $icode = false
    if $off or ($t | str starts-with "<") {
      continue
    }
    let body = $t | str replace -r '^(>\s?)+' ''
    let kind = if ($body | str starts-with "#") {
      "heading"
    } else if ($body | str starts-with "|") {
      "table"
    } else if $body =~ $LIST_MARKER {
      "list"
    } else {
      "prose"
    }
    $out = $out | append {line: $n, raw: $row.item, kind: $kind, text: ($body | strip-md)}
  }
  $out
}

# Exclude inline code, link targets, and URLs from checks. Also remove bold markers so the boundary with surrounding characters is visible.
def strip-md []: string -> string {
  $in
  | str replace -ra '`[^`]+`' '`code`'
  | str replace -ra '!?\[([^\]]*)\]\([^)]*\)' '$1'
  | str replace -ra '<?https?://[^\s>)]+>?' 'URL'
  | str replace -ra '\*\*|__' ''
}

# Turn source code comments into a list of lines to check {line, raw, kind, text}.
# Lines without Japanese are kept too, so the linebreak check can see how lines connect.
def comment-records [content: string, style: string]: nothing -> table {
  let patterns = match $style {
    "slash" => ['(?:^|[^:])//+[!<]?\s?(.*)$' '/\*+!?\s?(.*?)\s*(?:\*/|$)' '^\s*\*(?!/)\s?(.*?)\s*(?:\*/)?$']
    "hash" => ['(?:^|\s)#+\s?(.*)$']
    "dash" => ['--+\s?(.*)$']
    "semicolon" => [';+\s?(.*)$']
  }
  $content
  | lines
  | enumerate
  | each {|row|
    let text = $patterns
    | each {|p| $row.item | parse -r $p | get --optional 0.capture0 }
    | compact
    | get --optional 0
    if $text != null and ($text | str trim | is-not-empty) {
      {line: ($row.index + 1), raw: $row.item, kind: comment, text: ($text | str trim | strip-md)}
    }
  }
  | compact
}

# Treat every line as body text, as in commit messages.
def text-records [content: string]: nothing -> table {
  $content
  | lines
  | enumerate
  | where {|row| ($row.item | str trim | is-not-empty) and not ($row.item | str starts-with "#") }
  | each {|row|
    let t = $row.item | str trim
    let kind = if $t =~ $LIST_MARKER { "list" } else { "prose" }
    {line: ($row.index + 1), raw: $row.item, kind: $kind, text: ($t | strip-md)}
  }
}

# Check the rules that can be judged within one line (symbols, punctuation, long-vowel, spacing).
def inline-findings [r: record]: nothing -> list {
  let t = $r.text
  if not ($t =~ $JA) {
    return []
  }
  # Treat abbreviations in ABBREV_SUFFIXES as part of the Japanese.
  let spaced = $t | str replace -ra $"\(($JA)\)\(?:($ABBREV_SUFFIXES)\)\(?![A-Za-z0-9]\)" '${1}ア'
  # A single character in corner brackets, like 「，」, is considered a mention of the symbol itself.
  let quoted = $t | str replace -ra '「.」' '「」'
  [
    ($quoted | parse -r $"\(($SYMBOLS)\)" | get capture0 | uniq | each {|c|
      let shown = if $c == "　" { "full-width space" } else { $c }
      finding $r 記号 $"write it in ASCII: ($shown)"
    })
    ($quoted | parse -r '([，．])' | get capture0 | uniq | each {|c|
      finding $r 句読点 $"use 「、」 and 「。」: ($c)"
    })
    ($t | parse -r $"\(\(?<!\\p{Katakana}\)\(?:($LONG_VOWEL)\)\(?![ー\\p{Katakana}]\)\)" | get capture0 | uniq | each {|w|
      finding $r 長音 $"add the trailing long vowel: ($w) -> ($w)ー"
    })
    ($spaced | parse -r $"\(($JA)\(?:[0-9.]*[A-Za-z`]+|[0-9.]+%\)\)" | get capture0 | each {|s|
      finding $r スペース $"put a half-width space between Japanese and an English word: ($s)"
    })
    ($spaced | parse -r $"\(\(?:[A-Za-z`][0-9.]*|%\)($JA)\)" | get capture0 | each {|s|
      finding $r スペース $"put a half-width space between an English word and Japanese: ($s)"
    })
    ($t | parse -r $"\([0-9] \(?:($COUNTERS)\)\)" | get capture0 | each {|s|
      finding $r スペース $"no space between a number and its counter: ($s)"
    })
    ($t | parse -r $"\([0-9] \(?:($UNITS)\)\)\(?![A-Za-z]\)" | get capture0 | each {|s|
      finding $r スペース $"no space between a number and its unit: ($s)"
    })
  ]
  | flatten
}

# Check the linebreak rules. When two adjacent lines continue the same paragraph (comment), look at the first one.
# In markdown, a line break without two trailing spaces disappears when rendered, so flag it even if it is not mid-sentence.
def wrap-findings [records: table, mode: string]: nothing -> list {
  $records
  | window 2
  | where {|w|
    let a = $w.0
    let b = $w.1
    (
      $b.line == $a.line + 1
      and $a.kind in [prose list comment]
      and $b.kind in [prose comment]
      and (($a.text =~ $JA) or ($b.text =~ $JA))
      and not ($b.text =~ $LIST_MARKER)
    )
  }
  | each {|w|
    let a = $w.0
    let mid = $a.text | str trim | $in =~ $MID_SENTENCE
    if $mid {
      finding $a 改行 "line broken mid-sentence. Write one sentence per line"
    } else if $mode == "md" and not ($a.raw | str ends-with "  ") and not ($a.raw | str ends-with "\\") {
      finding $a 行末 "to break the line, end it with two spaces"
    }
  }
  | compact
}

# Aim for 0-2 bold places per document. Beyond that, report every line with bold.
# Narrowed to the range in the hook, the finding remains only when a line with bold is edited.
def bold-findings [records: table]: nothing -> list {
  let bolds = $records
  | each {|r|
    let n = $r.raw | str replace -ra '`[^`]+`' '' | parse -r '(\*\*[^*]+\*\*|__[^_]+__)' | length
    {r: $r, n: $n}
  }
  | where n > 0
  if ($bolds | is-empty) {
    return []
  }
  let total = $bolds | get n | math sum
  if $total <= 2 {
    return []
  }
  $bolds | each {|b|
    finding $b.r 太字 $"($total) bold places. Keep bold only where missing it would cause real harm \(aim for 0-2\)"
  }
}

def finding [r: record, rule: string, message: string]: nothing -> record {
  {line: $r.line, rule: $rule, message: $message}
}
