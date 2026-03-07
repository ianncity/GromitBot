namespace GromitBot.Agent.State;

public sealed class PersistedBotState
{
    public int BotId { get; set; }

    public string Mode { get; set; } = "leveling";

    public string? Profile { get; set; }

    public string Name { get; set; } = "Unknown";

    public string Zone { get; set; } = "Unknown";

    public int Level { get; set; }

    public int Xp { get; set; }

    public int Hp { get; set; }

    public int Mana { get; set; }

    public double BagFillPct { get; set; }

    public double? MapX { get; set; }

    public double? MapY { get; set; }
}