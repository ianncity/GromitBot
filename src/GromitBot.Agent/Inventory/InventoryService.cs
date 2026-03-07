using GromitBot.Agent.Wow;

namespace GromitBot.Agent.Inventory;

public sealed class InventoryService
{
    public double ComputeBagFill(WowTelemetry telemetry)
    {
        if (telemetry.BagFillPct is null)
        {
            return 0;
        }

        return Math.Clamp(telemetry.BagFillPct.Value, 0, 100);
    }
}