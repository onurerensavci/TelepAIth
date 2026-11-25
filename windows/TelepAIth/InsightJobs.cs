using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using TelepAIth.Core;

namespace TelepAIth;

/// <summary>
/// Uyarıların arka plan işleri (Mac'te InsightJobs.swift): push'tan sonra o commit'in CI'sini gh ile izler,
/// tur bitince commit'lenmemiş değişikliğe git ile bakar. gh/git yoksa sessizce vazgeçer.
/// </summary>
internal static class InsightJobs
{
    public static void Run(Insights.Job job, Insights insights, Action<AgentEvent> say)
    {
        Task.Run(async () =>
        {
            try
            {
                if (job.Kind == "ci") await WatchCi(job, say);
                else if (job.Kind == "commit") CheckCommit(job, insights, say);
            }
            catch { /* uyarı işleri robotu asla bozmamalı */ }
        });
    }

    private static async Task WatchCi(Insights.Job job, Action<AgentEvent> say)
    {
        var sha = Exec("git", job.Dir, "rev-parse", "HEAD")?.Trim();
        if (string.IsNullOrEmpty(sha) || sha.Length < 7) return;
        var started = DateTime.Now;
        await Task.Delay(TimeSpan.FromSeconds(20));
        while (DateTime.Now - started < TimeSpan.FromMinutes(45))
        {
            var json = Exec("gh", job.Dir, "run", "list", "--commit", sha, "--json", "status,conclusion,name,url,workflowName", "-L", "30");
            if (json == null) return;   // gh yok ya da giriş yapılmamış
            var r = CiStatus.Summarize(json);
            if (r == null && DateTime.Now - started > TimeSpan.FromMinutes(3)) return;   // bu depoda CI yok
            if (r is { Done: true })
            {
                say(Insights.CiEvent(job, r));
                return;
            }
            await Task.Delay(TimeSpan.FromSeconds(30));
        }
    }

    private static void CheckCommit(Insights.Job job, Insights insights, Action<AgentEvent> say)
    {
        var status = Exec("git", job.Dir, "status", "--porcelain");
        if (status == null) return;   // git deposu değil
        var last = Exec("git", job.Dir, "log", "-1", "--format=%ct")?.Trim();
        if (!long.TryParse(last, out var seconds)) return;
        var lastCommit = DateTimeOffset.FromUnixTimeSeconds(seconds).LocalDateTime;
        var now = DateTime.Now;
        bool tell;
        lock (insights.Nudge) tell = insights.Nudge.ShouldTell(job.Dir, status.Trim().Length > 0, lastCommit, now);
        if (tell) say(Insights.CommitEvent(job, lastCommit, now));
    }

    /// <summary>Komutu çalıştırır; başarısızsa (çıkış kodu ≠ 0, program yok, 20 sn'de bitmedi) null.</summary>
    private static string? Exec(string file, string dir, params string[] args)
    {
        if (!Directory.Exists(dir)) return null;
        var psi = new ProcessStartInfo(file)
        {
            WorkingDirectory = dir,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = new UTF8Encoding(false),
        };
        foreach (var a in args) psi.ArgumentList.Add(a);
        psi.Environment["GH_PROMPT_DISABLED"] = "1";
        psi.Environment["GIT_OPTIONAL_LOCKS"] = "0";
        try
        {
            using var p = Process.Start(psi);
            if (p == null) return null;
            var output = p.StandardOutput.ReadToEndAsync();
            _ = p.StandardError.ReadToEndAsync();
            if (!p.WaitForExit(20000)) { try { p.Kill(true); } catch { } return null; }
            return p.ExitCode == 0 ? output.Result : null;
        }
        catch
        {
            return null;
        }
    }
}
