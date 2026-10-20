#!/usr/bin/env bash
# 寫到 tracker（issue、PR 描述、comment、thread 回覆）之前，掃文字裡有沒有 secret。
# 內容一律從 stdin 讀，不放進 argv（argv 會出現在 ps、shell history）。命中只報類別與筆數，不印原值。
#
# 用法：scan-secrets.sh check  < file   exit 0 = 乾淨；1 = 命中（stderr 列類別與筆數）；2 = 掃描失敗
#       scan-secrets.sh redact < file   stdout = 遮罩後全文（命中處換成 [REDACTED:<類別>]，前綴如 `Authorization: Bearer ` 保留）；
#                                       stderr 同 check；exit 0，失敗 2
# 偵測的是「長得像 secret 的字串」，不是完整的 DLP：專案特有的個資格式（身分證、帳號…）要在專案版本補規則。
set -u
mode=${1:-}
case "$mode" in check|redact) ;; *) echo "用法：scan-secrets.sh check|redact < file" >&2; exit 2 ;; esac
command -v perl >/dev/null 2>&1 || { echo "scan-secrets：找不到 perl，無法掃描" >&2; exit 2; }

MODE=$mode perl -e '
use strict; use warnings;
binmode STDIN; binmode STDOUT;
local $/; my $t = <STDIN>; $t = "" unless defined $t;

# 值是變數參照、佔位符或已遮罩 → 不算 secret（文件裡寫 `Bearer $TOKEN`、`password: <your-password>` 很常見）
sub safe {
  my $v = shift;
  return 1 if $v =~ /^(?:\[REDACTED:|\$|<|\{\{|%[A-Za-z_])/;
  return 1 if $v =~ /^(?:\*+|x+|\.+|…+)$/i;
  return 1 if $v =~ /^(?:true|false|null|none|nil|undefined|required|optional|string|example|redacted|changeme|your[_-]?\w*)$/i;
  return 0;
}

# 每條規則：(前綴)(值)；只遮罩值。順序由具體到一般，後面的規則看到的是已遮罩的文字
my $V = q#(?:(?![\s"\x27\x60,;\]\x7d])[\x21-\x7e])#;   # 值字元：可見 ASCII，遇空白、引號、逗號、全形字元就停
my @rules = (
  [private_key       => qr/()(-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|\z))/],
  [github_token      => qr/()\b((?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,}))/],
  [gitlab_token      => qr/()\b((?:glpat|gldt|glrt|glcbt|glptt|glft|glimt|glagent|glsoat|gloas)-[A-Za-z0-9_-]{20,})/],
  [aws_access_key    => qr/()\b((?:AKIA|ASIA)[0-9A-Z]{16})\b/],
  [slack_token       => qr/()\b(xox[abposr]-[A-Za-z0-9-]{10,})/],
  [api_key           => qr/()\b((?:sk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}))/],
  [jwt               => qr/()\b(eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,})/],
  [url_credential    => qr{(\b[a-z][a-z0-9+.-]*://[^\s:/@]+:)([^\s@/]+)(?=@)}i],
  [auth_header       => qr/((?i:proxy-authorization|authorization)["\x27]?\s*[:=]\s*["\x27]?(?i:bearer|basic|token|digest)\s+)((?:${V}){8,})/],
  [bearer            => qr/(\b(?i:bearer)\s+)([A-Za-z0-9._~+\/-]{16,}=*)/],
  [secret_assignment => qr/((?i:\b[A-Za-z0-9_.-]*(?:password|passwd|pwd|secret|token|api[_-]?key|apikey|access[_-]?key|private[_-]?key|client[_-]?secret))["\x27]?\s*[:=]\s*["\x27]?)((?:${V}){4,})/],
);

my (%n, @order);
for my $r (@rules) {
  my ($kind, $re) = @$r;
  $t =~ s{$re}{
    my ($p, $v) = ($1, $2);
    if (safe($v)) { $p . $v }
    else { push @order, $kind unless $n{$kind}++; $p . "[REDACTED:$kind]" }
  }ge;
}

if (@order) {
  print STDERR "scan-secrets：命中 " . join("、", map { "$_ ×$n{$_}" } @order) . "\n";
}
print $t if $ENV{MODE} eq "redact";
exit(($ENV{MODE} eq "check" && @order) ? 1 : 0);
'
rc=$?
case "$rc" in 0|1) exit "$rc" ;; *) echo "scan-secrets：掃描失敗（perl exit ${rc}）" >&2; exit 2 ;; esac
