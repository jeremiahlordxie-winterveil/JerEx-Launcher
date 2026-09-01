namespace JerEx.JEL;

public sealed class MainForm : Form
{
    private readonly Label status = new() { AutoSize = true, Text = "Preparing..." };
    private readonly TextBox details = new() { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill, Visible = false };
    private readonly Button run = new() { Text = "Check and open ChatGPT", AutoSize = true };
    private readonly Button diagnose = new() { Text = "Diagnostics only", AutoSize = true };
    private readonly DiagnosticLogger log = new();
    private readonly bool diagnosticOnStart;
    private readonly bool closeWhenDone;
    private bool busy;
    public MainForm(bool diagnosticOnStart = false, bool closeWhenDone = false)
    {
        this.diagnosticOnStart = diagnosticOnStart;
        this.closeWhenDone = closeWhenDone;
        Text = "JEL - ChatGPT launcher"; Width = 620; Height = 420; StartPosition = FormStartPosition.CenterScreen;
        var title = new Label { Text = "JEL", Font = new Font(Font.FontFamily, 20, FontStyle.Bold), AutoSize = true };
        var hint = new Label { Text = "Checks network and configuration, then opens ChatGPT.", AutoSize = true, Top = 48 };
        var toggle = new CheckBox { Text = "Show detailed diagnostics", AutoSize = true, Top = 84 }; toggle.CheckedChanged += (_, _) => details.Visible = toggle.Checked;
        var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 52 }; buttons.Controls.AddRange(new Control[] { run, diagnose });
        var top = new Panel { Dock = DockStyle.Top, Height = 120 }; top.Controls.Add(title); top.Controls.Add(hint); top.Controls.Add(toggle); status.Top = 105; top.Controls.Add(status);
        Controls.Add(details); Controls.Add(buttons); Controls.Add(top); run.Click += async (_, _) => await RunAsync(false); diagnose.Click += async (_, _) => await RunAsync(true); Shown += async (_, _) => await RunAsync(diagnosticOnStart);
    }
    private async Task RunAsync(bool diagnosticOnly)
    {
        if (busy) return; busy = true; run.Enabled = diagnose.Enabled = false; details.Clear();
        try
        {
            var store = new ConfigStore(); var config = store.Load(); var env = new EnvironmentResolver().Resolve(); var appResolver = new ChatGptAppResolver(); var app = appResolver.Resolve();
            Add($"CODEX_HOME: {env.CodexHome}"); Add($"ChatGPT: {(app is null ? "not found" : $"{app.PackageName} {app.Version}")}"); if (app is null) { if (appResolver.LastError is not null) Add($"App discovery error: {appResolver.LastError}"); status.Text = "ChatGPT was not found."; return; }
            var check = await new ProxyDiscovery().FindAsync(config, CancellationToken.None, Add); if (check is null) { status.Text = "No usable network path found."; return; }
            Add($"Usable path: {check.Endpoint}; OpenAI {check.OpenAi}; ChatGPT {check.ChatGpt}"); config.LastProxy = check.Endpoint; config.LastValidatedAt = DateTimeOffset.Now; store.Save(config); if (diagnosticOnly) { status.Text = "Diagnostics complete."; return; }
            var editor = new CodexEnvEditor(); if (editor.NeedsUpdate(env.EnvFile, check.Endpoint))
            {
                var answer = MessageBox.Show($"ChatGPT configuration needs {check.Endpoint}. Update .env?", "JEL", MessageBoxButtons.YesNo, MessageBoxIcon.Question); if (answer == DialogResult.Yes) { editor.Update(env.EnvFile, check.Endpoint); Add("Updated ChatGPT .env (backup created)."); } else Add(".env update declined; ChatGPT will still be opened.");
            }
            if (app.IsRunning && MessageBox.Show("ChatGPT is already running. Restart it to apply configuration?", "JEL", MessageBoxButtons.YesNo, MessageBoxIcon.Question) == DialogResult.Yes) new LaunchCoordinator().StopRunning(app);
            var launcher = new LaunchCoordinator(); if (!launcher.Launch(app)) { status.Text = "Could not open ChatGPT."; return; } status.Text = await launcher.WaitForRunningAsync(app, CancellationToken.None) ? "ChatGPT is ready." : "ChatGPT startup timed out.";
        }
        catch (Exception ex) { log.Error("Run failed", ex); Add(ex.Message); status.Text = "Operation failed."; }
        finally
        {
            busy = false; run.Enabled = diagnose.Enabled = true;
            if (closeWhenDone) BeginInvoke(Close);
        }
    }
    private void Add(string text) { details.AppendText($"{DateTime.Now:T}  {text}{Environment.NewLine}"); log.Info(text); }
}
