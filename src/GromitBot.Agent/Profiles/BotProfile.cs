namespace GromitBot.Agent.Profiles;

public sealed class BotProfile
{
    public string Name { get; set; } = "default";

    public string? Description { get; set; }

    public string NavMesh { get; set; } = "default";

    public List<int> RouteNodeIds { get; set; } = [];

    public List<BotProfileStep> Steps { get; set; } = [];
}

public sealed class BotProfileStep
{
    public string? Zone { get; set; }

    public string Action { get; set; } = "grind";

    public int? TargetLevel { get; set; }
}
