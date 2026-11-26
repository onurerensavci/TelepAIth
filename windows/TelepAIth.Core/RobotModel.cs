using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

/// <summary>
/// Bir AI'ın (kaynağın) durumu: oturumları takip eder, robotun ne söyleyeceğini hesaplar.
/// Ekrandaki tek robot, o an gösterilen kaynağın modelini çizer. (Mac sürümündeki RobotModel'in aynısı.)
/// </summary>
/// <summary>Robotun el hareketleri</summary>

public sealed class RobotModel
{
    private sealed class Session
    {
        public RobotState State = RobotState.Idle;
        public string? Text;
        public string? Emoji;
        public string? Project;
        public DateTime Updated;
        public DateTime? TurnStart;
        public DateTime? LastWaitNotice;
        public int Tools, Edits, Errors, ErrorRun;
        public AppTarget? Target;
        public DateTime? WaitingSince;
        public bool Reminded;
        /// <summary>Kullanıcı bu sohbete en son ne zaman baktı (listeden açtı, uygulamada öndeydi)</summary>
        public DateTime SeenAt = DateTime.MinValue;
    }

    /// <summary>Kind: ses ayarı için olay türü (done, waiting, reminder, error, usage, alert, summary)</summary>
    /// <summary>Bildirim; Source + SessionId: tıklayınca açılacak sohbet.</summary>
    public sealed record Notice(string Title, string Body, bool Important = false, AppTarget? Target = null, string Kind = "done",
                                string? Source = null, string? SessionId = null);

    /// <summary>Kafaya tıklayınca açılan listedeki bir sohbet: ad, durum, "çalışıyor · 3 dk" gibi durum yazısı</summary>
    /// <summary>
    /// Rank: 0 seni bekliyor, 1 yeni bitti (bakılmadı), 2 çalışıyor, 3 bitti (bakıldı). Time: "2 dk" / "5 dk önce".
    /// Unread: bildirim gelmiş ama sohbete bakılmamış (listede nokta).
    /// </summary>
    public sealed record ChatRow(string Source, string SessionId, string Title, RobotState State, string Status,
                                 AppTarget? Target, int Rank, DateTime At, string Time = "", bool Unread = false)
    {
        /// <summary>Listede sağda: "bekliyor · 2 dk", "6 sn" (çalışıyor), "5 dk önce" (bitti), "hata · 5 dk önce"</summary>
        public string Label => Rank == 0 ? L("bekliyor · ", "waiting · ") + Time
            : State == RobotState.Error ? L("hata · ", "error · ") + Time : Time;

        /// <summary>Renk kodu: waiting (turuncu), working (AI rengi), error (kırmızı), fresh (yeşil: yeni bitti), seen (gri: bakılmış)</summary>
        public string Tone => Rank == 0 ? "waiting" : Rank == 2 ? "working" : State == RobotState.Error ? "error" : Rank == 1 ? "fresh" : "seen";
    }

    /// <summary>Ön plandaki uygulamanın açık sohbeti ("app-{pid}-…") görülüyor sayılır</summary>
    public void MarkSeenPrefix(string prefix, DateTime now)
    {
        foreach (var (id, s) in _sessions)
            if (id.StartsWith(prefix, StringComparison.Ordinal)) s.SeenAt = now;
    }

    /// <summary>Sohbete bakıldı: okunmamış noktası söner</summary>
    public void MarkSeen(string sessionId, DateTime now)
    {
        if (_sessions.TryGetValue(sessionId, out var s)) s.SeenAt = now;
    }

    /// <summary>Robotun yanındaki minik kafalar: aynı anda çalışan diğer oturumlar.</summary>
    public sealed record MiniSession(string Id, string Source, RobotState State, string Label);

    /// <summary>Ses çal (uygulama doldurur): "Glass", "Ping", "Basso", "Hero"</summary>
    public static Action<string>? PlaySound;

    public string Source { get; }
    public SourceTheme Theme { get; private set; }
    public RobotState State { get; private set; } = RobotState.Idle;
    public string? BubbleText { get; private set; }
    public string? BubbleSubtitle { get; private set; }
    public DateTime? CelebrateStart { get; private set; }
    public DateTime? ErrorStart { get; private set; }
    public Mood? Mood { get; private set; }
    /// <summary>Seni bekleyen şey bir soru mu (onay değil)? Gözlerde "?" çıkar.</summary>
    public bool IsAsking { get; private set; }

    /// <summary>Gözde çıkan simge: ? soru, ! onay bekliyor, ✓ yeni bitti (1,4 sn), % kota azaldı (10 sn'de bir yanıp söner); yoksa '\0'</summary>
    public char EyeGlyph(DateTime now)
    {
        // Seni bekliyorsa (başka bir oturumun ruh hâli olsa bile) önce o görünsün
        if (State == RobotState.Waiting) return IsAsking ? '?' : '!';
        if (Mood != null) return '\0';
        var age = (now - VisualChangedAt).TotalSeconds;
        return State switch
        {
            RobotState.Done when age < 1.4 => '✓',
            RobotState.Idle when (QuotaLeft ?? UsageLeft) is <= 20 && now.TimeOfDay.TotalSeconds % 10 < 1.6 => '%',
            _ => '\0',
        };
    }

    /// <summary>Dışarıdan kısa bir ruh hâli (ör. art arda tıklanınca başı döner)</summary>
    public void React(Mood mood, double seconds, string? say = null)
    {
        var now = DateTime.Now;
        SetMood(mood, seconds, now);
        if (say != null) ShowOverride(say, seconds, now);
        Refresh(now);
    }
    public AppTarget? Target { get; private set; }
    public DateTime? WaitingSince { get; private set; }
    public int? QuotaLeft { get; private set; }
    /// <summary>Claude Code'un durum satırından kalan kullanım (%); uygulama her karede günceller</summary>
    public int? UsageLeft { get; set; }
    public bool BubbleIsExplicit { get; private set; }
    public string? BestSessionId { get; private set; }
    public DateTime? LastRealEvent { get; private set; }
    /// <summary>
    /// Şu anki hâline (çalışıyor / seni bekliyor / ikisi de değil) ne zaman girdi. Sadece bu geçişlerde değişir;
    /// her aşama mesajında değişmediği için iki AI aynı anda çalışırken hangisinin gösterileceği bununla seçilir.
    /// </summary>
    public DateTime ActiveSince { get; private set; } = DateTime.MinValue;
    /// <summary>Herhangi bir oturumu en son ne zaman çalışıyor / seni bekliyor / hatadaydı (gösterilmeyen sohbetler dahil)</summary>
    public DateTime LastBusyAt { get; private set; } = DateTime.MinValue;
    private int _activeKind;
    public List<Notice> PendingNotices { get; } = new();
    public IReadOnlyList<string> History => _history;

    public event Action? StateChanged;

    private readonly Dictionary<string, Session> _sessions = new();
    private readonly List<string> _history = new();
    private DateTime? _quotaAt;
    private DateTime? _explicitUntil;
    private DateTime? _moodUntil;
    private DateTime _lastEventAt = DateTime.Now;
    private DateTime _lastCleanup = DateTime.Now;
    private string? _overrideText;
    private DateTime? _overrideUntil;
    private DateTime _nextIdleThought = DateTime.Now.AddSeconds(Random.Shared.Next(60, 120));

    public RobotModel(string source)
    {
        Source = source;
        Theme = Themes.Shared.Theme(source);
    }

    public void ReloadTheme() => Theme = Themes.Shared.Theme(Source);

    /// <summary>Teşhis: oturumlar ve durumları</summary>
    public IEnumerable<(string Id, RobotState State)> SessionStates => _sessions.Select(kv => (kv.Key, kv.Value.State)).ToList();

    public string StatusLine => Clip(BubbleText ?? WithEmoji(State.Emoji(), State.Label()), 48);

    private static string DonePhrase()
    {
        var phrases = Lang.Current == Language.Tr
            ? new[] { "Bitti!", "Tamamdır!", "Hallettim!", "İş bitti!" }
            : new[] { "Done!", "All set!", "Finished!", "Nailed it!" };
        return phrases[Random.Shared.Next(phrases.Length)];
    }

    private static string DoneEmoji()
    {
        var e = new[] { "🎉", "✨", "✅", "🪄" };
        return e[Random.Shared.Next(e.Length)];
    }

    private void SetMood(Mood mood, double seconds, DateTime now)
    {
        Mood = mood;
        _moodUntil = now.AddSeconds(seconds);
    }

    /// <summary>Robotun kısa sesi: genel ayar açık ve bu tür olayın sesi açıksa (Ses sekmesi)</summary>
    public static void Play(string name, string kind)
    {
        Effects.Kick(Effects.Strength(name));
        if (!Prefs.Sounds || !Prefs.SoundOn(kind) || FocusMode.IsActive) return;
        PlaySound?.Invoke(name);
    }

    private static string IdleThought()
    {
        var thoughts = new (string, string, string)[]
        {
            ("🪄", "Bir büyü yapalım mı?", "Shall we cast a spell?"),
            ("✨", "Hazırım, ne yapıyoruz?", "Ready when you are."),
            ("🔮", "Kristal küreme bakıyorum…", "Gazing into my crystal ball…"),
            ("🙂", "Buradayım.", "I'm right here."),
            ("📚", "Yeni bir şey öğrenmek isterdim.", "I'd love to learn something new."),
            ("☕️", "Kahve molası mı?", "Coffee break?"),
            ("👀", "Noktalarım parlıyor mu?", "Are my dots glowing?"),
        };
        var pick = thoughts[Random.Shared.Next(thoughts.Length)];
        return WithEmoji(pick.Item1, L(pick.Item2, pick.Item3));
    }

    public Notice? Apply(AgentEvent e) => Apply(e, DateTime.Now);

    public Notice? Apply(AgentEvent e, DateTime now)
    {
        _lastEventAt = now;
        if (e.Kind != EventKind.Heartbeat && e.Kind != EventKind.ToolDone) LastRealEvent = now;
        if (!string.IsNullOrEmpty(e.Text)) Remember(WithEmoji(e.Emoji, e.Text), now);
        if (e.Mood is { } m) SetMood(m, e.MoodSeconds, now);
        Notice? notice = null;

        switch (e.Kind)
        {
            case EventKind.Quota:
            {
                var text = WithEmoji(e.Emoji, e.Text ?? "");
                ShowOverride(text, 10, now);
                if (e.State == RobotState.Error) ErrorStart = now;
                if (e.QuotaLeft is { } left)
                {
                    QuotaLeft = Math.Clamp(left, 0, 100);
                    _quotaAt = now;
                }
                else if (e.State == RobotState.Error)
                {
                    QuotaLeft = 0;
                    _quotaAt = now;
                }
                if (e.ForceNotify)
                    notice = new Notice(Theme.DisplayName + L(" kota", " quota"), text,
                                        e.State == RobotState.Error || (e.QuotaLeft ?? 100) <= 10, null, "usage");
                break;
            }
            case EventKind.Heartbeat:
                if (_sessions.TryGetValue(e.SessionId, out var hb))
                {
                    hb.Updated = now;
                    if (e.Project != null) hb.Project = e.Project;   // sohbetin adı sonradan öğrenilebilir
                }
                break;

            case EventKind.Say:
                ShowOverride(WithEmoji(e.Emoji, e.Text ?? ""), 4, now);
                break;

            case EventKind.Insight:
            {
                // Takıldı, çakışma, CI, commit, kullanım sınırı: balonda söyle ve bildir
                var text = WithEmoji(e.Emoji, e.Text ?? "");
                ShowOverride(text, 8, now);
                if (e.UsageLeft is { } left) UsageLeft = left;
                var target = _sessions.TryGetValue(e.SessionId, out var ins) ? ins.Target : null;
                notice = new Notice(Theme.DisplayName, text, e.Important, target, e.SessionId == "usage" ? "usage" : "alert");
                break;
            }

            case EventKind.ToolDone:
            {
                if (_sessions.TryGetValue(e.SessionId, out var s))
                {
                    if (s.State == RobotState.Waiting)
                    {
                        s.State = RobotState.Thinking;
                        s.Text = L("Devam ediyor…", "Back to work…");
                        s.Emoji = "🔮";
                        s.WaitingSince = null;
                        s.Reminded = false;
                    }
                    if (e.State == RobotState.Error)
                    {
                        s.Errors++;
                        s.ErrorRun++;
                        if (s.ErrorRun >= 3)
                        {
                            SetMood(Core.Mood.Dizzy, 6, now);
                            ShowOverride(WithEmoji("😵‍💫", L($"Üst üste {s.ErrorRun} hata", $"{s.ErrorRun} errors in a row")), 5, now);
                            Play("Basso", "error");
                        }
                    }
                    else
                    {
                        s.ErrorRun = 0;
                    }
                    s.Updated = now;
                }
                var run = _sessions.TryGetValue(e.SessionId, out var s2) ? s2.ErrorRun : 0;
                if (e.Text != null && !(e.State == RobotState.Error && run >= 3))
                {
                    ShowOverride(WithEmoji(e.Emoji, e.Text), 4, now);
                    if (e.Mood == Core.Mood.Party) Play("Hero", "summary");
                }
                break;
            }
            case EventKind.SessionEnd:
                _sessions.Remove(e.SessionId);
                break;

            default:
            {
                if (!_sessions.TryGetValue(e.SessionId, out var s))
                {
                    s = new Session { Project = e.Project, Updated = now };
                    _sessions[e.SessionId] = s;
                }
                var wasWorking = s.State.IsWorking();
                if (e.State is { } st) s.State = st;
                // Yan menüdeki bir sohbet arkada çalışmaya başladı (Ses sekmesinden açılırsa kısa ses)
                if (!wasWorking && s.State.IsWorking() && e.Emoji == "🔄") Play("Tink", "background");
                if (e.Text != null)
                {
                    s.Text = e.Text;
                    s.Emoji = e.Emoji ?? s.State.Emoji();
                }
                if (e.Project != null) s.Project = e.Project;
                var pid = e.AppPid ?? e.QuietIfForegroundPid;
                if (pid != null) s.Target = new AppTarget(pid, null);
                else if (!string.IsNullOrEmpty(e.AppProcess)) s.Target = new AppTarget(null, e.AppProcess);
                if (s.State == RobotState.Waiting)
                {
                    s.WaitingSince ??= now;
                }
                else
                {
                    s.WaitingSince = null;
                    s.Reminded = false;
                }
                s.Updated = now;
                if (e.Kind == EventKind.Prompt)
                {
                    s.TurnStart = now;
                    s.Tools = s.Edits = s.Errors = s.ErrorRun = 0;
                }
                if (s.State.IsWorking() && s.TurnStart == null) s.TurnStart = now;
                if (e.Kind == EventKind.Tool)
                {
                    s.Tools++;
                    if (s.State == RobotState.Editing) s.Edits++;
                }
                var place = s.Project != null ? " · " + s.Project : "";

                switch (e.Kind)
                {
                    case EventKind.Stop:
                    {
                        var duration = s.TurnStart != null ? (now - s.TurnStart.Value).TotalSeconds : 0;
                        var parts = new List<string> { DonePhrase() };
                        if (duration >= 1) parts.Add(FormatDuration(duration));
                        if (s.Tools > 0) parts.Add(L($"{s.Tools} araç", $"{s.Tools} tools"));
                        if (s.Edits > 0) parts.Add(L($"{s.Edits} düzenleme", $"{s.Edits} edits"));
                        var text = e.Text ?? string.Join(" · ", parts);
                        if (!string.IsNullOrEmpty(e.LastMessage)) text += "\n" + Clip(e.LastMessage, 110);
                        s.Text = text;
                        if (duration > 180 || s.Tools > 25)
                        {
                            s.Emoji = e.Emoji ?? "😮‍💨";
                            SetMood(Core.Mood.Tired, 6, now);
                        }
                        else if (s.Edits > 0 && s.Errors == 0)
                        {
                            s.Emoji = e.Emoji ?? DoneEmoji();
                            SetMood(Core.Mood.Proud, 6, now);
                        }
                        else
                        {
                            s.Emoji = e.Emoji ?? DoneEmoji();
                        }
                        if (duration >= 1 || s.Tools > 0)
                        {
                            DailyStats.Shared.RecordTurn(Source, duration, s.Tools, s.Edits, now, s.Project);
                            Progress.Shared.Turn(Source, duration, s.Tools, s.Edits, now, DailyStats.Shared.TurnsOn(now));
                        }
                        s.TurnStart = null;
                        CelebrateStart = now;
                        // Gurur/parti anında alkış (normal bitişte el hareketi yok: zıplama ve parıltı yeter)
                        Play("Glass", "done");
                        Remember(WithEmoji(s.Emoji, text), now);
                        // Anlatıcının "bitti"si bildirim atmaz (izleyici ya da hook zaten haber veriyor)
                        if (e.SessionId != "mcp" && (e.ForceNotify || duration >= Prefs.LongTurnSeconds))
                        {
                            var body = (s.Project ?? L("Görev", "Task")) + " — " + FormatDuration(duration);
                            if (!string.IsNullOrEmpty(e.LastMessage)) body += "\n" + Clip(e.LastMessage, 140);
                            notice = new Notice(WithEmoji(s.Emoji, Theme.DisplayName + L(" bitirdi", " is done")), body, false, s.Target, "done");
                        }
                        break;
                    }
                    case EventKind.Waiting:
                    {
                        var canNotify = s.LastWaitNotice == null || (now - s.LastWaitNotice.Value).TotalSeconds > 20;
                        if (canNotify)
                        {
                            s.LastWaitNotice = now;
                            DailyStats.Shared.RecordWait(Source, now);
                            Progress.Shared.Wait();
                            Play("Ping", "waiting");
                            notice = new Notice(WithEmoji(s.Emoji, Theme.DisplayName + L(" seni bekliyor", " needs you") + place),
                                                s.Text ?? L("Cevabını bekliyor", "Waiting for your reply"), true, s.Target, "waiting");
                        }
                        break;
                    }
                    case EventKind.Failure:
                        ErrorStart = now;
                        Play("Basso", "error");
                        notice = new Notice(WithEmoji(s.Emoji, Theme.DisplayName + L(" hata verdi", " hit an error") + place),
                                            s.Text ?? "", true, s.Target, "error");
                        break;
                    case EventKind.Interrupt:
                        s.TurnStart = null;
                        break;
                }
                // Uygulama işi bitirdiyse anlatıcının son cümlesi ekranda asılı kalmasın
                if (e.Kind == EventKind.Stop && e.SessionId != "mcp") _sessions.Remove("mcp");
                break;
            }
        }

        Refresh(now);
        if (notice != null) notice = notice with { Source = Source, SessionId = e.SessionId };
        return e.NoNotice ? null : notice;
    }

    /// <summary>Kutlama: sevinçle zıplar, parıltı saçar ve balonda söyler (gardıropta bir şey açıldı…)</summary>
    public void Celebrate(string text, double seconds = 9)
    {
        var now = DateTime.Now;
        SetMood(Core.Mood.Party, 4, now);
        CelebrateStart = now;
        Play("Hero", "summary");
        Say(text, seconds);
    }

    /// <summary>Robotun balonda bir şey söylemesi (güncelleme haberi, uyarı…). Odak modunda da görünür.</summary>
    public void Say(string text, double seconds = 8)
    {
        var now = DateTime.Now;
        ShowOverride(text, seconds, now);
        _explicitUntil = now.AddSeconds(seconds);
        Refresh(now);
    }

    /// <summary>
    /// Uyuyorsa uyandır (AI uygulaması açıldı, öne geldi ya da robota tıklandı).
    /// greet: kısa bir balon; always değilse sadece uyuyorduysa gösterilir.
    /// </summary>
    public void Wake(string? greet = null, bool always = false, DateTime? at = null)
    {
        var now = at ?? DateTime.Now;
        var wasSleeping = State == RobotState.Sleeping;
        _lastEventAt = now;
        if ((wasSleeping || always) && greet != null)
        {
            ShowOverride(greet, 3, now);
        }
        Refresh(now);
    }

    /// <summary>Balondaki geçici yazıyı kaldır (yeni bir soru geldiğinde eski "izin verdim" onu örtmesin)</summary>
    public void ClearSay(DateTime? at = null)
    {
        _overrideUntil = null;
        _explicitUntil = null;
        Refresh(at ?? DateTime.Now);
    }

    public void ShowHistory()
    {
        var lines = _history.TakeLast(5).ToList();
        ShowOverride(lines.Count == 0 ? L("Henüz bir şey olmadı", "Nothing has happened yet") : string.Join("\n", lines), 6, DateTime.Now);
        Refresh(DateTime.Now);
    }

    private void Remember(string text, DateTime now)
    {
        var shortText = Clip(text, 60);
        if (_history.Count > 0 && _history[^1].EndsWith(shortText, StringComparison.Ordinal)) return;
        _history.Add($"{now:HH:mm}  {shortText}");
        if (_history.Count > 30) _history.RemoveRange(0, _history.Count - 30);
    }

    private void ShowOverride(string text, double seconds, DateTime now)
    {
        _overrideText = text;
        _overrideUntil = now.AddSeconds(seconds);
        _explicitUntil = null;
    }

    /// <summary>Durum hesaplama (saniyede birkaç kez çağrılır)</summary>
    public void Refresh(DateTime now)
    {
        if (_moodUntil is { } mu && mu <= now)
        {
            _moodUntil = null;
            Mood = null;
        }
        if ((now - _lastCleanup).TotalSeconds > 5)
        {
            _lastCleanup = now;
            foreach (var id in _sessions.Where(kv => (now - kv.Value.Updated).TotalSeconds >= 3600).Select(kv => kv.Key).ToList())
                _sessions.Remove(id);
            // Kota bilgisi 6 saatte eskir
            if (_quotaAt is { } qa && (now - qa).TotalHours > 6)
            {
                _quotaAt = null;
                QuotaLeft = null;
            }
            // Uzun süre onay bekleyen oturum: 2 dakika sonra bir kez daha hatırlat
            if (Prefs.WaitReminders)
            {
                foreach (var (id, s) in _sessions)
                {
                    if (s.State != RobotState.Waiting || s.Reminded || s.WaitingSince == null) continue;
                    if ((now - s.WaitingSince.Value).TotalSeconds < 120) continue;
                    s.Reminded = true;
                    var place = s.Project != null ? " · " + s.Project : "";
                    PendingNotices.Add(new Notice(WithEmoji("⏰", Theme.DisplayName + L(" hâlâ seni bekliyor", " is still waiting for you") + place),
                                                  s.Text ?? L("Cevabını bekliyor", "Waiting for your reply"), true, s.Target, "reminder", Source, id));
                    ShowOverride(WithEmoji("⏰", L("Hâlâ onayını bekliyorum!", "Still waiting for your OK!")), 6, now);
                }
            }
        }

        Session? best = null;
        string? bestId = null;
        var bestState = RobotState.Idle;
        foreach (var (id, s) in _sessions)
        {
            var st = EffectiveState(s, id, now);
            if (st.IsWorking() || st is RobotState.Waiting or RobotState.Error) LastBusyAt = now;
            if (best == null || st.Priority() > bestState.Priority() || (st.Priority() == bestState.Priority() && s.Updated > best.Updated))
            {
                best = s;
                bestId = id;
                bestState = st;
            }
        }
        BestSessionId = bestId;
        IsAsking = bestState == RobotState.Waiting && best?.Emoji == "❓";
        Target = best?.Target;
        WaitingSince = bestState == RobotState.Waiting ? best?.WaitingSince : null;

        var newState = best == null ? RobotState.Idle : bestState;
        if (newState == RobotState.Idle && (now - _lastEventAt).TotalSeconds > 600) newState = RobotState.Sleeping;

        // Boştayken ara sıra laf at
        if (newState == RobotState.Idle && Prefs.IdleChatter && !FocusMode.IsActive && _overrideUntil == null && now >= _nextIdleThought)
        {
            ShowOverride(IdleThought(), 5, now);
            _nextIdleThought = now.AddSeconds(Random.Shared.Next(150, 360));
        }

        string? text = null;
        string? subtitle = null;
        if (_overrideUntil is { } ou && ou > now && _overrideText != null)
        {
            text = _overrideText;
        }
        else
        {
            _overrideText = null;
            _overrideUntil = null;
            if (best != null && newState != RobotState.Idle && newState != RobotState.Sleeping)
            {
                text = best.Text != null ? WithEmoji(best.Emoji, best.Text) : WithEmoji(newState.Emoji(), newState.Label());
                subtitle = best.Project;
                if (newState == RobotState.Done && (now - best.Updated).TotalSeconds > 15)
                {
                    text = null;
                    subtitle = null;
                }
            }
        }

        var kind = newState == RobotState.Waiting ? 2 : newState.IsWorking() || newState == RobotState.Error ? 1 : 0;
        if (kind != _activeKind)
        {
            _activeKind = kind;
            ActiveSince = now;
        }
        if (newState != State)
        {
            State = newState;
            StateChanged?.Invoke();
        }
        BubbleIsExplicit = _explicitUntil is { } eu && eu > now && text != null;
        BubbleText = text;
        BubbleSubtitle = subtitle;
        // Yüz değiştiyse (durum ya da ruh hâli) çizim eskisinden yenisine yumuşakça geçsin
        if (State != _visualState || Mood != _visualMood)
        {
            PreviousState = _visualState;
            PreviousMood = _visualMood;
            VisualChangedAt = now;
            _visualState = State;
            _visualMood = Mood;
        }
    }

    private RobotState _visualState = RobotState.Idle;
    private Mood? _visualMood;
    /// <summary>Bir önceki yüz (durum + ruh hâli) ve değiştiği an: çizim aradaki geçişi yumuşatır.</summary>
    public RobotState PreviousState { get; private set; } = RobotState.Idle;
    public Mood? PreviousMood { get; private set; }
    public DateTime VisualChangedAt { get; private set; } = DateTime.MinValue;

    /// <summary>Bu AI'ın, ekranda gösterilen dışında kalan çalışan/bekleyen oturumları.</summary>
    /// <summary>
    /// Masaüstü uygulamasından izlenen sohbet ("app-…") ile Anlatıcı'nın ("mcp") anlattığı aynı sohbettir:
    /// ikisi ayrı minik kafa olmasın.
    /// </summary>
    public static string SessionGroup(string id) => id == "mcp" || id.StartsWith("app-", StringComparison.Ordinal) ? "desktop" : id;

    public List<MiniSession> MiniSessions(string? excluded, DateTime now)
    {
        var excludedGroup = excluded != null ? SessionGroup(excluded) : null;
        var best = new Dictionary<string, (string Id, Session S, RobotState St)>();
        foreach (var (id, s) in _sessions)
        {
            var group = SessionGroup(id);
            if (group == excludedGroup) continue;
            var st = EffectiveState(s, id, now);
            if (!st.IsWorking() && st != RobotState.Waiting) continue;
            if (best.TryGetValue(group, out var b) && (b.St.Priority() > st.Priority() || (b.St.Priority() == st.Priority() && b.S.Updated >= s.Updated))) continue;
            best[group] = (id, s, st);
        }
        return best.Values
            .Select(x => new MiniSession(Source + "/" + x.Id, Source, x.St,
                string.Join(" · ", new[] { Theme.DisplayName, x.S.Project, x.S.Text != null ? Clip(x.S.Text, 40) : null }.Where(t => t != null))))
            .OrderBy(m => m.Id, StringComparer.Ordinal).ToList();
    }

    /// <summary>
    /// Kafaya tıklayınca açılan liste: seni bekleyen, çalışan ve son 15 dakikada biten sohbetler.
    /// Rank: 0 bekliyor, 1 çalışıyor, 2 bitti/hata. At: o hâle girdiği an (süre bundan).
    /// </summary>
    public List<ChatRow> ChatRows(DateTime now)
    {
        var rows = new List<ChatRow>();
        foreach (var (id, s) in _sessions)
        {
            if (id == "mcp") continue;   // anlatıcı: açık sohbetle aynı
            var st = EffectiveState(s, id, now);
            var age = (now - s.Updated).TotalSeconds;
            string status, time;
            int rank;
            DateTime at;
            var unread = false;
            if (st == RobotState.Waiting)
            {
                at = s.WaitingSince ?? s.Updated;
                time = ShortDuration((now - at).TotalSeconds);
                status = L("seni bekliyor · ", "waiting for you · ") + time;
                rank = 0;
                unread = s.SeenAt < at;
            }
            else if (st.IsWorking())
            {
                at = s.TurnStart ?? s.Updated;
                time = ShortDuration((now - at).TotalSeconds);
                status = L("çalışıyor · ", "working · ") + time;
                rank = 2;
            }
            else if (s.State is RobotState.Done or RobotState.Error && age < 2 * 3600)   // biten sohbetler 2 saat listede kalır
            {
                at = s.Updated;
                var ago = ShortDuration(age);
                time = L($"{ago} önce", $"{ago} ago");
                status = s.State == RobotState.Error
                    ? L($"hata verdi · {ago} önce", $"hit an error · {ago} ago")
                    : L($"bitti · {ago} önce", $"done · {ago} ago");
                unread = s.SeenAt < at;
                rank = unread ? 1 : 3;
            }
            else continue;
            var title = s.Project ?? (id.StartsWith("app-", StringComparison.Ordinal) ? L("Açık sohbet", "Open chat") : L("Oturum", "Session"));
            rows.Add(new ChatRow(Source, id, title, st == RobotState.Idle ? s.State : st, status, s.Target, rank, at, time, unread));
        }
        return rows;
    }

    /// <summary>Şu an çalışan sohbet sayısı (başarım: aynı anda 3 sohbet)</summary>
    public int WorkingCount(DateTime now) => _sessions.Count(kv => EffectiveState(kv.Value, kv.Key, now).IsWorking());

    private static RobotState EffectiveState(Session s, string id, DateTime now)
    {
        var age = (now - s.Updated).TotalSeconds;
        if (id == "mcp" && s.State.IsWorking() && age > 90) return RobotState.Idle;   // anlatıcı sustuysa
        if (s.State == RobotState.Done && age > 90) return RobotState.Idle;
        if (s.State == RobotState.Error && age > 60) return RobotState.Idle;
        if (s.State.IsWorking() && age > 300) return RobotState.Idle;   // takılı kalan oturum
        return s.State;
    }
}

/// <summary>Günlük özet için sayaçlar (~/.telepaith/daily-stats.json, son 14 gün).</summary>
public sealed class DailyStats
{
    public static DailyStats Shared { get; } = new(AppInfo.StatsFile);

    public sealed class Day
    {
        public int Turns { get; set; }
        public double Seconds { get; set; }
        public int Tools { get; set; }
        public int Edits { get; set; }
        public int Waits { get; set; }
        /// <summary>Proje → (saniye, tur): Emek sekmesi için</summary>
        public Dictionary<string, (double Seconds, int Turns)> Projects { get; } = new();
    }

    /// <summary>Kaç gün saklanır (Emek sekmesi son 30 günü gösterir)</summary>
    /// <summary>Emek'te "Tüm zamanlar" için günler uzun süre saklanır (gün başına birkaç sayı)</summary>
    public const int KeepDays = 3650;

    private readonly string? _file;
    private readonly Dictionary<string, Dictionary<string, Day>> _days = new();
    private readonly object _gate = new();

    public DailyStats(string? file)
    {
        _file = file;
        if (file == null || !File.Exists(file)) return;
        try
        {
            if (System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(file)) is not System.Text.Json.Nodes.JsonObject root) return;
            foreach (var (day, sources) in root)
            {
                if (sources is not System.Text.Json.Nodes.JsonObject so) continue;
                var map = new Dictionary<string, Day>();
                foreach (var (src, node) in so)
                {
                    var d = new Day
                    {
                        Turns = (int)(node.Num("turns") ?? 0),
                        Seconds = node.Num("seconds") ?? 0,
                        Tools = (int)(node.Num("tools") ?? 0),
                        Edits = (int)(node.Num("edits") ?? 0),
                        Waits = (int)(node.Num("waits") ?? 0),
                    };
                    if (node?["projects"] is System.Text.Json.Nodes.JsonObject projects)
                        foreach (var (name, pv) in projects)
                            if (pv is System.Text.Json.Nodes.JsonArray { Count: 2 } a)
                                d.Projects[name] = (a[0]!.GetValue<double>(), a[1]!.GetValue<int>());
                    map[src] = d;
                }
                _days[day] = map;
            }
        }
        catch { /* bozuk dosya */ }
    }

    public static string DayKey(DateTime d) => d.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture);

    public void RecordTurn(string source, double seconds, int tools, int edits, DateTime at, string? project = null) =>
        Update(source, at, d =>
        {
            d.Turns++;
            d.Seconds += Math.Max(0, seconds);
            d.Tools += tools;
            d.Edits += edits;
            if (!string.IsNullOrWhiteSpace(project))
            {
                var p = d.Projects.GetValueOrDefault(project);
                d.Projects[project] = (p.Seconds + Math.Max(0, seconds), p.Turns + 1);
            }
        });

    /// <summary>Bugün (tüm AI'lar) kaç tur</summary>
    public int TurnsOn(DateTime date)
    {
        lock (_gate) return _days.TryGetValue(DayKey(date), out var m) ? m.Values.Sum(d => d.Turns) : 0;
    }

    /// <summary>Emek: son `days` gün (bugün dahil), günlük AI saniyeleri ve projeler. days 0: tüm zamanlar (ilk kayıtlı günden bugüne).</summary>
    public Effort Effort(DateTime today, int days)
    {
        lock (_gate)
        {
            if (days <= 0)
            {
                var first = _days.Keys.Where(k => DateTime.TryParseExact(k, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.None, out _))
                    .OrderBy(k => k, StringComparer.Ordinal).FirstOrDefault();
                days = first == null ? 1
                    : Math.Max(1, (int)(today.Date - DateTime.ParseExact(first, "yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture)).TotalDays + 1);
            }
            var list = new List<EffortDay>();
            var bySource = new Dictionary<string, double>();
            var projects = new Dictionary<string, (double Seconds, int Turns)>();
            int turns = 0, edits = 0;
            for (var i = days - 1; i >= 0; i--)
            {
                var key = DayKey(today.AddDays(-i));
                var secs = new Dictionary<string, double>();
                if (_days.TryGetValue(key, out var map))
                    foreach (var (src, d) in map)
                    {
                        var canon = Themes.Canonical(src);
                        secs[canon] = secs.GetValueOrDefault(canon) + d.Seconds;
                        bySource[canon] = bySource.GetValueOrDefault(canon) + d.Seconds;
                        turns += d.Turns;
                        edits += d.Edits;
                        foreach (var (name, pv) in d.Projects)
                        {
                            var old = projects.GetValueOrDefault(name);
                            projects[name] = (old.Seconds + pv.Seconds, old.Turns + pv.Turns);
                        }
                    }
                list.Add(new EffortDay(key, secs));
            }
            var total = bySource.Values.Sum();
            var projectSeconds = projects.Values.Sum(p => p.Seconds);
            var rows = projects.Select(p => new EffortProject(p.Key, p.Value.Seconds, p.Value.Turns, projectSeconds > 0 ? p.Value.Seconds / projectSeconds : 0))
                .OrderByDescending(p => p.Seconds).ToList();
            return new Effort(list, rows, bySource, total, turns, edits);
        }
    }

    public void RecordWait(string source, DateTime at) => Update(source, at, d => d.Waits++);

    private void Update(string source, DateTime at, Action<Day> change)
    {
        lock (_gate)
        {
            var key = DayKey(at);
            if (!_days.TryGetValue(key, out var map)) _days[key] = map = new();
            if (!map.TryGetValue(source, out var day)) map[source] = day = new Day();
            change(day);
            foreach (var old in _days.Keys.OrderBy(k => k, StringComparer.Ordinal).Take(Math.Max(0, _days.Count - KeepDays)).ToList())
                _days.Remove(old);
            Save();
        }
    }

    private void Save()
    {
        if (_file == null) return;
        try
        {
            var root = new System.Text.Json.Nodes.JsonObject();
            foreach (var (day, map) in _days)
            {
                var so = new System.Text.Json.Nodes.JsonObject();
                foreach (var (src, d) in map)
                {
                    var o = new System.Text.Json.Nodes.JsonObject
                    {
                        ["turns"] = d.Turns, ["seconds"] = d.Seconds, ["tools"] = d.Tools, ["edits"] = d.Edits, ["waits"] = d.Waits,
                    };
                    if (d.Projects.Count > 0)
                    {
                        var po = new System.Text.Json.Nodes.JsonObject();
                        foreach (var (name, pv) in d.Projects) po[name] = new System.Text.Json.Nodes.JsonArray(pv.Seconds, pv.Turns);
                        o["projects"] = po;
                    }
                    so[src] = o;
                }
                root[day] = so;
            }
            File.WriteAllText(_file, root.ToJsonString());
        }
        catch { /* yazılamadı */ }
    }

    public Dictionary<string, Day> Today(DateTime date)
    {
        lock (_gate) return _days.TryGetValue(DayKey(date), out var m) ? new Dictionary<string, Day>(m) : new();
    }

    /// <summary>"Claude: 14 iş, 2 sa 10 dk, 31 düzenleme"</summary>
    public string? Summary(Func<string, string> names, DateTime date)
    {
        var entries = Today(date).Where(kv => kv.Value.Turns > 0).OrderByDescending(kv => kv.Value.Seconds).ToList();
        if (entries.Count == 0) return null;
        return string.Join("\n", entries.Select(kv =>
        {
            var d = kv.Value;
            var parts = new List<string> { L($"{d.Turns} iş", $"{d.Turns} task{(d.Turns == 1 ? "" : "s")}") };
            if (d.Seconds >= 60) parts.Add(FormatDuration(d.Seconds));
            if (d.Edits > 0) parts.Add(L($"{d.Edits} düzenleme", $"{d.Edits} edit{(d.Edits == 1 ? "" : "s")}"));
            if (d.Waits > 0) parts.Add(L($"{d.Waits} kez seni bekledi", $"waited for you {d.Waits}×"));
            return names(kv.Key) + ": " + string.Join(", ", parts);
        }));
    }

    /// <summary>Bugünün özeti zaten söylendi mi?</summary>
    public bool ShownToday
    {
        get => Prefs.GetString("dailySummaryShown") == DayKey(DateTime.Now);
        set => Prefs.Set("dailySummaryShown", value ? DayKey(DateTime.Now) : "");
    }
}
