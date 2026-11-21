using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace TelepAIth;

/// <summary>
/// Renkli emoji. WPF renkli emoji yazı tiplerini (Segoe UI Emoji) tek renk çiziyor; bu yüzden her emojiyi Windows'un kendi
/// çizicisiyle (Direct2D + DirectWrite, renkli yazı tipi açık) bir kere küçük bir resme çizip önbellekte tutuyoruz.
/// Sonuç Windows'taki emojilerin birebir aynısı. Bir sorun olursa düz yazıya döner.
/// </summary>
internal static class Emoji
{
    /// <summary>Bu metin parçası (grafem) emoji mi?</summary>
    public static bool IsEmoji(string element)
    {
        if (element.Length == 0) return false;
        foreach (var rune in element.EnumerateRunes())
        {
            var v = rune.Value;
            if (v is 0xFE0F or 0x200D or 0x20E3) return true;
            if (v >= 0x1F000 && v <= 0x1FAFF) return true;
            if (v >= 0x2600 && v <= 0x27BF && v != 0x2713 && v != 0x2715 && v != 0x2716 && v != 0x2717) return true;
            if (v is >= 0x2B05 and <= 0x2B07 or 0x2B1B or 0x2B1C or 0x2B50 or 0x2B55) return true;
            if (v is 0x231A or 0x231B or 0x2328 or 0x23CF or (>= 0x23E9 and <= 0x23F3) or (>= 0x23F8 and <= 0x23FA)) return true;
            if (v is 0x203C or 0x2049 or 0x2139 or 0x24C2 or 0x3030 or 0x303D or 0x3297 or 0x3299) return true;
        }
        return false;
    }

    /// <summary>Metni parçalara ayırır: (yazı, null) ya da (null, emoji)</summary>
    public static IEnumerable<(string? Text, string? Emoji)> Split(string s)
    {
        var text = new StringBuilder();
        var e = StringInfo.GetTextElementEnumerator(s);
        while (e.MoveNext())
        {
            var el = (string)e.Current;
            if (IsEmoji(el))
            {
                if (text.Length > 0) { yield return (text.ToString(), null); text.Clear(); }
                yield return (null, el);
            }
            else text.Append(el);
        }
        if (text.Length > 0) yield return (text.ToString(), null);
    }

    /// <summary>Bir TextBlock'u yazı + renkli emoji resimleriyle doldurur.</summary>
    public static void Fill(TextBlock t, string s)
    {
        t.Inlines.Clear();
        var size = t.FontSize;
        foreach (var (text, emoji) in Split(s))
        {
            if (text != null) { t.Inlines.Add(new Run(text)); continue; }
            var img = Image(emoji!, size * 1.25, 2.0);
            if (img == null) { t.Inlines.Add(new Run(emoji)); continue; }
            var box = size * 1.25;
            t.Inlines.Add(new InlineUIContainer(new System.Windows.Controls.Image
            {
                Source = img, Width = box, Height = box, Margin = new Thickness(1, 0, 1, 0),
            }) { BaselineAlignment = BaselineAlignment.Center });
        }
    }

    // MARK: Çizim (Direct2D + DirectWrite)

    private static readonly Dictionary<(string, int), BitmapSource?> Cache = new();
    private static bool _broken;
    public static string? LastError { get; private set; }

    /// <summary>Emojinin resmi. size: DIP; scale: ekranın DPI çarpanı (keskin olsun diye o kadar büyük çizilir).</summary>
    public static BitmapSource? Image(string emoji, double size, double scale)
    {
        if (_broken) return null;
        var px = (int)Math.Ceiling(size * Math.Max(1, scale));
        if (px < 4) return null;
        var key = (emoji, px);
        if (Cache.TryGetValue(key, out var cached)) return cached;
        BitmapSource? bmp = null;
        try
        {
            bmp = D2D.Render(emoji, px);
            if (bmp != null)
            {
                // Çizildiği ölçeğe göre DPI ver ki WPF onu tam 'size' DIP gösterip keskin kalsın
                var dpi = 96.0 * px / size;
                var pixels = new byte[px * px * 4];
                bmp.CopyPixels(pixels, px * 4, 0);
                bmp = BitmapSource.Create(px, px, dpi, dpi, PixelFormats.Pbgra32, null, pixels, px * 4);
                bmp.Freeze();
            }
        }
        catch (Exception ex)
        {
            LastError = ex.GetType().Name + ": " + ex.Message;
            _broken = true;   // bir daha deneme; düz yazıya dön
            return null;
        }
        if (Cache.Count > 600) Cache.Clear();
        Cache[key] = bmp;
        return bmp;
    }

    /// <summary>Teşhis/test: çizilen emojide kaç farklı renkli piksel var?</summary>
    public static (bool Ok, int Colored, int Opaque) Probe(string emoji = "🎉")
    {
        var bmp = Image(emoji, 48, 1);
        if (bmp == null) return (false, 0, 0);
        var px = new byte[bmp.PixelWidth * bmp.PixelHeight * 4];
        bmp.CopyPixels(px, bmp.PixelWidth * 4, 0);
        int colored = 0, opaque = 0;
        for (var i = 0; i < px.Length; i += 4)
        {
            int b = px[i], g = px[i + 1], r = px[i + 2], a = px[i + 3];
            if (a < 128) continue;
            opaque++;
            if (Math.Max(r, Math.Max(g, b)) - Math.Min(r, Math.Min(g, b)) > 60) colored++;
        }
        return (true, colored, opaque);
    }

    /// <summary>Ham COM çağrıları (vtable sırasıyla). Ek paket gerektirmez.</summary>
    private static unsafe class D2D
    {
        private static IntPtr _d2d, _dwrite, _wic;

        [DllImport("d2d1.dll")] private static extern int D2D1CreateFactory(int type, in Guid riid, IntPtr options, out IntPtr factory);
        [DllImport("dwrite.dll")] private static extern int DWriteCreateFactory(int type, in Guid riid, out IntPtr factory);
        [DllImport("ole32.dll")] private static extern int CoCreateInstance(in Guid clsid, IntPtr outer, int ctx, in Guid riid, out IntPtr obj);

        private static readonly Guid IID_ID2D1Factory = new("06152247-6f50-465a-9245-118bfd3b6007");
        private static readonly Guid IID_IDWriteFactory = new("b859ee5a-d838-4b5b-a2e8-1adc7d93db48");
        private static readonly Guid CLSID_WICImagingFactory = new("cacaf262-9370-4615-a13b-9f5539da4c0a");
        private static readonly Guid IID_IWICImagingFactory = new("ec5ec8a9-c395-4314-9c77-54d7a935ff70");
        private static readonly Guid WICPixelFormat32bppPBGRA = new("6fddc324-4e03-4bfe-b185-3d77768dc910");

        [StructLayout(LayoutKind.Sequential)]
        private struct RenderTargetProperties
        {
            public int Type;          // D2D1_RENDER_TARGET_TYPE_DEFAULT
            public uint Format;       // DXGI_FORMAT_B8G8R8A8_UNORM = 87
            public int AlphaMode;     // D2D1_ALPHA_MODE_PREMULTIPLIED = 1
            public float DpiX, DpiY;
            public int Usage, MinLevel;
        }

        [StructLayout(LayoutKind.Sequential)] private struct ColorF { public float R, G, B, A; }
        [StructLayout(LayoutKind.Sequential)] private struct RectF { public float Left, Top, Right, Bottom; }

        private static void* Fn(IntPtr obj, int index) => (*(void***)obj)[index];

        private static void Release(IntPtr obj)
        {
            if (obj != IntPtr.Zero) ((delegate* unmanaged[Stdcall]<IntPtr, uint>)Fn(obj, 2))(obj);
        }

        private static void Check(int hr, string what)
        {
            if (hr < 0) throw new COMException(what + $" (0x{hr:X8})", hr);
        }

        private static void Init()
        {
            if (_d2d != IntPtr.Zero) return;
            Check(D2D1CreateFactory(0, IID_ID2D1Factory, IntPtr.Zero, out _d2d), "D2D1CreateFactory");
            Check(DWriteCreateFactory(0, IID_IDWriteFactory, out _dwrite), "DWriteCreateFactory");
            Check(CoCreateInstance(CLSID_WICImagingFactory, IntPtr.Zero, 1 /* CLSCTX_INPROC_SERVER */, IID_IWICImagingFactory, out _wic), "WIC");
        }

        public static BitmapSource? Render(string text, int px)
        {
            Init();
            IntPtr wicBitmap = IntPtr.Zero, rt = IntPtr.Zero, format = IntPtr.Zero, brush = IntPtr.Zero;
            try
            {
                // IWICImagingFactory::CreateBitmap (17)
                var fmt = WICPixelFormat32bppPBGRA;
                Check(((delegate* unmanaged[Stdcall]<IntPtr, uint, uint, Guid*, int, IntPtr*, int>)Fn(_wic, 17))(_wic, (uint)px, (uint)px, &fmt, 2, &wicBitmap), "CreateBitmap");

                // ID2D1Factory::CreateWicBitmapRenderTarget (13)
                var props = new RenderTargetProperties { Type = 0, Format = 87, AlphaMode = 1, DpiX = 96, DpiY = 96 };
                Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, RenderTargetProperties*, IntPtr*, int>)Fn(_d2d, 13))(_d2d, wicBitmap, &props, &rt), "CreateWicBitmapRenderTarget");

                // IDWriteFactory::CreateTextFormat (15)
                var fontSize = px * 0.8f;
                fixed (char* family = "Segoe UI Emoji")
                fixed (char* locale = "en-us")
                    Check(((delegate* unmanaged[Stdcall]<IntPtr, char*, IntPtr, int, int, int, float, char*, IntPtr*, int>)Fn(_dwrite, 15))
                        (_dwrite, family, IntPtr.Zero, 400, 0, 5, fontSize, locale, &format), "CreateTextFormat");
                // IDWriteTextFormat::SetTextAlignment (3) / SetParagraphAlignment (4): ortala
                ((delegate* unmanaged[Stdcall]<IntPtr, int, int>)Fn(format, 3))(format, 2);
                ((delegate* unmanaged[Stdcall]<IntPtr, int, int>)Fn(format, 4))(format, 2);

                // ID2D1RenderTarget::CreateSolidColorBrush (8)
                var black = new ColorF { A = 1 };
                Check(((delegate* unmanaged[Stdcall]<IntPtr, ColorF*, IntPtr, IntPtr*, int>)Fn(rt, 8))(rt, &black, IntPtr.Zero, &brush), "CreateSolidColorBrush");

                // BeginDraw (48), Clear (47), DrawText (27, ENABLE_COLOR_FONT = 4), EndDraw (49)
                ((delegate* unmanaged[Stdcall]<IntPtr, void>)Fn(rt, 48))(rt);
                var clear = new ColorF();
                ((delegate* unmanaged[Stdcall]<IntPtr, ColorF*, void>)Fn(rt, 47))(rt, &clear);
                var rect = new RectF { Left = -px * 0.25f, Top = -px * 0.25f, Right = px * 1.25f, Bottom = px * 1.25f };
                fixed (char* s = text)
                    ((delegate* unmanaged[Stdcall]<IntPtr, char*, uint, IntPtr, RectF*, IntPtr, int, int, void>)Fn(rt, 27))
                        (rt, s, (uint)text.Length, format, &rect, brush, 4, 0);
                Check(((delegate* unmanaged[Stdcall]<IntPtr, ulong*, ulong*, int>)Fn(rt, 49))(rt, null, null), "EndDraw");

                // IWICBitmapSource::CopyPixels (7)
                var stride = px * 4;
                var pixels = new byte[stride * px];
                fixed (byte* p = pixels)
                    Check(((delegate* unmanaged[Stdcall]<IntPtr, IntPtr, uint, uint, byte*, int>)Fn(wicBitmap, 7))(wicBitmap, IntPtr.Zero, (uint)stride, (uint)pixels.Length, p), "CopyPixels");
                var bmp = BitmapSource.Create(px, px, 96, 96, PixelFormats.Pbgra32, null, pixels, stride);
                bmp.Freeze();
                return bmp;
            }
            finally
            {
                Release(brush);
                Release(format);
                Release(rt);
                Release(wicBitmap);
            }
        }
    }
}

/// <summary>
/// Konuşma balonu için yazı yerleşimi: kelime kaydırma, en fazla N satır, sonda "…", emojiler renkli resim.
/// Bir kez hesaplanır, sonra her karede sadece çizilir.
/// </summary>
internal sealed class RichLayout
{
    private sealed record Piece(FormattedText? Text, ImageSource? Image, string? Emoji, double X, double W);

    private readonly List<List<Piece>> _lines = new();
    private readonly double _lineHeight, _emojiSize;
    public double Width { get; private set; }
    public double Height => _lines.Count * _lineHeight;

    private RichLayout(double lineHeight, double emojiSize)
    {
        _lineHeight = lineHeight;
        _emojiSize = emojiSize;
    }

    public static RichLayout Create(string text, Typeface face, double size, Brush brush, double maxWidth, int maxLines, double pixelsPerDip)
    {
        FormattedText Ft(string s) => new(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, face, size, brush, pixelsPerDip);
        var lineHeight = Math.Ceiling(Ft("Ağ").Height);
        var emojiSize = size * 1.3;
        var layout = new RichLayout(lineHeight, emojiSize);
        var spaceW = Ft(" ").WidthIncludingTrailingWhitespace;

        // Parçalar: kelime, boşluk, emoji, satır sonu
        var tokens = new List<(char Kind, string Value)>();
        var word = new StringBuilder();
        void FlushWord()
        {
            if (word.Length > 0) { tokens.Add(('w', word.ToString())); word.Clear(); }
        }
        var en = StringInfo.GetTextElementEnumerator(text);
        while (en.MoveNext())
        {
            var el = (string)en.Current;
            if (el == "\n" || el == "\r\n") { FlushWord(); tokens.Add(('n', "")); }
            else if (el == "\r") { }
            else if (el.Length == 1 && char.IsWhiteSpace(el[0])) { FlushWord(); tokens.Add(('s', " ")); }
            else if (Emoji.IsEmoji(el)) { FlushWord(); tokens.Add(('e', el)); }
            else word.Append(el);
        }
        FlushWord();

        var line = new List<Piece>();
        double x = 0, pending = 0;
        var truncated = false;

        bool NewLine()
        {
            layout._lines.Add(line);
            layout.Width = Math.Max(layout.Width, x);
            line = new List<Piece>();
            x = 0;
            pending = 0;
            if (layout._lines.Count >= maxLines) { truncated = true; return false; }
            return true;
        }

        bool Place(Piece p)
        {
            if (x > 0 && x + pending + p.W > maxWidth && !NewLine()) return false;
            if (x > 0) x += pending;
            pending = 0;
            line.Add(p with { X = x });
            x += p.W;
            return true;
        }

        foreach (var (kind, value) in tokens)
        {
            if (kind == 'n') { if (!NewLine()) break; continue; }
            if (kind == 's') { if (x > 0) pending += spaceW; continue; }
            if (kind == 'e')
            {
                var img = Emoji.Image(value, emojiSize, pixelsPerDip);
                if (!Place(new Piece(img == null ? Ft(value) : null, img, value, 0, img == null ? Ft(value).WidthIncludingTrailingWhitespace : emojiSize + 2))) break;
                continue;
            }
            var ft = Ft(value);
            if (ft.WidthIncludingTrailingWhitespace <= maxWidth)
            {
                if (!Place(new Piece(ft, null, null, 0, ft.WidthIncludingTrailingWhitespace))) break;
                continue;
            }
            // Çok uzun kelime (adres, yol): harf harf böl
            var chunk = new StringBuilder();
            var ok = true;
            var ce = StringInfo.GetTextElementEnumerator(value);
            while (ce.MoveNext() && ok)
            {
                var el = (string)ce.Current;
                if (Ft(chunk + el).WidthIncludingTrailingWhitespace > maxWidth - x && chunk.Length > 0)
                {
                    var part = Ft(chunk.ToString());
                    ok = Place(new Piece(part, null, null, 0, part.WidthIncludingTrailingWhitespace)) && NewLine();
                    chunk.Clear();
                }
                chunk.Append(el);
            }
            if (!ok) break;
            if (chunk.Length > 0)
            {
                var part = Ft(chunk.ToString());
                if (!Place(new Piece(part, null, null, 0, part.WidthIncludingTrailingWhitespace))) break;
            }
        }
        if (!truncated && line.Count > 0)
        {
            layout._lines.Add(line);
            layout.Width = Math.Max(layout.Width, x);
        }
        if (truncated && layout._lines.Count > 0)
        {
            // Son satıra "…" sığdır
            var last = layout._lines[^1];
            var dots = Ft("…");
            double End() => last.Count == 0 ? 0 : last[^1].X + last[^1].W;
            while (last.Count > 0 && End() + dots.Width > maxWidth) last.RemoveAt(last.Count - 1);
            last.Add(new Piece(dots, null, null, End() + (last.Count > 0 ? 1 : 0), dots.Width));
            layout.Width = Math.Max(layout.Width, End());
        }
        if (layout._lines.Count == 0) layout._lines.Add(new List<Piece>());
        return layout;
    }

    public void Draw(DrawingContext dc, Point origin)
    {
        for (var i = 0; i < _lines.Count; i++)
        {
            var y = origin.Y + i * _lineHeight;
            foreach (var p in _lines[i])
            {
                if (p.Image != null)
                {
                    var s = _emojiSize;
                    dc.DrawImage(p.Image, new Rect(origin.X + p.X + 1, y + (_lineHeight - s) / 2, s, s));
                }
                else if (p.Text != null)
                {
                    dc.DrawText(p.Text, new Point(origin.X + p.X, y));
                }
            }
        }
    }
}
