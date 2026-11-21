using System;
using System.IO;
using System.Threading;
using System.Windows;
using TelepAIth.Core;

namespace TelepAIth;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        try { Directory.CreateDirectory(AppInfo.SupportDir); } catch { }

        // İndirilen klasörden açıldıysa kendini kurup oradan yeniden açar
        if (Installer.EnsureInstalled()) return 0;

        // Tek kopya
        using var mutex = new Mutex(true, @"Local\TelepAIth.Robot", out var first);
        if (!first)
        {
            // Zaten çalışıyor: kısa bir süre bekle (güncelleme sonrası eski kopya kapanıyor olabilir)
            try
            {
                if (!mutex.WaitOne(TimeSpan.FromSeconds(4))) return 0;
            }
            catch (AbandonedMutexException) { }
        }

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.DispatcherUnhandledException += (_, e) =>
        {
            Log("UI: " + e.Exception);
            e.Handled = true;
        };
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log("Fatal: " + e.ExceptionObject);

        var controller = new AppController();
        app.Startup += (_, _) =>
        {
            try { controller.Start(); }
            catch (Exception ex)
            {
                Log("Start: " + ex);
                MessageBox.Show(ex.Message, AppInfo.Name);
                app.Shutdown();
            }
        };
        app.Exit += (_, _) =>
        {
            controller.Stop();
            try { File.Delete(AppInfo.PortFile); } catch { }
        };
        return app.Run();
    }

    private static void Log(string s)
    {
        try { File.AppendAllText(Path.Combine(AppInfo.SupportDir, "error.log"), $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {s}\n"); } catch { }
    }
}
