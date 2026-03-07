using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using GromitBot.Agent.Configuration;
using GromitBot.Agent.Infrastructure;
using Microsoft.Extensions.Options;

namespace GromitBot.Agent.Commands;

public sealed class CommandServer(
    IOptions<AgentOptions> options,
    CommandRouter router,
    ILogger<CommandServer> logger) : BackgroundService
{
    private TcpListener? _listener;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        AgentOptions cfg = options.Value;
        int port = Math.Clamp(cfg.Port, 1, 65535);
        IPAddress bindIp = ResolveBindIp(cfg.BindHost);

        _listener = new TcpListener(bindIp, port);
        _listener.Start();
        logger.LogInformation("Command server listening on {Host}:{Port}", bindIp, port);

        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                TcpClient client = await _listener.AcceptTcpClientAsync(stoppingToken);
                _ = Task.Run(() => HandleClientAsync(client, stoppingToken), stoppingToken);
            }
        }
        catch (OperationCanceledException)
        {
            logger.LogInformation("Command server stopping");
        }
        finally
        {
            _listener.Stop();
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken stoppingToken)
    {
        using (client)
        await using (NetworkStream network = client.GetStream())
        using (StreamReader reader = new(network, Encoding.UTF8, false, 4096, leaveOpen: true))
        using (StreamWriter writer = new(network, new UTF8Encoding(false), 4096, leaveOpen: true)
        {
            AutoFlush = true,
            NewLine = "\n",
        })
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                string? line;
                try
                {
                    line = await reader.ReadLineAsync().WaitAsync(stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    return;
                }

                if (line is null)
                {
                    return;
                }

                object response;
                try
                {
                    CommandEnvelope? request =
                        JsonSerializer.Deserialize<CommandEnvelope>(line, JsonDefaults.Options);

                    if (request is null || string.IsNullOrWhiteSpace(request.Cmd))
                    {
                        response = Error("invalid_request");
                    }
                    else
                    {
                        response = await router.ExecuteAsync(request, stoppingToken);
                    }
                }
                catch (JsonException ex)
                {
                    logger.LogWarning(ex, "Invalid JSON command payload");
                    response = Error("invalid_json");
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Command dispatch failed");
                    response = Error("internal_error");
                }

                string payload = JsonSerializer.Serialize(response, JsonDefaults.Options);
                await writer.WriteAsync(payload.AsMemory(), stoppingToken);
                await writer.WriteAsync("\n".AsMemory(), stoppingToken);
            }
        }
    }

    private static Dictionary<string, object?> Error(string error) =>
        new()
        {
            ["ok"] = false,
            ["error"] = error,
        };

    private static IPAddress ResolveBindIp(string host)
    {
        if (string.IsNullOrWhiteSpace(host) || host == "0.0.0.0")
        {
            return IPAddress.Any;
        }

        if (host == "::")
        {
            return IPAddress.IPv6Any;
        }

        if (IPAddress.TryParse(host, out IPAddress? parsed))
        {
            return parsed;
        }

        IPAddress[] addresses = Dns.GetHostAddresses(host);
        return addresses.FirstOrDefault() ?? IPAddress.Any;
    }
}