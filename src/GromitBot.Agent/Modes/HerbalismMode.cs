namespace GromitBot.Agent.Modes;

public sealed class HerbalismMode : IBotMode
{
    public string Name => "herbalism";

    public async Task TickAsync(BotModeContext context, CancellationToken cancellationToken)
    {
        await context.QueueActionAsync("TARGET_NEAREST_HERB", null, cancellationToken);
        await context.QueueActionAsync("INTERACT_TARGET", null, cancellationToken);
    }
}