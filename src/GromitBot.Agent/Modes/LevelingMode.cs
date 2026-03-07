using System.Globalization;
using GromitBot.Agent.Nav;
using GromitBot.Agent.Profiles;

namespace GromitBot.Agent.Modes;

public sealed class LevelingMode(
    ProfileRepository profiles,
    NavMeshRepository navMeshes,
    ILogger<LevelingMode> logger) : IBotMode
{
    private readonly Dictionary<int, int> _routeCursorByBot = [];

    public string Name => "leveling";

    public async Task TickAsync(BotModeContext context, CancellationToken cancellationToken)
    {
        string profileName = string.IsNullOrWhiteSpace(context.Profile)
            ? "default"
            : context.Profile;

        if (!profiles.TryLoad(profileName, out BotProfile? profile) || profile is null)
        {
            await context.QueueActionAsync("PRINT", $"Missing profile: {profileName}", cancellationToken);
            return;
        }

        if (!navMeshes.TryLoad(profile.NavMesh, out NavMesh? mesh) || mesh is null || mesh.Nodes.Count == 0)
        {
            await context.QueueActionAsync("PRINT", $"Missing navmesh: {profile.NavMesh}", cancellationToken);
            return;
        }

        BotProfileStep? step = ResolveStep(profile, context.Level);
        if (step is not null)
        {
            string stepAction = step.Action.Trim().ToUpperInvariant();
            _ = await context.QueueActionAsync("SET_LEVELING_STEP", stepAction, cancellationToken);
        }

        NavNode targetNode = ResolveNextNode(context.BotId, profile, mesh);
        string moveArgs = string.Create(
            CultureInfo.InvariantCulture,
            $"{targetNode.X:F4},{targetNode.Y:F4},{targetNode.Z:F2}");
        await context.QueueActionAsync("MOVE_TO", moveArgs, cancellationToken);

        if (step is not null && !string.IsNullOrWhiteSpace(step.Zone))
        {
            _ = await context.QueueActionAsync("EXPECT_ZONE", step.Zone, cancellationToken);
        }

        logger.LogDebug(
            "Leveling tick bot {BotId}: profile={Profile} step={Step} targetNode={NodeId}",
            context.BotId,
            profileName,
            step?.Action ?? "none",
            targetNode.Id);
    }

    private BotProfileStep? ResolveStep(BotProfile profile, int level)
    {
        foreach (BotProfileStep step in profile.Steps)
        {
            if (!step.TargetLevel.HasValue || level <= step.TargetLevel.Value)
            {
                return step;
            }
        }

        return profile.Steps.Count > 0 ? profile.Steps[^1] : null;
    }

    private NavNode ResolveNextNode(int botId, BotProfile profile, NavMesh mesh)
    {
        List<int> route = profile.RouteNodeIds
            .Where(id => mesh.Nodes.Any(node => node.Id == id))
            .ToList();

        if (route.Count == 0)
        {
            return mesh.Nodes[0];
        }

        if (!_routeCursorByBot.TryGetValue(botId, out int cursor))
        {
            cursor = 0;
        }

        int clamped = Math.Clamp(cursor, 0, route.Count - 1);
        int nodeId = route[clamped];

        int nextCursor = clamped + 1;
        if (nextCursor >= route.Count)
        {
            nextCursor = 0;
        }

        _routeCursorByBot[botId] = nextCursor;
        return mesh.Nodes.First(node => node.Id == nodeId);
    }
}