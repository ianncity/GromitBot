using GromitBot.Agent.Configuration;
using GromitBot.Agent.Inventory;
using GromitBot.Agent.Modes;
using GromitBot.Agent.State;
using GromitBot.Agent.Wow;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Bots;

public sealed class BotManager
{
    private readonly Dictionary<int, BotSlot> _slots = [];
    private readonly StateStore _stateStore;

    public BotManager(
        IOptions<AgentOptions> options,
        IEnumerable<IBotMode> botModes,
        IWowBridge wowBridge,
        InventoryService inventoryService,
        StateStore stateStore,
        TimeProvider timeProvider,
        ILoggerFactory loggerFactory,
        ILogger<BotManager> logger)
    {
        _stateStore = stateStore;

        Dictionary<string, IBotMode> modeMap = botModes.ToDictionary(
            mode => mode.Name,
            StringComparer.OrdinalIgnoreCase);

        int botSlots = Math.Clamp(options.Value.BotSlots, 1, 8);
        string vmId = Environment.MachineName;

        for (int i = 0; i < botSlots; i++)
        {
            BotSlot slot = new(
                i,
                vmId,
                options.Value.DefaultMode,
                wowBridge,
                inventoryService,
                modeMap,
                timeProvider,
                loggerFactory.CreateLogger<BotSlot>());

            _slots[i] = slot;
        }

        Dictionary<int, PersistedBotState> persisted = _stateStore.LoadAll(botSlots);
        foreach ((int slotId, PersistedBotState state) in persisted)
        {
            if (_slots.TryGetValue(slotId, out BotSlot? slot))
            {
                slot.ApplyPersistedState(state);
            }
        }

        logger.LogInformation("Bot manager initialized with {SlotCount} slot(s)", _slots.Count);
    }

    public int BotCount => _slots.Count;

    public IReadOnlyList<int> SlotIds => _slots.Keys.OrderBy(id => id).ToList();

    public bool TryGetSlot(int botId, out BotSlot slot)
    {
        return _slots.TryGetValue(botId, out slot!);
    }

    public IReadOnlyList<BotSnapshot> GetAllSnapshots()
    {
        return _slots.Values
            .Select(slot => slot.GetSnapshot())
            .OrderBy(snapshot => snapshot.BotId)
            .ToList();
    }

    public void SaveAll()
    {
        foreach (BotSlot slot in _slots.Values)
        {
            _stateStore.Save(slot.ToPersistedState());
        }
    }
}