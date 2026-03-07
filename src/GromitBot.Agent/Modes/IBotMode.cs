namespace GromitBot.Agent.Modes;

public interface IBotMode
{
    string Name { get; }

    Task TickAsync(BotModeContext context, CancellationToken cancellationToken);
}