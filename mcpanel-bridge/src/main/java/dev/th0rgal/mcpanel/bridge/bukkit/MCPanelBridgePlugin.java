package dev.th0rgal.mcpanel.bridge.bukkit;

import dev.th0rgal.mcpanel.bridge.bukkit.paper.PaperCompletionHandler;
import dev.th0rgal.mcpanel.bridge.bukkit.paper.PaperBrigadierExporter;
import dev.th0rgal.mcpanel.bridge.bukkit.spigot.SpigotCompletionHandler;
import dev.th0rgal.mcpanel.bridge.handler.CompletionHandler;
import dev.th0rgal.mcpanel.bridge.protocol.*;
import dev.th0rgal.mcpanel.bridge.protocol.payloads.*;
import dev.th0rgal.mcpanel.bridge.util.BrigadierExporter;
import org.bukkit.Bukkit;
import org.bukkit.World;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.event.server.PluginDisableEvent;
import org.bukkit.event.server.PluginEnableEvent;
import org.bukkit.event.server.ServerLoadEvent;
import org.bukkit.plugin.Plugin;
import org.bukkit.plugin.java.JavaPlugin;
import org.jetbrains.annotations.NotNull;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.util.*;
import java.util.Base64;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.logging.Level;
import java.util.stream.Collectors;

/**
 * MCPanel Bridge plugin for Bukkit/Spigot/Paper servers.
 * Provides real-time console communication with MCPanel.
 */
public class MCPanelBridgePlugin extends JavaPlugin implements Listener {

    private static final String VERSION = "1.0.1";

    /**
     * Command name for MCPanel requests.
     * MCPanel sends: mcpanel <base64-json>
     */
    private static final String COMMAND_NAME = "mcpanel";

    private boolean isPaper;
    private boolean isFolia;
    private CompletionHandler completionHandler;
    private BrigadierExporter brigadierExporter;

    // Cached command tree (rebuilt on plugin reload)
    // These fields are accessed from multiple threads (main thread, RCON thread, ForkJoinPool)
    // volatile ensures visibility across threads
    private volatile CommandTreePayload cachedCommandTree;
    private volatile long commandTreeCacheTime = 0;
    private static final long CACHE_TTL = 60_000; // 1 minute
    private final Object cacheLock = new Object();

    // Command dump file location
    private File commandsFile;

    // Registry export folder
    private File registriesFolder;

    // Periodic status broadcast interval (in ticks, 20 ticks = 1 second)
    private static final long STATUS_BROADCAST_INTERVAL = 20 * 10; // Every 10 seconds

    // Server start time for uptime calculation
    private long serverStartTime;

    // Debug logging toggle (config.yml)
    private boolean debugLogging = false;

    @Override
    public void onEnable() {
        // Detect platform
        isPaper = detectPaper();
        isFolia = detectFolia();

        getLogger().info("MCPanel Bridge v" + VERSION + " - Platform: " +
                (isFolia ? "Folia" : isPaper ? "Paper" : "Spigot"));

        // Initialize platform-specific handlers
        if (isPaper) {
            completionHandler = new PaperCompletionHandler(this);
            brigadierExporter = new PaperBrigadierExporter(this);
        } else {
            completionHandler = new SpigotCompletionHandler(this);
            // Spigot doesn't have easy Brigadier access, use plugin.yml parsing
            brigadierExporter = new SpigotBrigadierExporter(this);
        }

        // Ensure config + data folder
        saveDefaultConfig();
        reloadConfig();
        debugLogging = getConfig().getBoolean("debug", false);

        if (!getDataFolder().exists()) {
            getDataFolder().mkdirs();
        }
        commandsFile = new File(getDataFolder(), "commands.json");

        // Create registries subfolder
        registriesFolder = new File(getDataFolder(), "registries");
        if (!registriesFolder.exists()) {
            registriesFolder.mkdirs();
        }

        // Track server start time
        serverStartTime = System.currentTimeMillis();

        // Register event listeners
        getServer().getPluginManager().registerEvents(this, this);

        // Send ready event and generate command dump after server is fully loaded
        scheduleTask(() -> {
            sendBridgeReadyEvent();
            generateCommandDump();
            exportPluginRegistries();
            startStatusBroadcaster();
        }, 40L); // 2 second delay to ensure all plugins are loaded
    }

    @Override
    public void onDisable() {
        // Nothing to clean up
    }

    /**
     * Detect if running on Paper.
     */
    private boolean detectPaper() {
        try {
            Class.forName("com.destroystokyo.paper.event.server.AsyncTabCompleteEvent");
            return true;
        } catch (ClassNotFoundException e) {
            return false;
        }
    }

    /**
     * Detect if running on Folia.
     */
    private boolean detectFolia() {
        try {
            Class.forName("io.papermc.paper.threadedregions.RegionizedServer");
            return true;
        } catch (ClassNotFoundException e) {
            return false;
        }
    }

    /**
     * Schedule a task (Folia-compatible).
     */
    private void scheduleTask(Runnable task, long delayTicks) {
        if (isFolia) {
            // Folia: use global region scheduler
            try {
                Object scheduler = Bukkit.class.getMethod("getGlobalRegionScheduler").invoke(null);
                scheduler.getClass().getMethod("runDelayed", Plugin.class, java.util.function.Consumer.class, long.class)
                        .invoke(scheduler, this, (java.util.function.Consumer<Object>) t -> task.run(), delayTicks);
            } catch (Exception e) {
                getLogger().log(Level.WARNING, "Failed to schedule Folia task", e);
            }
        } else {
            Bukkit.getScheduler().runTaskLater(this, task, delayTicks);
        }
    }

    /**
     * Schedule a repeating task (Folia-compatible).
     */
    private void scheduleRepeatingTask(Runnable task, long delayTicks, long periodTicks) {
        if (isFolia) {
            // Folia: use global region scheduler
            try {
                Object scheduler = Bukkit.class.getMethod("getGlobalRegionScheduler").invoke(null);
                scheduler.getClass().getMethod("runAtFixedRate", Plugin.class, java.util.function.Consumer.class, long.class, long.class)
                        .invoke(scheduler, this, (java.util.function.Consumer<Object>) t -> task.run(), delayTicks, periodTicks);
            } catch (Exception e) {
                getLogger().log(Level.WARNING, "Failed to schedule Folia repeating task", e);
            }
        } else {
            Bukkit.getScheduler().runTaskTimer(this, task, delayTicks, periodTicks);
        }
    }

    /**
     * Generate the command dump file (commands.json) in the plugin's data folder.
     * This file can be fetched by MCPanel via SFTP for offline command completion.
     */
    private void generateCommandDump() {
        try {
            // Export Brigadier command tree
            CommandTreePayload commandTree = brigadierExporter.export();
            synchronized (cacheLock) {
                cachedCommandTree = commandTree;
                commandTreeCacheTime = System.currentTimeMillis();
            }

            // Convert to JSON using Gson
            com.google.gson.Gson gson = new com.google.gson.GsonBuilder()
                    .setPrettyPrinting()
                    .disableHtmlEscaping()
                    .create();
            String json = gson.toJson(commandTree);

            // Write to file
            try (FileWriter writer = new FileWriter(commandsFile)) {
                writer.write(json);
            }

            logDebug("Generated command dump: " + commandsFile.getAbsolutePath() +
                    " (" + commandTree.commands().size() + " commands)");
        } catch (IOException e) {
            getLogger().log(Level.WARNING, "Failed to write command dump", e);
        }
    }

    /**
     * Start the periodic status broadcaster.
     * Sends TPS, memory, and player count every STATUS_BROADCAST_INTERVAL ticks.
     */
    private void startStatusBroadcaster() {
        scheduleRepeatingTask(() -> {
            MCPanelEvent.StatusPayload status = buildStatusPayload();
            sendEvent(MCPanelEvent.statusUpdate(status));
        }, STATUS_BROADCAST_INTERVAL, STATUS_BROADCAST_INTERVAL);

        logDebug("Started status broadcaster (interval: " + (STATUS_BROADCAST_INTERVAL / 20) + "s)");
    }

    /**
     * Build the current status payload.
     */
    private MCPanelEvent.StatusPayload buildStatusPayload() {
        double tps = 20.0;
        Double mspt = null;

        if (isPaper) {
            try {
                double[] tpsArray = (double[]) Bukkit.class.getMethod("getTPS").invoke(null);
                if (tpsArray != null && tpsArray.length > 0) {
                    tps = tpsArray[0]; // 1-minute average
                }
                mspt = (Double) Bukkit.class.getMethod("getAverageTickTime").invoke(null);
            } catch (Exception e) {
                // Ignore - not available
            }
        }

        Runtime runtime = Runtime.getRuntime();
        long usedMemoryMB = (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024);
        long maxMemoryMB = runtime.maxMemory() / (1024 * 1024);
        long uptimeSeconds = (System.currentTimeMillis() - serverStartTime) / 1000;

        return new MCPanelEvent.StatusPayload(
                Math.min(tps, 20.0), // Cap at 20 TPS
                mspt,
                Bukkit.getOnlinePlayers().size(),
                Bukkit.getMaxPlayers(),
                usedMemoryMB,
                maxMemoryMB,
                uptimeSeconds
        );
    }

    /**
     * Export plugin-specific registries to JSON files.
     * These can be used for autocomplete (e.g., Oraxen item IDs).
     */
    private void exportPluginRegistries() {
        // Export Oraxen items if available
        exportOraxenItems();

        // Export ItemsAdder items if available
        exportItemsAdderItems();

        // Could add more plugins here...
    }

    /**
     * Export Oraxen item IDs to registries/oraxen_items.json
     */
    private void exportOraxenItems() {
        try {
            Plugin oraxen = Bukkit.getPluginManager().getPlugin("Oraxen");
            if (oraxen == null || !oraxen.isEnabled()) return;

            // Try to get Oraxen's ItemsRegistry.getNames() via reflection
            Class<?> oraxenItemsClass = Class.forName("io.th0rgal.oraxen.api.OraxenItems");
            @SuppressWarnings("unchecked")
            Set<String> itemIds = (Set<String>) oraxenItemsClass.getMethod("getNames").invoke(null);

            if (itemIds != null && !itemIds.isEmpty()) {
                List<String> sortedIds = new ArrayList<>(itemIds);
                Collections.sort(sortedIds);

                // Write to file
                writeRegistryFile("oraxen_items.json", sortedIds);

                // Also send as OSC event for real-time updates
                sendEvent(MCPanelEvent.registryUpdate(
                        new MCPanelEvent.RegistryPayload("oraxen", "items", sortedIds)
                ));

                logDebug("Exported " + sortedIds.size() + " Oraxen items");
            }
        } catch (ClassNotFoundException e) {
            // Oraxen not installed - ignore
        } catch (Exception e) {
            getLogger().log(Level.FINE, "Could not export Oraxen items: " + e.getMessage());
        }
    }

    /**
     * Export ItemsAdder item IDs to registries/itemsadder_items.json
     */
    private void exportItemsAdderItems() {
        try {
            Plugin itemsAdder = Bukkit.getPluginManager().getPlugin("ItemsAdder");
            if (itemsAdder == null || !itemsAdder.isEnabled()) return;

            // Try to get ItemsAdder items via reflection
            Class<?> customStackClass = Class.forName("dev.lone.itemsadder.api.CustomStack");
            @SuppressWarnings("unchecked")
            List<String> itemIds = (List<String>) customStackClass.getMethod("getNamespacedIdsInRegistry").invoke(null);

            if (itemIds != null && !itemIds.isEmpty()) {
                List<String> sortedIds = new ArrayList<>(itemIds);
                Collections.sort(sortedIds);

                // Write to file
                writeRegistryFile("itemsadder_items.json", sortedIds);

                // Also send as OSC event
                sendEvent(MCPanelEvent.registryUpdate(
                        new MCPanelEvent.RegistryPayload("itemsadder", "items", sortedIds)
                ));

                logDebug("Exported " + sortedIds.size() + " ItemsAdder items");
            }
        } catch (ClassNotFoundException e) {
            // ItemsAdder not installed - ignore
        } catch (Exception e) {
            getLogger().log(Level.FINE, "Could not export ItemsAdder items: " + e.getMessage());
        }
    }

    /**
     * Write a registry file to the registries folder.
     */
    private void writeRegistryFile(String filename, List<String> values) {
        try {
            File file = new File(registriesFolder, filename);
            com.google.gson.Gson gson = new com.google.gson.GsonBuilder()
                    .setPrettyPrinting()
                    .create();
            try (FileWriter writer = new FileWriter(file)) {
                gson.toJson(Map.of("values", values, "timestamp", System.currentTimeMillis()), writer);
            }
        } catch (IOException e) {
            getLogger().log(Level.WARNING, "Failed to write registry file: " + filename, e);
        }
    }

    /**
     * Send the bridge ready event to MCPanel.
     */
    private void sendBridgeReadyEvent() {
        List<String> features = new ArrayList<>();
        features.add("commands");
        features.add("players");
        features.add("plugins");
        features.add("status");
        features.add("worlds");

        if (isPaper) {
            features.add("async_complete");
            features.add("brigadier");
            features.add("rich_tooltips");
            features.add("tps");
            features.add("mspt");
        }

        MCPanelEvent event = MCPanelEvent.bridgeReady(
                VERSION,
                isFolia ? "folia" : isPaper ? "paper" : "spigot",
                features
        );

        sendEvent(event);
        logDebug("Bridge ready - Features: " + features);
    }

    /**
     * Handle the /mcpanel command (registered in plugin.yml).
     * Format: mcpanel <base64-json>
     *
     * When called via RCON, sender.sendMessage() returns directly to RCON client.
     * This provides synchronous request-response without depending on stdout/PTY.
     */
    @Override
    public boolean onCommand(@NotNull CommandSender sender, @NotNull Command command, @NotNull String label, String[] args) {
        if (args.length > 0) {
            // Join args in case base64 got split somehow
            String base64 = String.join("", args);
            MCPanelRequest request = MCPanelMessage.parseRequestBase64(base64);
            if (request != null) {
                handleRequest(request, sender);
            } else {
                sender.sendMessage("§c[MCPanel] Invalid request format");
            }
        }
        return true;  // Always return true to suppress any error messages
    }

    /**
     * Handle an incoming MCPanel request.
     * Response is sent via sender.sendMessage() for RCON compatibility.
     * We block and wait for the result to ensure RCON gets the response.
     */
    private void handleRequest(@NotNull MCPanelRequest request, @NotNull CommandSender sender) {
        CompletableFuture<MCPanelResponse> future = switch (request.getType()) {
            case COMPLETE -> handleComplete(request);
            case COMMANDS -> handleCommands(request);
            case PLAYERS -> handlePlayers(request);
            case STATUS -> handleStatus(request);
            case PLUGINS -> handlePlugins(request);
            case WORLDS -> handleWorlds(request);
            case PING -> CompletableFuture.completedFuture(
                    MCPanelResponse.create(request.getId(), "pong", Map.of("time", System.currentTimeMillis()))
            );
        };

        try {
            // Block and wait for the response (with 5 second timeout)
            // This ensures RCON gets the response before the connection closes
            MCPanelResponse response = future.get(5, TimeUnit.SECONDS);
            String encoded = encodeRCONResponse(response);
            sender.sendMessage(encoded);
        } catch (TimeoutException e) {
            sender.sendMessage(encodeRCONResponse(MCPanelResponse.error(request.getId(), "Request timed out")));
        } catch (Exception e) {
            sender.sendMessage(encodeRCONResponse(MCPanelResponse.error(request.getId(), e.getMessage())));
        }
    }

    /**
     * Encode a response for RCON transmission.
     * Format: MCPANEL:<base64-json>
     * This is simpler than OSC since RCON doesn't need escape sequences.
     */
    private String encodeRCONResponse(@NotNull MCPanelResponse response) {
        String json = response.toJson();
        String base64 = Base64.getEncoder().encodeToString(json.getBytes());
        return "MCPANEL:" + base64;
    }

    /**
     * Handle tab completion request.
     */
    private CompletableFuture<MCPanelResponse> handleComplete(@NotNull MCPanelRequest request) {
        String buffer = request.getString("buffer");
        if (buffer == null) {
            return CompletableFuture.completedFuture(
                    MCPanelResponse.error(request.getId(), "Missing 'buffer' in payload")
            );
        }

        return completionHandler.complete(buffer)
                .thenApply(payload -> MCPanelResponse.create(request.getId(), "completions", payload));
    }

    /**
     * Handle command tree request.
     */
    private CompletableFuture<MCPanelResponse> handleCommands(@NotNull MCPanelRequest request) {
        // Use cached tree if fresh (volatile reads ensure visibility)
        long now = System.currentTimeMillis();
        CommandTreePayload cached = cachedCommandTree;
        long cacheTime = commandTreeCacheTime;

        if (cached != null && (now - cacheTime) < CACHE_TTL) {
            return CompletableFuture.completedFuture(
                    MCPanelResponse.create(request.getId(), "command_tree", cached)
            );
        }

        // Rebuild cache (synchronized to prevent concurrent rebuilds)
        return CompletableFuture.supplyAsync(() -> {
            synchronized (cacheLock) {
                // Double-check: another thread may have rebuilt while we waited
                if (cachedCommandTree != null && (System.currentTimeMillis() - commandTreeCacheTime) < CACHE_TTL) {
                    return MCPanelResponse.create(request.getId(), "command_tree", cachedCommandTree);
                }
                CommandTreePayload newTree = brigadierExporter.export();
                cachedCommandTree = newTree;
                commandTreeCacheTime = System.currentTimeMillis();
                return MCPanelResponse.create(request.getId(), "command_tree", newTree);
            }
        });
    }

    /**
     * Handle player list request.
     */
    private CompletableFuture<MCPanelResponse> handlePlayers(@NotNull MCPanelRequest request) {
        List<PlayerListPayload.PlayerInfo> players = new ArrayList<>();

        for (Player player : Bukkit.getOnlinePlayers()) {
            players.add(new PlayerListPayload.PlayerInfo(
                    player.getName(),
                    player.getUniqueId().toString(),
                    player.getWorld().getName(),
                    player.getDisplayName(),
                    player.getHealth(),
                    player.getFoodLevel(),
                    player.getPing(),
                    player.isOp(),
                    player.getGameMode().name().toLowerCase()
            ));
        }

        PlayerListPayload payload = new PlayerListPayload(
                players.size(),
                Bukkit.getMaxPlayers(),
                players
        );

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "player_list", payload)
        );
    }

    /**
     * Handle server status request.
     */
    private CompletableFuture<MCPanelResponse> handleStatus(@NotNull MCPanelRequest request) {
        double[] tps = null;
        Double mspt = null;

        if (isPaper) {
            try {
                // Paper provides TPS and MSPT
                tps = (double[]) Bukkit.class.getMethod("getTPS").invoke(null);
                mspt = (Double) Bukkit.class.getMethod("getAverageTickTime").invoke(null);
            } catch (Exception e) {
                // Ignore - not available
            }
        }

        List<ServerStatusPayload.WorldInfo> worlds = new ArrayList<>();
        for (World world : Bukkit.getWorlds()) {
            worlds.add(new ServerStatusPayload.WorldInfo(
                    world.getName(),
                    world.getPlayers().size(),
                    world.getEntities().size(),
                    world.getLoadedChunks().length,
                    world.getEnvironment().name().toLowerCase()
            ));
        }

        ServerStatusPayload payload = new ServerStatusPayload(
                Bukkit.getMinecraftVersion(),
                Bukkit.getName(),
                Bukkit.getBukkitVersion(),
                Bukkit.getOnlinePlayers().size(),
                Bukkit.getMaxPlayers(),
                tps,
                mspt,
                ServerStatusPayload.MemoryInfo.current(),
                worlds
        );

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "server_status", payload)
        );
    }

    /**
     * Handle plugin list request.
     */
    private CompletableFuture<MCPanelResponse> handlePlugins(@NotNull MCPanelRequest request) {
        List<PluginListPayload.PluginInfo> plugins = new ArrayList<>();

        for (Plugin plugin : Bukkit.getPluginManager().getPlugins()) {
            var desc = plugin.getDescription();

            List<String> commands = desc.getCommands() != null
                    ? new ArrayList<>(desc.getCommands().keySet())
                    : null;

            plugins.add(new PluginListPayload.PluginInfo(
                    plugin.getName(),
                    desc.getVersion(),
                    plugin.isEnabled(),
                    desc.getDescription(),
                    desc.getAuthors(),
                    desc.getWebsite(),
                    commands,
                    desc.getDepend(),
                    desc.getSoftDepend()
            ));
        }

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "plugin_list", new PluginListPayload(plugins))
        );
    }

    /**
     * Handle worlds request.
     */
    private CompletableFuture<MCPanelResponse> handleWorlds(@NotNull MCPanelRequest request) {
        List<ServerStatusPayload.WorldInfo> worlds = Bukkit.getWorlds().stream()
                .map(world -> new ServerStatusPayload.WorldInfo(
                        world.getName(),
                        world.getPlayers().size(),
                        world.getEntities().size(),
                        world.getLoadedChunks().length,
                        world.getEnvironment().name().toLowerCase()
                ))
                .collect(Collectors.toList());

        return CompletableFuture.completedFuture(
                MCPanelResponse.create(request.getId(), "worlds", Map.of("worlds", worlds))
        );
    }

    /**
     * Send a response to MCPanel via stdout OSC.
     */
    private void sendResponse(@NotNull MCPanelResponse response) {
        System.out.print(response.encode());
        System.out.flush();
    }

    /**
     * Send an event to MCPanel via stdout OSC.
     */
    public void sendEvent(@NotNull MCPanelEvent event) {
        System.out.print(event.encode());
        System.out.flush();
    }

    private void logDebug(@NotNull String message) {
        if (debugLogging) {
            getLogger().info(message);
        }
    }

    // Event handlers for real-time updates

    @EventHandler(priority = EventPriority.MONITOR)
    public void onPlayerJoin(PlayerJoinEvent event) {
        Player player = event.getPlayer();
        sendEvent(MCPanelEvent.playerJoin(player.getName(), player.getUniqueId().toString()));
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onPlayerQuit(PlayerQuitEvent event) {
        Player player = event.getPlayer();
        sendEvent(MCPanelEvent.playerLeave(player.getName(), player.getUniqueId().toString()));
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onServerLoad(ServerLoadEvent event) {
        // Regenerate command dump when server reloads (new plugins/commands may be available)
        scheduleTask(() -> {
            generateCommandDump();
            sendEvent(MCPanelEvent.create(MCPanelEvent.EventType.SERVER_READY));
        }, 20L); // Short delay to ensure all plugins finished loading
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onPluginEnable(PluginEnableEvent event) {
        // Skip our own enable event (already handled in onEnable)
        if (event.getPlugin() == this) return;

        String pluginName = event.getPlugin().getName();
        logDebug("Plugin enabled: " + pluginName + " - regenerating command tree");

        // Delay to let the plugin finish registering commands
        scheduleTask(() -> {
            generateCommandDump();
            sendEvent(MCPanelEvent.commandsUpdated("plugin_enabled:" + pluginName));
        }, 20L); // 1 second delay
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onPluginDisable(PluginDisableEvent event) {
        // Skip our own disable event
        if (event.getPlugin() == this) return;

        String pluginName = event.getPlugin().getName();
        logDebug("Plugin disabled: " + pluginName + " - regenerating command tree");

        // Delay to let command unregistration complete
        scheduleTask(() -> {
            generateCommandDump();
            sendEvent(MCPanelEvent.commandsUpdated("plugin_disabled:" + pluginName));
        }, 20L); // 1 second delay
    }

    /**
     * Simple Spigot Brigadier exporter that uses plugin.yml data.
     */
    private static class SpigotBrigadierExporter extends BrigadierExporter {
        private final MCPanelBridgePlugin plugin;

        public SpigotBrigadierExporter(MCPanelBridgePlugin plugin) {
            this.plugin = plugin;
        }

        @Override
        public @NotNull CommandTreePayload export() {
            Map<String, CommandTreePayload.CommandNode> commands = new LinkedHashMap<>();

            for (Plugin p : Bukkit.getPluginManager().getPlugins()) {
                var desc = p.getDescription();
                if (desc.getCommands() == null) continue;

                for (var entry : desc.getCommands().entrySet()) {
                    String name = entry.getKey();
                    var cmdInfo = entry.getValue();

                    String description = cmdInfo.get("description") instanceof String d ? d : null;
                    @SuppressWarnings("unchecked")
                    List<String> aliases = cmdInfo.get("aliases") instanceof List<?> l
                            ? l.stream().map(Object::toString).toList()
                            : null;
                    String usage = cmdInfo.get("usage") instanceof String u ? u : null;
                    String permission = cmdInfo.get("permission") instanceof String perm ? perm : null;

                    commands.put(name, new CommandTreePayload.CommandNode(
                            description, aliases, permission, usage, null
                    ));
                }
            }

            return new CommandTreePayload(commands);
        }
    }
}
