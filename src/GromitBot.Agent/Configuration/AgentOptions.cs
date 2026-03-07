namespace GromitBot.Agent.Configuration;

public sealed class AgentOptions
{
    public const string SectionName = "Agent";

    public string BindHost { get; set; } = "0.0.0.0";

    public int Port { get; set; } = 9000;

    public string AuthSecret { get; set; } = string.Empty;

    public int BotSlots { get; set; } = 1;

    public string StateDirectory { get; set; } = "state";

    public string ProfilesDirectory { get; set; } = "profiles";

    public string NavMeshesDirectory { get; set; } = "navmeshes";

    public string IpcDirectory { get; set; } = "ipc";

    public int SnapshotIntervalSeconds { get; set; } = 3;

    public string DefaultMode { get; set; } = "leveling";
}