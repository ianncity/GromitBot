using GromitBot.Agent.Wow;

namespace GromitBot.Agent.Modes;

public sealed class BotModeContext(
    int botId,
    string? profile,
    int level,
    string zone,
    double? mapX,
    double? mapY,
    Func<WowAction, CancellationToken, Task<bool>> queueActionAsync)
{
    public int BotId { get; } = botId;

    public string? Profile { get; } = profile;

    public int Level { get; } = level;

    public string Zone { get; } = zone;

    public double? MapX { get; } = mapX;

    public double? MapY { get; } = mapY;

    public Task<bool> QueueActionAsync(string command, string? args, CancellationToken cancellationToken)
    {
        return queueActionAsync(new WowAction(command, args), cancellationToken);
    }
}