using System.Text.Json;
using GromitBot.Agent.Configuration;
using GromitBot.Agent.Infrastructure;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Profiles;

public sealed class ProfileRepository
{
    private readonly string _profileRoot;
    private readonly Dictionary<string, BotProfile> _cache = new(StringComparer.OrdinalIgnoreCase);

    public ProfileRepository(
        IOptions<AgentOptions> options,
        IHostEnvironment hostEnvironment)
    {
        _profileRoot = ToAbsolutePath(hostEnvironment.ContentRootPath, options.Value.ProfilesDirectory);
        Directory.CreateDirectory(_profileRoot);
    }

    public IReadOnlyList<string> ListProfiles()
    {
        return Directory
            .EnumerateFiles(_profileRoot, "*.json", SearchOption.TopDirectoryOnly)
            .Select(Path.GetFileNameWithoutExtension)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToList()!;
    }

    public bool Exists(string profileName)
    {
        string path = Path.Combine(_profileRoot, $"{profileName}.json");
        return File.Exists(path);
    }

    public bool TryLoad(string profileName, out BotProfile? profile)
    {
        if (_cache.TryGetValue(profileName, out BotProfile? cached))
        {
            profile = cached;
            return true;
        }

        string path = Path.Combine(_profileRoot, $"{profileName}.json");
        if (!File.Exists(path))
        {
            profile = null;
            return false;
        }

        string json = File.ReadAllText(path);
        BotProfile? loaded = JsonSerializer.Deserialize<BotProfile>(json, JsonDefaults.Options);
        if (loaded is null)
        {
            profile = null;
            return false;
        }

        if (string.IsNullOrWhiteSpace(loaded.Name))
        {
            loaded.Name = profileName;
        }

        if (string.IsNullOrWhiteSpace(loaded.NavMesh))
        {
            loaded.NavMesh = "default";
        }

        _cache[profileName] = loaded;
        profile = loaded;
        return true;
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