package dev.th0rgal.mcpanel.bridge.velocity;

import com.google.inject.Inject;
import com.velocitypowered.api.command.CommandManager;
import com.velocitypowered.api.command.CommandMeta;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.connection.DisconnectEvent;
import com.velocitypowered.api.event.connection.PostLoginEvent;
import com.velocitypowered.api.event.proxy.ProxyInitializeEvent;
import com.velocitypowered.api.event.proxy.ProxyShutdownEvent;
import com.velocitypowered.api.plugin.Plugin;
import com.velocitypowered.api.plugin.PluginContainer;
import com.velocitypowered.api.plugin.PluginDescription;
import com.velocitypowered.api.proxy.Player;
import com.velocitypowered.api.proxy.ProxyServer;
import com.velocitypowered.api.proxy.server.RegisteredServer;
import dev.th0rgal.mcpanel.bridge.protocol.*;
import dev.th0rgal.mcpanel.bridge.protocol.payloads.*;
import org.slf4j.Logger;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

/**
 * MCPanel Bridge plugin for Velocity proxy.
 */
@Plugin(
        id = "mcpanel-bridge",
        name = "MCPanel Bridge",
        version = "1.0.1",
        description = "Bridge plugin for MCPanel - Real-time console communication",
        authors = {"Th0rgal"}
)
public class MCPanelBridgeVelocity {

    private static final String VERSION = "1.0.1";

    private final ProxyServer server;
    private final Logger logger;
    private Thread stdinReaderThread;
    private volatile boolean running = true;

    @Inject
    public MCPanelBridgeVelocity(ProxyServer server, Logger logger) {
        this.server = server;
        this.logger = logger;
    }

    @Subscribe
    public void onProxyInitialize(ProxyInitializeEvent event) {
        logger.info("MCPanel Bridge v" + VERSION + " - Platform: Velocity");

        // Start stdin reader for MCPanel requests
        startStdinReader();

        // Send ready event after a short delay
        server.getScheduler().buildTask(this, this::sendBridgeReadyEvent)
                .delay(1, TimeUnit.SECONDS)
                .schedule();
    }

    @Subscribe
    public void onProxyShutdown(ProxyShutdownEvent event) {
        running = false;
        if (stdinReaderThread != null) {
            stdinReaderThread.interrupt();
        }
    }

    /**
     * Send the bridge ready event to MCPanel.
     */
    private void sendBridgeReadyEvent() {
        List<String> features = Arrays.asList(
                "commands",
                "players",
                "plugins",
                "status",
                "servers"
        );

        MCPanelEvent event = MCPanelEvent.bridgeReady(VERSION, "velocity", features);
        sendEvent(event);
        logger.info("Bridge ready - Features: " + features);
    }

    /**
     * Start reading stdin for MCPanel requests.
     */
    private void startStdinReader() {
        stdinReaderThread = new Thread(() -> {
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(System.in))) {
                while (running) {
                    String line = reader.readLine();
                    if (line == null) break;

                    MCPanelRequest request = MCPanelMessage.parseRequest(line);
                    if (request != null) {
                        handleRequest(request);
                    }
                }
            } catch (IOException e) {
                if (running) {
                    logger.warn("Stdin reader error", e);
                }
            }
        }, "MCPanel-StdinReader");

        stdinReaderThread.setDaemon(true);
        stdinReaderThread.start();
    }

    /**
     * Handle an incoming MCPanel request.
     */
    private void handleRequest(MCPanelRequest request) {
        CompletableFuture<MCPanelResponse> future = switch (request.getType()) {
            case COMPLETE -> handleComplete(request);
            case COMMANDS -> handleCommands(request);
            case PLAYERS -> handlePlayers(request);
            case STATUS -> handleStatus(request);
            case PLUGINS -> handlePlugins(request);
            case WORLDS -> handleServers(request); // Velocity uses "servers" instead of "worlds"
            case PING -> CompletableFuture.completedFuture(
                    MCPanelResponse.create(request.getId(), "pong", Map.of("time", System.currentTimeMillis()))
            );
        };

        future.thenAccept(this::sendResponse)
                .exceptionally(e -> {
                    logger.warn("Request handler error", e);
                    sendResponse(MCPanelResponse.error(request.getId(), e.getMessage()));
                    return null;
                });
    }

    /**
     * Handle tab completion request.
     */
    private CompletableFuture<MCPanelResponse> handleComplete(MCPanelRequest request) {
        String buffer = request.getString("buffer");
        if (buffer == null) {
            return CompletableFuture.completedFuture(
                    MCPanelResponse.error(request.getId(), "Missing 'buffer' in payload")
            );
        }

        // Get completions from command manager
        List<String> completions = getCompletions(buffer);
        List<CompletionPayload.Completion> result = completions.stream()
                .map(CompletionPayload.Completion::new)
                .collect(Collectors.toList());

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "completions", new CompletionPayload(result, false))
        );
    }

    /**
     * Get command completions.
     */
    private List<String> getCompletions(String buffer) {
        String[] parts = buffer.split(" ", -1);
        if (parts.length == 0) return Collections.emptyList();

        CommandManager cmdManager = server.getCommandManager();

        if (parts.length == 1) {
            // Complete command name
            String prefix = parts[0].toLowerCase();
            return cmdManager.getAliases().stream()
                    .filter(cmd -> cmd.toLowerCase().startsWith(prefix))
                    .sorted()
                    .limit(50)
                    .collect(Collectors.toList());
        }

        // For arguments, we'd need to use Brigadier suggestions
        // This is more complex in Velocity, return empty for now
        return Collections.emptyList();
    }

    /**
     * Handle command tree request.
     */
    private CompletableFuture<MCPanelResponse> handleCommands(MCPanelRequest request) {
        Map<String, CommandTreePayload.CommandNode> commands = new LinkedHashMap<>();

        CommandManager cmdManager = server.getCommandManager();
        for (String alias : cmdManager.getAliases()) {
            // Skip aliases that contain colons (namespaced)
            if (alias.contains(":")) continue;

            commands.put(alias, new CommandTreePayload.CommandNode(
                    null, // Description not easily available
                    null,
                    null,
                    null,
                    null
            ));
        }

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "command_tree", new CommandTreePayload(commands))
        );
    }

    /**
     * Handle player list request.
     */
    private CompletableFuture<MCPanelResponse> handlePlayers(MCPanelRequest request) {
        List<PlayerListPayload.PlayerInfo> players = new ArrayList<>();

        for (Player player : server.getAllPlayers()) {
            String serverName = player.getCurrentServer()
                    .map(conn -> conn.getServerInfo().getName())
                    .orElse(null);

            players.add(new PlayerListPayload.PlayerInfo(
                    player.getUsername(),
                    player.getUniqueId().toString(),
                    serverName,
                    null, // Display name not easily available
                    20.0, // Health not available on proxy
                    20,   // Food level not available
                    (int) player.getPing(),
                    false, // OP status not available
                    null   // Game mode not available
            ));
        }

        PlayerListPayload payload = new PlayerListPayload(
                players.size(),
                server.getConfiguration().getShowMaxPlayers(),
                players
        );

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "player_list", payload)
        );
    }

    /**
     * Handle server status request.
     */
    private CompletableFuture<MCPanelResponse> handleStatus(MCPanelRequest request) {
        ServerStatusPayload payload = new ServerStatusPayload(
                server.getVersion().getVersion(),
                "Velocity",
                server.getVersion().getName(),
                server.getPlayerCount(),
                server.getConfiguration().getShowMaxPlayers(),
                null, // TPS not applicable to proxy
                null, // MSPT not applicable
                ServerStatusPayload.MemoryInfo.current(),
                null  // Worlds not applicable
        );

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "server_status", payload)
        );
    }

    /**
     * Handle plugins request.
     */
    private CompletableFuture<MCPanelResponse> handlePlugins(MCPanelRequest request) {
        List<PluginListPayload.PluginInfo> plugins = new ArrayList<>();

        for (PluginContainer container : server.getPluginManager().getPlugins()) {
            PluginDescription desc = container.getDescription();

            plugins.add(new PluginListPayload.PluginInfo(
                    desc.getName().orElse(desc.getId()),
                    desc.getVersion().orElse("unknown"),
                    true, // All loaded plugins are "enabled" in Velocity
                    desc.getDescription().orElse(null),
                    desc.getAuthors().isEmpty() ? null : desc.getAuthors(),
                    desc.getUrl().map(Object::toString).orElse(null),
                    null, // Commands not easily accessible
                    desc.getDependencies().stream()
                            .map(dep -> dep.getId())
                            .collect(Collectors.toList()),
                    null  // Soft dependencies
            ));
        }

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "plugin_list", new PluginListPayload(plugins))
        );
    }

    /**
     * Handle servers request (Velocity-specific, replaces "worlds").
     */
    private CompletableFuture<MCPanelResponse> handleServers(MCPanelRequest request) {
        List<Map<String, Object>> servers = new ArrayList<>();

        for (RegisteredServer regServer : server.getAllServers()) {
            Map<String, Object> serverInfo = new LinkedHashMap<>();
            serverInfo.put("name", regServer.getServerInfo().getName());
            serverInfo.put("address", regServer.getServerInfo().getAddress().toString());
            serverInfo.put("players", regServer.getPlayersConnected().size());

            servers.add(serverInfo);
        }

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "servers", Map.of("servers", servers))
        );
    }

    /**
     * Send a response to MCPanel via stdout OSC.
     */
    private void sendResponse(MCPanelResponse response) {
        System.out.print(response.encode());
        System.out.flush();
    }

    /**
     * Send an event to MCPanel via stdout OSC.
     */
    private void sendEvent(MCPanelEvent event) {
        System.out.print(event.encode());
        System.out.flush();
    }

    // Event handlers

    @Subscribe
    public void onPlayerConnect(PostLoginEvent event) {
        Player player = event.getPlayer();
        sendEvent(MCPanelEvent.playerJoin(player.getUsername(), player.getUniqueId().toString()));
    }

    @Subscribe
    public void onPlayerDisconnect(DisconnectEvent event) {
        Player player = event.getPlayer();
        sendEvent(MCPanelEvent.playerLeave(player.getUsername(), player.getUniqueId().toString()));
    }
}
