using System.Text.Json;
using System.Text.Json.Serialization;

namespace GromitBot.Agent.Commands;

public sealed class CommandEnvelope
{
    [JsonPropertyName("cmd")]
    public string? Cmd { get; set; }

    [JsonPropertyName("args")]
    public string? Args { get; set; }

    [JsonPropertyName("auth")]
    public string? Auth { get; set; }

    [JsonPropertyName("bot")]
    public JsonElement Bot { get; set; }

    [JsonIgnore]
    public bool HasBot =>
        Bot.ValueKind is not JsonValueKind.Undefined and not JsonValueKind.Null;
}