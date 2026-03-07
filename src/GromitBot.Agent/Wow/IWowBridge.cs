namespace GromitBot.Agent.Wow;

public interface IWowBridge
{
    Task<WowTelemetry?> ReadTelemetryAsync(int botId, CancellationToken cancellationToken);

    Task QueueActionAsync(int botId, WowAction action, CancellationToken cancellationToken);
}