namespace GromitBot.Agent.Modes;

public sealed class FishingMode : IBotMode
{
    public string Name => "fishing";

    public async Task TickAsync(BotModeContext context, CancellationToken cancellationToken)
    {
        await context.QueueActionAsync("CAST", "Fishing", cancellationToken);
    }
}