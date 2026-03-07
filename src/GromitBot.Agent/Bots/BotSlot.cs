using GromitBot.Agent.Inventory;
using GromitBot.Agent.Modes;
using GromitBot.Agent.State;
using GromitBot.Agent.Wow;

namespace GromitBot.Agent.Bots;

public sealed class BotSlot
{
    private readonly int _botId;
    private readonly IWowBridge _wowBridge;
    private readonly InventoryService _inventoryService;
    private readonly IReadOnlyDictionary<string, IBotMode> _modes;
    private readonly TimeProvider _timeProvider;
    private readonly ILogger<BotSlot> _logger;

    private readonly object _stateLock = new();
    private readonly SemaphoreSlim _lifecycleLock = new(1, 1);

    private BotSnapshot _state;
    private CancellationTokenSource? _runCts;
    private Task? _runTask;

    public BotSlot(
        int botId,
        string vmId,
        string defaultMode,
        IWowBridge wowBridge,
        InventoryService inventoryService,
        IReadOnlyDictionary<string, IBotMode> modes,
        TimeProvider timeProvider,
        ILogger<BotSlot> logger)
    {
        _botId = botId;
        _wowBridge = wowBridge;
        _inventoryService = inventoryService;
        _modes = modes;
        _timeProvider = timeProvider;
        _logger = logger;

        string normalizedMode = NormalizeMode(defaultMode);
        _state = new BotSnapshot
        {
            BotId = botId,
            VmId = vmId,
            Running = false,
            Name = $"Bot{botId}",
            Player = $"Bot{botId}",
            Zone = "Unknown",
            Level = 1,
            Mode = normalizedMode,
            Profile = null,
            BagFillPct = 0,
            Xp = 0,
            Hp = 0,
            Mana = 0,
        };
    }

    public BotSnapshot GetSnapshot()
    {
        lock (_stateLock)
        {
            return _state with { };
        }
    }

    public async Task<bool> StartAsync(CancellationToken cancellationToken)
    {
        await _lifecycleLock.WaitAsync(cancellationToken);
        try
        {
            if (_runTask is { IsCompleted: false })
            {
                return true;
            }

            _runCts = new CancellationTokenSource();
            SetState(snapshot => snapshot with
            {
                Running = true,
                Error = null,
            });

            _runTask = Task.Run(() => RunLoopAsync(_runCts.Token), CancellationToken.None);
            return true;
        }
        finally
        {
            _lifecycleLock.Release();
        }
    }

    public async Task<bool> StopAsync(CancellationToken cancellationToken)
    {
        Task? runTask;

        await _lifecycleLock.WaitAsync(cancellationToken);
        try
        {
            if (_runTask is null || _runTask.IsCompleted)
            {
                SetState(snapshot => snapshot with
                {
                    Running = false,
                });
                return true;
            }

            _runCts?.Cancel();
            runTask = _runTask;
        }
        finally
        {
            _lifecycleLock.Release();
        }

        try
        {
            if (runTask is not null)
            {
                await runTask.WaitAsync(cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
        }

        SetState(snapshot => snapshot with
        {
            Running = false,
        });

        return true;
    }

    public Task<bool> SetModeAsync(string mode, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        string normalized = NormalizeMode(mode);
        if (!_modes.ContainsKey(normalized))
        {
            return Task.FromResult(false);
        }

        SetState(snapshot => snapshot with
        {
            Mode = normalized,
            Error = null,
        });

        return Task.FromResult(true);
    }

    public Task<bool> SetProfileAsync(string profileName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        SetState(snapshot => snapshot with
        {
            Profile = profileName,
            Error = null,
        });
        return Task.FromResult(true);
    }

    public async Task<bool> QueueActionAsync(string command, string? args, CancellationToken cancellationToken)
    {
        try
        {
            await _wowBridge.QueueActionAsync(_botId, new WowAction(command, args), cancellationToken);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to queue action {Command} for bot {BotId}", command, _botId);
            SetState(snapshot => snapshot with
            {
                Error = "action_queue_failed",
            });
            return false;
        }
    }

    public void ApplyPersistedState(PersistedBotState persisted)
    {
        if (persisted.BotId != _botId)
        {
            return;
        }

        SetState(snapshot => snapshot with
        {
            Running = false,
            Mode = NormalizeMode(persisted.Mode),
            Profile = persisted.Profile,
            Name = persisted.Name,
            Player = persisted.Name,
            Zone = persisted.Zone,
            Level = persisted.Level,
            Xp = persisted.Xp,
            Hp = persisted.Hp,
            Mana = persisted.Mana,
            BagFillPct = persisted.BagFillPct,
            MapX = persisted.MapX,
            MapY = persisted.MapY,
        });
    }

    public PersistedBotState ToPersistedState()
    {
        BotSnapshot snapshot = GetSnapshot();
        return new PersistedBotState
        {
            BotId = snapshot.BotId,
            Mode = snapshot.Mode,
            Profile = snapshot.Profile,
            Name = snapshot.Name,
            Zone = snapshot.Zone,
            Level = snapshot.Level,
            Xp = snapshot.Xp,
            Hp = snapshot.Hp,
            Mana = snapshot.Mana,
            BagFillPct = snapshot.BagFillPct,
            MapX = snapshot.MapX,
            MapY = snapshot.MapY,
        };
    }

    private async Task RunLoopAsync(CancellationToken cancellationToken)
    {
        DateTimeOffset nextModeTick = _timeProvider.GetUtcNow();

        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                WowTelemetry? telemetry = await _wowBridge.ReadTelemetryAsync(_botId, cancellationToken);
                if (telemetry is not null)
                {
                    ApplyTelemetry(telemetry);
                }

                BotSnapshot snapshot = GetSnapshot();
                DateTimeOffset now = _timeProvider.GetUtcNow();

                if (snapshot.Running && now >= nextModeTick && _modes.TryGetValue(snapshot.Mode, out IBotMode? mode))
                {
                    BotModeContext context = new(
                        snapshot.BotId,
                        snapshot.Profile,
                        snapshot.Level,
                        snapshot.Zone,
                        snapshot.MapX,
                        snapshot.MapY,
                        QueueModeActionAsync);
                    await mode.TickAsync(context, cancellationToken);
                    nextModeTick = now.AddSeconds(2);
                }

                await Task.Delay(500, cancellationToken);
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Bot loop failed for slot {BotId}", _botId);
            SetState(snapshot => snapshot with
            {
                Error = "bot_loop_failed",
            });
        }
        finally
        {
            SetState(snapshot => snapshot with
            {
                Running = false,
            });
        }
    }

    private async Task<bool> QueueModeActionAsync(WowAction action, CancellationToken cancellationToken)
    {
        return await QueueActionAsync(action.Command, action.Args, cancellationToken);
    }

    private void ApplyTelemetry(WowTelemetry telemetry)
    {
        SetState(snapshot => snapshot with
        {
            Name = telemetry.Name ?? snapshot.Name,
            Player = telemetry.Name ?? snapshot.Player,
            Zone = telemetry.Zone ?? snapshot.Zone,
            Level = telemetry.Level ?? snapshot.Level,
            Xp = telemetry.Xp ?? snapshot.Xp,
            Hp = telemetry.Hp ?? snapshot.Hp,
            Mana = telemetry.Mana ?? snapshot.Mana,
            BagFillPct = _inventoryService.ComputeBagFill(telemetry),
            MapX = ClampMapCoordinate(telemetry.MapX) ?? snapshot.MapX,
            MapY = ClampMapCoordinate(telemetry.MapY) ?? snapshot.MapY,
            Error = null,
        });
    }

    private void SetState(Func<BotSnapshot, BotSnapshot> update)
    {
        lock (_stateLock)
        {
            _state = update(_state);
        }
    }

    private static double? ClampMapCoordinate(double? value)
    {
        if (value is null)
        {
            return null;
        }

        return Math.Clamp(value.Value, 0.0, 1.0);
    }

    private string NormalizeMode(string mode)
    {
        string normalized = mode.Trim().ToLowerInvariant();
        return _modes.ContainsKey(normalized) ? normalized : "leveling";
    }
}