using GromitBot.Agent.Configuration;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Wow;

public sealed class MemoryInputBridge : IWowBridge
{
    private readonly string _ipcRoot;

    public MemoryInputBridge(
        IOptions<AgentOptions> options,
        IHostEnvironment hostEnvironment)
    {
        _ipcRoot = ToAbsolutePath(hostEnvironment.ContentRootPath, options.Value.IpcDirectory);
        Directory.CreateDirectory(_ipcRoot);
    }

    public Task<WowTelemetry?> ReadTelemetryAsync(int botId, CancellationToken cancellationToken)
    {
        return Task.FromResult<WowTelemetry?>(null);
    }

    public Task QueueActionAsync(int botId, WowAction action, CancellationToken cancellationToken)
    {
        string file = Path.Combine(_ipcRoot, $"memory-actions-slot-{botId}.log");
        string line = $"{DateTimeOffset.UtcNow:O} {action.Command} {action.Args}";
        return File.AppendAllTextAsync(file, line + Environment.NewLine, cancellationToken);
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