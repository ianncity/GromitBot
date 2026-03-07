using System.Text.Json;
using GromitBot.Agent.Configuration;
using GromitBot.Agent.Infrastructure;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.State;

public sealed class StateStore
{
    private readonly string _stateDirectory;
    private readonly object _ioLock = new();
    private readonly ILogger<StateStore> _logger;

    public StateStore(
        IOptions<AgentOptions> options,
        IHostEnvironment hostEnvironment,
        ILogger<StateStore> logger)
    {
        _logger = logger;
        _stateDirectory = ToAbsolutePath(hostEnvironment.ContentRootPath, options.Value.StateDirectory);
        Directory.CreateDirectory(_stateDirectory);
    }

    public Dictionary<int, PersistedBotState> LoadAll(int botSlots)
    {
        Dictionary<int, PersistedBotState> loaded = [];

        for (int slot = 0; slot < botSlots; slot++)
        {
            string file = FilePath(slot);
            if (!File.Exists(file))
            {
                continue;
            }

            try
            {
                string json = File.ReadAllText(file);
                PersistedBotState? state = JsonSerializer.Deserialize<PersistedBotState>(json, JsonDefaults.Options);
                if (state is not null)
                {
                    loaded[slot] = state;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not load state snapshot {File}", file);
            }
        }

        return loaded;
    }

    public void Save(PersistedBotState state)
    {
        lock (_ioLock)
        {
            string file = FilePath(state.BotId);
            string tmp = file + ".tmp";

            try
            {
                string json = JsonSerializer.Serialize(state, JsonDefaults.Options);
                File.WriteAllText(tmp, json);
                File.Move(tmp, file, overwrite: true);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to persist slot state for bot {BotId}", state.BotId);
            }
            finally
            {
                if (File.Exists(tmp))
                {
                    File.Delete(tmp);
                }
            }
        }
    }

    private string FilePath(int botId) => Path.Combine(_stateDirectory, $"slot-{botId}.json");

    private static string ToAbsolutePath(string root, string configuredPath)
    {
        if (Path.IsPathRooted(configuredPath))
        {
            return configuredPath;
        }

        return Path.Combine(root, configuredPath);
    }
}