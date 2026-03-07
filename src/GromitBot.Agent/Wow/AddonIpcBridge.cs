using System.Text.Json;
using GromitBot.Agent.Configuration;
using GromitBot.Agent.Infrastructure;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Wow;

public sealed class AddonIpcBridge : IWowBridge
{
    private readonly string _ipcRoot;
    private readonly ILogger<AddonIpcBridge> _logger;

    public AddonIpcBridge(
        IOptions<AgentOptions> options,
        IHostEnvironment hostEnvironment,
        ILogger<AddonIpcBridge> logger)
    {
        _logger = logger;
        _ipcRoot = ToAbsolutePath(hostEnvironment.ContentRootPath, options.Value.IpcDirectory);
        Directory.CreateDirectory(_ipcRoot);
    }

    public async Task<WowTelemetry?> ReadTelemetryAsync(int botId, CancellationToken cancellationToken)
    {
        string file = Path.Combine(_ipcRoot, $"telemetry-slot-{botId}.json");
        if (!File.Exists(file))
        {
            return null;
        }

        try
        {
            string json = await File.ReadAllTextAsync(file, cancellationToken);
            if (string.IsNullOrWhiteSpace(json))
            {
                return null;
            }

            return JsonSerializer.Deserialize<WowTelemetry>(json, JsonDefaults.Options);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Unable to parse telemetry from {File}", file);
            return null;
        }
    }

    public async Task QueueActionAsync(int botId, WowAction action, CancellationToken cancellationToken)
    {
        string queueFile = Path.Combine(_ipcRoot, $"commands-slot-{botId}.jsonl");
        string payload = JsonSerializer.Serialize(
            new
            {
                ts = DateTimeOffset.UtcNow,
                cmd = action.Command,
                args = action.Args,
            },
            JsonDefaults.Options);

        await File.AppendAllTextAsync(queueFile, payload + Environment.NewLine, cancellationToken);
    }

    private static string ToAbsolutePath(string root, string configuredPath)
    {
        if (Path.IsPathRooted(configuredPath))
        {
            return configuredPath;
        }

        return Path.Combine(root, configuredPath);
    }
}