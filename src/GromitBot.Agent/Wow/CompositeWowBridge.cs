namespace GromitBot.Agent.Wow;

public sealed class CompositeWowBridge(
    AddonIpcBridge addonBridge,
    MemoryInputBridge memoryBridge,
    ILogger<CompositeWowBridge> logger) : IWowBridge
{
    public async Task<WowTelemetry?> ReadTelemetryAsync(int botId, CancellationToken cancellationToken)
    {
        WowTelemetry? telemetry = await addonBridge.ReadTelemetryAsync(botId, cancellationToken);
        if (telemetry is not null)
        {
            return telemetry;
        }

        return await memoryBridge.ReadTelemetryAsync(botId, cancellationToken);
    }

    public async Task QueueActionAsync(int botId, WowAction action, CancellationToken cancellationToken)
    {
        try
        {
            await addonBridge.QueueActionAsync(botId, action, cancellationToken);
        }
        catch (Exception ex)
        {
            logger.LogDebug(ex, "Addon IPC write failed for bot {BotId}", botId);
        }

        await memoryBridge.QueueActionAsync(botId, action, cancellationToken);
    }
}