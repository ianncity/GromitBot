using System.Text.Json.Serialization;

namespace GromitBot.Agent.Bots;

public sealed record BotSnapshot
{
    [JsonPropertyName("bot_id")]
    public int BotId { get; init; }

    [JsonPropertyName("vm_id")]
    public string VmId { get; init; } = "vm1";

    [JsonPropertyName("running")]
    public bool Running { get; init; }

    [JsonPropertyName("name")]
    public string Name { get; init; } = "Unknown";

    [JsonPropertyName("player")]
    public string Player { get; init; } = "Unknown";

    [JsonPropertyName("zone")]
    public string Zone { get; init; } = "Unknown";

    [JsonPropertyName("level")]
    public int Level { get; init; }

    [JsonPropertyName("mode")]
    public string Mode { get; init; } = "unknown";

    [JsonPropertyName("profile")]
    public string? Profile { get; init; }

    [JsonPropertyName("bagFillPct")]
    public double BagFillPct { get; init; }

    [JsonPropertyName("xp")]
    public int Xp { get; init; }

    [JsonPropertyName("hp")]
    public int Hp { get; init; }

    [JsonPropertyName("mana")]
    public int Mana { get; init; }

    [JsonPropertyName("mapX")]
    public double? MapX { get; init; }

    [JsonPropertyName("mapY")]
    public double? MapY { get; init; }

    [JsonPropertyName("error")]
    public string? Error { get; init; }
}