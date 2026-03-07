using GromitBot.Agent.Configuration;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Bots;

public sealed class SnapshotService(
    BotManager botManager,
    IOptions<AgentOptions> options,
    ILogger<SnapshotService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        int intervalSeconds = Math.Max(options.Value.SnapshotIntervalSeconds, 1);

        logger.LogInformation("Snapshot service started (interval: {Seconds}s)", intervalSeconds);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                botManager.SaveAll();
                await Task.Delay(TimeSpan.FromSeconds(intervalSeconds), stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            botManager.SaveAll();
            logger.LogInformation("Snapshot service stopped");
        }
    }
}