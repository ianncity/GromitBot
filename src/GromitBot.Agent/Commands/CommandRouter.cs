using System.Globalization;
using System.Text.Json;
using GromitBot.Agent.Bots;
using GromitBot.Agent.Configuration;
using GromitBot.Agent.Profiles;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Commands;

public sealed class CommandRouter(
    BotManager botManager,
    ProfileRepository profiles,
    IOptions<AgentOptions> options,
    ILogger<CommandRouter> logger)
{
    private static readonly HashSet<string> ModeNames =
        ["fishing", "herbalism", "leveling"];

    public async Task<object> ExecuteAsync(CommandEnvelope request, CancellationToken cancellationToken)
    {
        string cmd = (request.Cmd ?? string.Empty).Trim().ToUpperInvariant();
        if (string.IsNullOrWhiteSpace(cmd))
        {
            return Error("missing_cmd");
        }

        string secret = options.Value.AuthSecret.Trim();
        if (!string.IsNullOrWhiteSpace(secret) && !string.Equals(secret, request.Auth, StringComparison.Ordinal))
        {
            return Error("unauthorized");
        }

        if (cmd == "LIST")
        {
            return ListPayload();
        }

        if (cmd == "PROFILES")
        {
            return new Dictionary<string, object?>
            {
                ["ok"] = true,
                ["queued"] = "PROFILES",
                ["data"] = profiles.ListProfiles(),
            };
        }

        if (!TryResolveTargets(request, out List<int> targets, out bool broadcast, out string? targetError))
        {
            return Error(targetError ?? "invalid_bot_target");
        }

        switch (cmd)
        {
            case "STATUS":
                return broadcast
                    ? ListPayload()
                    : SingleStatusPayload(targets[0]);

            case "POSITION":
                return broadcast
                    ? ListPayload()
                    : SingleStatusPayload(targets[0]);

            case "START":
                return await ApplyQueuedCommandAsync(
                    targets,
                    broadcast,
                    cmd,
                    static (slot, _, ct) => slot.StartAsync(ct),
                    cancellationToken);

            case "STOP":
                return await ApplyQueuedCommandAsync(
                    targets,
                    broadcast,
                    cmd,
                    static (slot, _, ct) => slot.StopAsync(ct),
                    cancellationToken);

            case "MODE":
            {
                string? mode = request.Args?.Trim().ToLowerInvariant();
                if (string.IsNullOrWhiteSpace(mode) || !ModeNames.Contains(mode))
                {
                    return Error("invalid_mode");
                }

                return await ApplyQueuedCommandAsync(
                    targets,
                    broadcast,
                    cmd,
                    (slot, _, ct) => slot.SetModeAsync(mode, ct),
                    cancellationToken);
            }

            case "PROFILE":
            {
                string? profileName = request.Args?.Trim();
                if (string.IsNullOrWhiteSpace(profileName))
                {
                    return Error("missing_profile");
                }

                if (!profiles.Exists(profileName))
                {
                    return Error("profile_not_found");
                }

                return await ApplyQueuedCommandAsync(
                    targets,
                    broadcast,
                    cmd,
                    (slot, _, ct) => slot.SetProfileAsync(profileName, ct),
                    cancellationToken);
            }

            case "SAY":
            case "WHISPER":
            case "EMOTE":
            case "PRINT":
            case "MAIL":
            case "JUMP":
            case "SIT":
            case "STAND":
            case "RELOAD":
            case "DISCONNECT":
                return await ApplyQueuedCommandAsync(
                    targets,
                    broadcast,
                    cmd,
                    (slot, args, ct) => slot.QueueActionAsync(cmd, args, ct),
                    cancellationToken,
                    request.Args);

            default:
                logger.LogWarning("Unknown command {Command}", cmd);
                return Error("unknown_command");
        }
    }

    private Dictionary<string, object?> SingleStatusPayload(int botId)
    {
        if (!botManager.TryGetSlot(botId, out BotSlot? slot))
        {
            return Error("unknown_bot_slot");
        }

        return new Dictionary<string, object?>
        {
            ["ok"] = true,
            ["bot"] = botId,
            ["data"] = slot.GetSnapshot(),
        };
    }

    private Dictionary<string, object?> ListPayload()
    {
        IReadOnlyList<BotSnapshot> bots = botManager.GetAllSnapshots();
        return new Dictionary<string, object?>
        {
            ["ok"] = true,
            ["data"] = new Dictionary<string, object?>
            {
                ["bot_count"] = bots.Count,
                ["bots"] = bots,
            },
        };
    }

    private async Task<Dictionary<string, object?>> ApplyQueuedCommandAsync(
        IReadOnlyList<int> targets,
        bool broadcast,
        string cmd,
        Func<BotSlot, string?, CancellationToken, Task<bool>> executor,
        CancellationToken cancellationToken,
        string? args = null)
    {
        if (broadcast)
        {
            Dictionary<string, object?> results = [];
            foreach (int target in targets)
            {
                if (!botManager.TryGetSlot(target, out BotSlot? slot))
                {
                    results[target.ToString(CultureInfo.InvariantCulture)] = Error("unknown_bot_slot");
                    continue;
                }

                bool ok = await executor(slot, args, cancellationToken);
                results[target.ToString(CultureInfo.InvariantCulture)] = ok
                    ? new Dictionary<string, object?>
                    {
                        ["ok"] = true,
                        ["queued"] = cmd,
                    }
                    : Error("command_failed");
            }

            return new Dictionary<string, object?>
            {
                ["ok"] = true,
                ["results"] = results,
            };
        }

        int botId = targets[0];
        if (!botManager.TryGetSlot(botId, out BotSlot? singleSlot))
        {
            return Error("unknown_bot_slot");
        }

        bool queued = await executor(singleSlot, args, cancellationToken);
        if (!queued)
        {
            return Error("command_failed");
        }

        return new Dictionary<string, object?>
        {
            ["ok"] = true,
            ["bot"] = botId,
            ["queued"] = cmd,
        };
    }

    private bool TryResolveTargets(
        CommandEnvelope request,
        out List<int> targets,
        out bool broadcast,
        out string? error)
    {
        targets = [];
        broadcast = false;
        error = null;

        if (!request.HasBot)
        {
            if (botManager.BotCount == 1)
            {
                targets.Add(0);
            }
            else
            {
                targets.AddRange(botManager.SlotIds);
                broadcast = true;
            }

            return true;
        }

        JsonElement raw = request.Bot;
        if (raw.ValueKind == JsonValueKind.String)
        {
            string? text = raw.GetString()?.Trim();
            if (string.Equals(text, "all", StringComparison.OrdinalIgnoreCase))
            {
                targets.AddRange(botManager.SlotIds);
                broadcast = true;
                return true;
            }

            if (int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out int slotId))
            {
                return ResolveSingleTarget(slotId, out targets, out error);
            }
        }

        if (raw.ValueKind == JsonValueKind.Number && raw.TryGetInt32(out int numberSlot))
        {
            return ResolveSingleTarget(numberSlot, out targets, out error);
        }

        error = "invalid_bot_target";
        return false;
    }

    private bool ResolveSingleTarget(int slotId, out List<int> targets, out string? error)
    {
        targets = [];
        error = null;

        if (!botManager.TryGetSlot(slotId, out _))
        {
            error = "unknown_bot_slot";
            return false;
        }

        targets.Add(slotId);
        return true;
    }

    private static Dictionary<string, object?> Error(string error) =>
        new()
        {
            ["ok"] = false,
            ["error"] = error,
        };
}