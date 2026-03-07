using System.Text.Json;
using GromitBot.Agent.Configuration;
using GromitBot.Agent.Infrastructure;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Nav;

public sealed class NavMeshRepository
{
    private readonly string _navRoot;
    private readonly Dictionary<string, NavMesh> _cache = new(StringComparer.OrdinalIgnoreCase);

    public NavMeshRepository(
        IOptions<AgentOptions> options,
        IHostEnvironment hostEnvironment)
    {
        _navRoot = ToAbsolutePath(hostEnvironment.ContentRootPath, options.Value.NavMeshesDirectory);
        Directory.CreateDirectory(_navRoot);
    }

    public bool TryLoad(string name, out NavMesh? navMesh)
    {
        if (_cache.TryGetValue(name, out NavMesh? cached))
        {
            navMesh = cached;
            return true;
        }

        string path = Path.Combine(_navRoot, $"{name}.json");
        if (!File.Exists(path))
        {
            navMesh = null;
            return false;
        }

        string json = File.ReadAllText(path);
        navMesh = JsonSerializer.Deserialize<NavMesh>(json, JsonDefaults.Options);
        if (navMesh is null)
        {
            return false;
        }

        _cache[name] = navMesh;
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