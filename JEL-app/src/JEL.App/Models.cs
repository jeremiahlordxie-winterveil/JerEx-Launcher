using System.Text.Json.Serialization;

namespace JerEx.JEL;

public sealed class JelConfig
{
    public int SchemaVersion { get; set; } = 1;
    public string Version { get; set; } = "0.1.0-dev";
    public string TestUri { get; set; } = "https://www.cloudflare.com/cdn-cgi/trace";
    public string OpenAiTestUri { get; set; } = "https://api.openai.com/v1/models";
    public string ChatGptTestUri { get; set; } = "https://chatgpt.com/";
    public List<int> CandidatePorts { get; set; } = new() { 7897, 7890, 1080, 10808, 8080, 10809 };
    public ProxyEndpoint? LastProxy { get; set; }
    public DateTimeOffset? LastValidatedAt { get; set; }
}

public sealed class ProxyEndpoint
{
    public string Protocol { get; set; } = "http";
    public int Port { get; set; }
    [JsonIgnore] public Uri Uri => new($"{Protocol}://127.0.0.1:{Port}");
    public override string ToString() => $"{Protocol.ToUpperInvariant()} 127.0.0.1:{Port}";
}

public sealed record ProbeResult(bool TransportOk, int? StatusCode, string? Error)
{
    public bool Reachable => TransportOk && (StatusCode is null || (StatusCode >= 200 && StatusCode < 500));
    public override string ToString() => StatusCode is int code ? $"{code}" : (Error ?? (TransportOk ? "OK" : "Failed"));
}

public sealed record ChatGptInstallation(string PackageName, string Version, string InstallPath, string FamilyName, string AppUserModelId, bool IsRunning);

public sealed record EnvironmentInfo(string CodexHome, string EnvFile, bool IsJunction, bool HasConfig);

public sealed record ProxyCheck(ProxyEndpoint Endpoint, ProbeResult Network, ProbeResult OpenAi, ProbeResult ChatGpt)
{
    public bool IsUsable => Network.Reachable && OpenAi.Reachable && ChatGpt.Reachable;
}
