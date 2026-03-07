namespace GromitBot.Agent.Wow;

public sealed class WowTelemetry
{
    public string? Name { get; set; }

    public string? Zone { get; set; }

    public int? Level { get; set; }

    public int? Xp { get; set; }

    public int? Hp { get; set; }

    public int? Mana { get; set; }

    public double? BagFillPct { get; set; }

    public double? MapX { get; set; }

    public double? MapY { get; set; }
}