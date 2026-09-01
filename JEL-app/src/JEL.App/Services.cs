using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.Win32;

namespace JerEx.JEL;

public sealed class DiagnosticLogger
{
    private readonly string _file;
    public DiagnosticLogger()
    {
        var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JerEx", "JEL", "logs");
        Directory.CreateDirectory(dir); _file = Path.Combine(dir, "JEL.log");
    }
    public void Info(string message) => Write("INFO", message);
    public void Error(string message, Exception? ex = null) => Write("ERROR", ex is null ? message : $"{message}: {ex.Message}");
    private void Write(string level, string message)
    {
        try { if (File.Exists(_file) && new FileInfo(_file).Length > 1_000_000) File.Move(_file, _file + ".1", true); File.AppendAllText(_file, $"{DateTimeOffset.Now:O} [{level}] {Redact(message)}{Environment.NewLine}"); } catch { }
    }
    private static string Redact(string s) => Regex.Replace(s, "(?i)(token|password|secret|api[_-]?key)\\s*=\\s*[^\\s]+", "$1=<redacted>");
}

public sealed class EnvironmentResolver
{
    public EnvironmentInfo Resolve()
    {
        var home = Environment.GetEnvironmentVariable("CODEX_HOME");
        if (string.IsNullOrWhiteSpace(home)) home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
        home = Path.GetFullPath(home); Directory.CreateDirectory(home);
        var junction = (File.GetAttributes(home) & FileAttributes.ReparsePoint) != 0;
        return new(home, Path.Combine(home, ".env"), junction, File.Exists(Path.Combine(home, "config.toml")));
    }
}

public sealed class ConfigStore
{
    public string Path { get; } = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "JerEx", "JEL", "config.json");
    public JelConfig Load()
    {
        try { if (File.Exists(Path)) return JsonSerializer.Deserialize<JelConfig>(File.ReadAllText(Path)) ?? new(); } catch { }
        return new();
    }
    public void Save(JelConfig config)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        var temp = Path + ".tmp"; File.WriteAllText(temp, JsonSerializer.Serialize(config, new JsonSerializerOptions { WriteIndented = true })); File.Move(temp, Path, true);
    }
}

public sealed class ChatGptAppResolver
{
    public string? LastError { get; private set; }
    public ChatGptInstallation? Resolve()
    {
        try
        {
            var sid = WindowsIdentity.GetCurrent().User?.Value ?? string.Empty;
            var managerType = Type.GetType("Windows.Management.Deployment.PackageManager, Windows.Management, ContentType=WindowsRuntime")
                ?? Type.GetType("Windows.Management.Deployment.PackageManager, Windows.Management");
            if (managerType is null) return ResolveFromRegistry();
            dynamic manager = Activator.CreateInstance(managerType)!;
            var packages = (System.Collections.IEnumerable)manager.FindPackagesForUser(sid);
            foreach (var package in packages)
            {
                var id = package.GetType().GetProperty("Id")!.GetValue(package)!;
                var name = id.GetType().GetProperty("Name")!.GetValue(id)?.ToString() ?? "";
                if (!name.Equals("OpenAI.Codex", StringComparison.OrdinalIgnoreCase) && !name.Equals("ChatGPT", StringComparison.OrdinalIgnoreCase)) continue;
                var location = package.GetType().GetProperty("InstalledLocation")!.GetValue(package)!;
                var installPath = location.GetType().GetProperty("Path")!.GetValue(location)!.ToString()!;
                var manifest = XDocument.Load(System.IO.Path.Combine(installPath, "AppxManifest.xml"));
                var appId = manifest.Descendants().FirstOrDefault(x => x.Name.LocalName == "Application")?.Attribute("Id")?.Value ?? "App";
                var family = id.GetType().GetProperty("FamilyName")!.GetValue(id)!.ToString()!;
                var version = id.GetType().GetProperty("Version")!.GetValue(id)?.ToString() ?? "";
                return new(name, version, installPath, family, $"{family}!{appId}", IsRunning(installPath));
            }
        } catch (Exception ex) { LastError = ex.Message; }
        return ResolveFromRegistry();
    }
    private ChatGptInstallation? ResolveFromRegistry()
    {
        const string rootPath = @"Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages";
        try
        {
            using var root = Registry.CurrentUser.OpenSubKey(rootPath);
            if (root is null) return null;
            var packageKey = root.GetSubKeyNames()
                .Where(x => x.StartsWith("OpenAI.Codex_", StringComparison.OrdinalIgnoreCase) || x.StartsWith("ChatGPT_", StringComparison.OrdinalIgnoreCase))
                .OrderByDescending(x => x, StringComparer.OrdinalIgnoreCase)
                .FirstOrDefault();
            if (packageKey is null) return null;
            using var package = root.OpenSubKey(packageKey);
            var installPath = package?.GetValue("PackageRootFolder") as string;
            if (string.IsNullOrWhiteSpace(installPath) || !File.Exists(System.IO.Path.Combine(installPath, "AppxManifest.xml"))) return null;
            var manifest = XDocument.Load(System.IO.Path.Combine(installPath, "AppxManifest.xml"));
            var identity = manifest.Root?.Elements().FirstOrDefault(x => x.Name.LocalName == "Identity");
            var name = identity?.Attribute("Name")?.Value ?? packageKey.Split('_')[0];
            var version = identity?.Attribute("Version")?.Value ?? "unknown";
            var publisherId = packageKey.Split(new[] { "__" }, StringSplitOptions.None).LastOrDefault();
            if (string.IsNullOrWhiteSpace(publisherId)) return null;
            var family = $"{name}_{publisherId}";
            var appId = manifest.Descendants().FirstOrDefault(x => x.Name.LocalName == "Application")?.Attribute("Id")?.Value ?? "App";
            return new(name, version, installPath, family, $"{family}!{appId}", IsRunning(installPath));
        }
        catch (Exception ex) { LastError = ex.Message; return null; }
    }
    public static bool IsRunning(string installPath)
    {
        foreach (var p in Process.GetProcessesByName("codex"))
        { try { if (p.MainModule?.FileName.StartsWith(installPath, StringComparison.OrdinalIgnoreCase) == true) return true; } catch { } }
        return false;
    }
}

public sealed class CodexEnvEditor
{
    public bool NeedsUpdate(string file, ProxyEndpoint proxy)
    {
        if (!File.Exists(file)) return true;
        var text = File.ReadAllText(file);
        return !Regex.IsMatch(text, $"(?im)^\\s*HTTP_PROXY\\s*=\\s*{Regex.Escape(proxy.Uri.ToString())}\\s*$") || !Regex.IsMatch(text, $"(?im)^\\s*HTTPS_PROXY\\s*=\\s*{Regex.Escape(proxy.Uri.ToString())}\\s*$");
    }
    public string? Update(string file, ProxyEndpoint proxy)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(file)!); var old = File.Exists(file) ? File.ReadAllText(file) : string.Empty;
        var lines = old.Replace("\r\n", "\n").Split('\n').Where(x => !Regex.IsMatch(x, "^\\s*HTTPS?_PROXY\\s*=", RegexOptions.IgnoreCase)).ToList();
        while (lines.Count > 0 && string.IsNullOrEmpty(lines[^1])) lines.RemoveAt(lines.Count - 1);
        lines.Add($"HTTP_PROXY={proxy.Uri}"); lines.Add($"HTTPS_PROXY={proxy.Uri}");
        var backup = file + $".{DateTime.Now:yyyyMMdd-HHmmss-fff}.bak"; if (File.Exists(file)) File.Copy(file, backup, false);
        var temp = file + ".jel.tmp"; File.WriteAllText(temp, string.Join("\r\n", lines) + "\r\n", new UTF8Encoding(false)); File.Move(temp, file, true); return backup;
    }
}

public sealed class ConnectivityProbe
{
    private static readonly int[] Accepted = { 200, 201, 204, 301, 302, 307, 308, 401, 403, 429 };
    public async Task<ProbeResult> HttpAsync(Uri target, ProxyEndpoint? proxy, CancellationToken ct)
    {
        try { using var handler = new HttpClientHandler { UseProxy = proxy is not null, Proxy = proxy is null ? null : new WebProxy(proxy.Uri) }; using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(5) }; using var response = await client.GetAsync(target, HttpCompletionOption.ResponseHeadersRead, ct); return new(true, (int)response.StatusCode, null); }
        catch (Exception ex) { return new(false, null, ex.Message); }
    }
    public async Task<ProbeResult> ProbeAsync(Uri target, ProxyEndpoint proxy, CancellationToken ct)
    {
        return proxy.Protocol.Equals("socks5", StringComparison.OrdinalIgnoreCase) ? await SocksAsync(target, proxy, ct) : await HttpAsync(target, proxy, ct);
    }
    private static async Task<ProbeResult> SocksAsync(Uri target, ProxyEndpoint proxy, CancellationToken ct)
    {
        try
        {
            using var tcp = new TcpClient(); await tcp.ConnectAsync(IPAddress.Loopback, proxy.Port, ct); await using var stream = tcp.GetStream();
            await stream.WriteAsync(new byte[] { 5, 1, 0 }, ct); var hello = await ReadExact(stream, 2, ct); if (hello[1] != 0) return new(false, null, "SOCKS5 authentication is required");
            var host = Encoding.ASCII.GetBytes(target.Host); var req = new byte[7 + host.Length]; req[0] = 5; req[1] = 1; req[3] = 3; req[4] = (byte)host.Length; host.CopyTo(req, 5); req[^2] = (byte)(target.Port >> 8); req[^1] = (byte)target.Port; await stream.WriteAsync(req, ct); var head = await ReadExact(stream, 4, ct); if (head[1] != 0) return new(false, null, $"SOCKS5 error {head[1]}");
            var n = head[3] switch { 1 => 4, 3 => (await ReadExact(stream, 1, ct))[0] + 1, 4 => 16, _ => 0 }; if (n > 0) await ReadExact(stream, n + 2, ct); using var ssl = new System.Net.Security.SslStream(stream, false); await ssl.AuthenticateAsClientAsync(target.Host); var request = $"GET {target.PathAndQuery} HTTP/1.1\r\nHost: {target.Host}\r\nConnection: close\r\n\r\n"; await ssl.WriteAsync(Encoding.ASCII.GetBytes(request), ct); await ssl.FlushAsync(ct); var line = await new StreamReader(ssl).ReadLineAsync(ct); var code = int.TryParse(line?.Split(' ').ElementAtOrDefault(1), out var c) ? c : (int?)null; return new(true, code, null);
        }
        catch (Exception ex) { return new(false, null, ex.Message); }
    }
    private static async Task<byte[]> ReadExact(Stream s, int count, CancellationToken ct) { var b = new byte[count]; var i = 0; while (i < count) { var n = await s.ReadAsync(b.AsMemory(i, count - i), ct); if (n == 0) throw new EndOfStreamException(); i += n; } return b; }
    public static bool IsAccepted(ProbeResult r) => r.TransportOk && r.StatusCode is int c && Accepted.Contains(c);
}

public sealed class ProxyDiscovery
{
    private readonly ConnectivityProbe _probe = new();
    public async Task<ProxyCheck?> FindAsync(JelConfig config, CancellationToken ct, Action<string>? report = null)
    {
        var ports = new List<ProxyEndpoint>();
        if (config.LastProxy is not null) ports.Add(config.LastProxy);
        ports.AddRange(IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners().Where(x => (x.Address.Equals(IPAddress.Loopback) || x.Address.Equals(IPAddress.Any)) && x.Port >= 1024).SelectMany(x => new[] { new ProxyEndpoint { Protocol = "http", Port = x.Port }, new ProxyEndpoint { Protocol = "socks5", Port = x.Port } }));
        ports.AddRange(config.CandidatePorts.SelectMany(p => new[] { new ProxyEndpoint { Protocol = "http", Port = p }, new ProxyEndpoint { Protocol = "socks5", Port = p } }));
        var endpoints = ports.GroupBy(x => $"{x.Protocol}:{x.Port}").Select(x => x.First()).ToArray();
        var checks = await Task.WhenAll(endpoints.Select(endpoint => CheckEndpointAsync(config, endpoint, ct, report)));
        return checks.FirstOrDefault(x => x?.IsUsable == true);
    }
    private async Task<ProxyCheck?> CheckEndpointAsync(JelConfig config, ProxyEndpoint endpoint, CancellationToken ct, Action<string>? report)
    {
        report?.Invoke($"Checking {endpoint}");
        using var probeTimeout = CancellationTokenSource.CreateLinkedTokenSource(ct); probeTimeout.CancelAfter(TimeSpan.FromSeconds(3));
        var net = await _probe.ProbeAsync(new Uri(config.TestUri), endpoint, probeTimeout.Token); if (!ConnectivityProbe.IsAccepted(net)) return null;
        probeTimeout.CancelAfter(TimeSpan.FromSeconds(5));
        var openAi = await _probe.ProbeAsync(new Uri(config.OpenAiTestUri), endpoint, probeTimeout.Token);
        var chat = await _probe.ProbeAsync(new Uri(config.ChatGptTestUri), endpoint, probeTimeout.Token);
        return new ProxyCheck(endpoint, net, openAi, chat);
    }
}

public sealed class LaunchCoordinator
{
    private readonly ChatGptAppResolver _resolver = new();
    public bool StopRunning(ChatGptInstallation app)
    {
        var stopped = true;
        foreach (var p in Process.GetProcessesByName("codex"))
        { try { if (p.MainModule?.FileName.StartsWith(app.InstallPath, StringComparison.OrdinalIgnoreCase) == true) { p.CloseMainWindow(); if (!p.WaitForExit(8000)) p.Kill(true); } } catch { stopped = false; } }
        return stopped;
    }
    public bool Launch(ChatGptInstallation app)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", $"shell:AppsFolder\\{app.AppUserModelId}") { UseShellExecute = true }); return true; } catch { return false; }
    }
    public async Task<bool> WaitForRunningAsync(ChatGptInstallation app, CancellationToken ct)
    {
        for (var i = 0; i < 30; i++) { if (ChatGptAppResolver.IsRunning(app.InstallPath)) return true; await Task.Delay(500, ct); } return false;
    }
}
