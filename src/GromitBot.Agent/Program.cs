using GromitBot.Agent.Bots;
using GromitBot.Agent.Commands;
using GromitBot.Agent.Configuration;
using GromitBot.Agent.Inventory;
using GromitBot.Agent.Modes;
using GromitBot.Agent.Nav;
using GromitBot.Agent.Profiles;
using GromitBot.Agent.State;
using GromitBot.Agent.Wow;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);

builder.Services.AddWindowsService(options =>
{
	options.ServiceName = "GromitBotAgent";
});

builder.Services.Configure<AgentOptions>(
	builder.Configuration.GetSection(AgentOptions.SectionName));

builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<StateStore>();
builder.Services.AddSingleton<InventoryService>();
builder.Services.AddSingleton<NavMeshRepository>();
builder.Services.AddSingleton<ProfileRepository>();

builder.Services.AddSingleton<AddonIpcBridge>();
builder.Services.AddSingleton<MemoryInputBridge>();
builder.Services.AddSingleton<IWowBridge, CompositeWowBridge>();

builder.Services.AddSingleton<IBotMode, FishingMode>();
builder.Services.AddSingleton<IBotMode, HerbalismMode>();
builder.Services.AddSingleton<IBotMode, LevelingMode>();

builder.Services.AddSingleton<BotManager>();
builder.Services.AddSingleton<CommandRouter>();

builder.Services.AddHostedService<CommandServer>();
builder.Services.AddHostedService<SnapshotService>();

IHost host = builder.Build();
host.Run();
