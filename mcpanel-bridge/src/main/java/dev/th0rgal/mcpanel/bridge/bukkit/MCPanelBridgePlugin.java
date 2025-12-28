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

    // Network I/O tracking for rate calculation
    private long lastNetworkCheckTime = 0;
    private long lastRxBytes = 0;
    private long lastTxBytes = 0;

    // CPU usage fallback tracking (process CPU time deltas)
    private long lastProcessCpuTimeNs = -1;
    private long lastProcessCpuSampleTimeNs = -1;
    private List<CpuTimes> lastPerCoreCpuTimes = null;

    // Debug logging toggle (config.yml)
    private boolean debugLogging = false;

    private void sendPlayersUpdateEvent() {
        List<MCPanelEvent.PlayersUpdatePayload.PlayerInfo> players = new ArrayList<>();
        for (Player player : Bukkit.getOnlinePlayers()) {
            players.add(new MCPanelEvent.PlayersUpdatePayload.PlayerInfo(
                    player.getName(),
                    player.getUniqueId().toString(),
                    player.getWorld().getName(),
                    player.getPing()
            ));
        }

        MCPanelEvent.PlayersUpdatePayload payload = new MCPanelEvent.PlayersUpdatePayload(
                players.size(),
                Bukkit.getMaxPlayers(),
                players
        );

        sendEvent(MCPanelEvent.playersUpdate(payload));
    }

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
            sendSystemInfoEvent();
            generateCommandDump();
            exportPluginRegistries();
            sendPlayersUpdateEvent();
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
            sendPlayersUpdateEvent();
        }, STATUS_BROADCAST_INTERVAL, STATUS_BROADCAST_INTERVAL);

        logDebug("Started status broadcaster (interval: " + (STATUS_BROADCAST_INTERVAL / 20) + "s)");
    }

    /**
     * Build the current status payload with comprehensive metrics.
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

        // Collect CPU and thread metrics via JMX
        Double cpuUsage = null;
        Double systemCpu = null;
        List<Double> perCoreCpu = null;
        Integer threadCount = null;
        Integer peakThreadCount = null;

        try {
            java.lang.management.OperatingSystemMXBean osBean =
                    java.lang.management.ManagementFactory.getOperatingSystemMXBean();

            // Try to get process CPU load (requires com.sun.management)
            if (osBean instanceof com.sun.management.OperatingSystemMXBean sunBean) {
                double processCpu = sunBean.getProcessCpuLoad();
                if (processCpu >= 0) {
                    cpuUsage = processCpu * 100.0;
                } else {
                    // Fallback to manual process CPU calculation using cpu time deltas
                    Double fallback = computeProcessCpuFallback(sunBean);
                    if (fallback != null) {
                        cpuUsage = fallback;
                    }
                }

                double sysCpu = sunBean.getSystemCpuLoad();
                if (sysCpu < 0) {
                    sysCpu = sunBean.getCpuLoad();
                }
                if (sysCpu >= 0) {
                    systemCpu = sysCpu * 100.0;
                }
            }
        } catch (Exception e) {
            // CPU metrics not available on this JVM
        }

        // Per-core CPU usage (Linux only via /proc/stat)
        perCoreCpu = collectPerCoreCpuUsage();

        try {
            java.lang.management.ThreadMXBean threadBean =
                    java.lang.management.ManagementFactory.getThreadMXBean();
            threadCount = threadBean.getThreadCount();
            peakThreadCount = threadBean.getPeakThreadCount();
        } catch (Exception e) {
            // Thread metrics not available
        }

        // Collect disk metrics
        List<MCPanelEvent.DiskInfo> disks = collectDiskMetrics();

        // Collect network metrics
        MCPanelEvent.NetworkInfo network = collectNetworkMetrics();

        return new MCPanelEvent.StatusPayload(
                Math.min(tps, 20.0), // Cap at 20 TPS
                mspt,
                Bukkit.getOnlinePlayers().size(),
                Bukkit.getMaxPlayers(),
                usedMemoryMB,
                maxMemoryMB,
                uptimeSeconds,
                cpuUsage,
                systemCpu,
                perCoreCpu,
                threadCount,
                peakThreadCount,
                disks,
                network
        );
    }

    /**
     * Compute process CPU usage from process CPU time deltas.
     * Returns null until at least two samples are available.
     */
    private Double computeProcessCpuFallback(@NotNull com.sun.management.OperatingSystemMXBean sunBean) {
        long processCpuTime = sunBean.getProcessCpuTime(); // ns
        long now = System.nanoTime();

        if (processCpuTime < 0) {
            lastProcessCpuTimeNs = processCpuTime;
            lastProcessCpuSampleTimeNs = now;
            return null;
        }

        Double computed = null;
        if (lastProcessCpuTimeNs > 0 && lastProcessCpuSampleTimeNs > 0) {
            long cpuDelta = processCpuTime - lastProcessCpuTimeNs;
            long timeDelta = now - lastProcessCpuSampleTimeNs;
            if (cpuDelta >= 0 && timeDelta > 0) {
                int cores = Math.max(1, sunBean.getAvailableProcessors());
                double usage = ((double) cpuDelta / (double) timeDelta) / cores * 100.0;
                if (!Double.isNaN(usage) && usage >= 0) {
                    computed = Math.min(usage, 100.0);
                }
            }
        }

        lastProcessCpuTimeNs = processCpuTime;
        lastProcessCpuSampleTimeNs = now;
        return computed;
    }

    private static class CpuTimes {
        final long total;
        final long idle;

        CpuTimes(long total, long idle) {
            this.total = total;
            this.idle = idle;
        }
    }

    private long parseStatValue(@NotNull String value) {
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    /**
     * Collect per-core CPU usage from /proc/stat (Linux only).
     * Returns null if not available (non-Linux or error).
     */
    private List<Double> collectPerCoreCpuUsage() {
        try {
            java.io.File procStat = new java.io.File("/proc/stat");
            if (!procStat.exists()) return null;

            List<CpuTimes> current = new ArrayList<>();

            try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(procStat))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (!line.startsWith("cpu")) continue;
                    if (line.startsWith("cpu ")) continue; // Skip aggregate line

                    String[] parts = line.trim().split("\\s+");
                    if (parts.length < 5) continue;

                    long user = parseStatValue(parts[1]);
                    long nice = parseStatValue(parts[2]);
                    long system = parseStatValue(parts[3]);
                    long idle = parseStatValue(parts[4]);
                    long iowait = parts.length > 5 ? parseStatValue(parts[5]) : 0;
                    long irq = parts.length > 6 ? parseStatValue(parts[6]) : 0;
                    long softirq = parts.length > 7 ? parseStatValue(parts[7]) : 0;
                    long steal = parts.length > 8 ? parseStatValue(parts[8]) : 0;
                    long guest = parts.length > 9 ? parseStatValue(parts[9]) : 0;
                    long guestNice = parts.length > 10 ? parseStatValue(parts[10]) : 0;

                    long total = user + nice + system + idle + iowait + irq + softirq + steal + guest + guestNice;
                    long idleAll = idle + iowait;

                    current.add(new CpuTimes(total, idleAll));
                }
            }

            if (current.isEmpty()) return null;
            if (lastPerCoreCpuTimes == null || lastPerCoreCpuTimes.size() != current.size()) {
                lastPerCoreCpuTimes = current;
                return null;
            }

            List<Double> usage = new ArrayList<>();
            for (int i = 0; i < current.size(); i++) {
                CpuTimes prev = lastPerCoreCpuTimes.get(i);
                CpuTimes now = current.get(i);
                long deltaTotal = now.total - prev.total;
                long deltaIdle = now.idle - prev.idle;
                double percent = 0;
                if (deltaTotal > 0) {
                    percent = ((double) (deltaTotal - deltaIdle) / (double) deltaTotal) * 100.0;
                }
                if (Double.isNaN(percent)) percent = 0;
                percent = Math.max(0, Math.min(100, percent));
                usage.add(percent);
            }

            lastPerCoreCpuTimes = current;
            return usage;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Collect disk usage for mounted filesystems.
     */
    private List<MCPanelEvent.DiskInfo> collectDiskMetrics() {
        List<MCPanelEvent.DiskInfo> disks = new ArrayList<>();

        try {
            // Use Java NIO to get filesystem info
            for (java.nio.file.FileStore store : java.nio.file.FileSystems.getDefault().getFileStores()) {
                try {
                    // Skip pseudo filesystems
                    String type = store.type();
                    if (type.equals("tmpfs") || type.equals("devtmpfs") || type.equals("overlay") ||
                        type.equals("squashfs") || type.startsWith("fuse")) {
                        continue;
                    }

                    long total = store.getTotalSpace();
                    long usable = store.getUsableSpace();
                    long used = total - usable;

                    // Skip tiny or zero-size filesystems
                    if (total < 1024 * 1024 * 100) continue; // Skip < 100MB

                    double usagePercent = total > 0 ? (double) used / total * 100.0 : 0;

                    // Get mount point from store name (format varies by OS)
                    String name = store.name();
                    String mount = store.toString();
                    // Extract mount point from "name (mount)" format
                    int parenIdx = mount.lastIndexOf('(');
                    if (parenIdx > 0) {
                        mount = mount.substring(parenIdx + 1, mount.length() - 1);
                    }

                    disks.add(new MCPanelEvent.DiskInfo(mount, name, used, total, usagePercent));
                } catch (java.io.IOException e) {
                    // Skip this store
                }
            }
        } catch (Exception e) {
            logDebug("Failed to collect disk metrics: " + e.getMessage());
        }

        return disks.isEmpty() ? null : disks;
    }

    /**
     * Collect network I/O metrics.
     * Uses /proc/net/dev on Linux, or falls back to null.
     */
    private MCPanelEvent.NetworkInfo collectNetworkMetrics() {
        try {
            java.io.File procNetDev = new java.io.File("/proc/net/dev");
            if (!procNetDev.exists()) return null;

            long rxBytes = 0;
            long txBytes = 0;

            try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(procNetDev))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    line = line.trim();
                    // Skip header lines
                    if (line.startsWith("Inter") || line.startsWith("face")) continue;

                    // Format: "iface: rx_bytes rx_packets ... tx_bytes tx_packets ..."
                    int colonIdx = line.indexOf(':');
                    if (colonIdx < 0) continue;

                    String iface = line.substring(0, colonIdx).trim();
                    // Skip loopback
                    if (iface.equals("lo")) continue;

                    String[] parts = line.substring(colonIdx + 1).trim().split("\\s+");
                    if (parts.length >= 9) {
                        rxBytes += Long.parseLong(parts[0]);
                        txBytes += Long.parseLong(parts[8]);
                    }
                }
            }

            // Calculate rates
            long now = System.currentTimeMillis();
            long rxBytesPerSec = 0;
            long txBytesPerSec = 0;

            if (lastNetworkCheckTime > 0) {
                long elapsedMs = now - lastNetworkCheckTime;
                if (elapsedMs > 0) {
                    rxBytesPerSec = (rxBytes - lastRxBytes) * 1000 / elapsedMs;
                    txBytesPerSec = (txBytes - lastTxBytes) * 1000 / elapsedMs;
                    // Clamp to non-negative (in case of counter reset)
                    rxBytesPerSec = Math.max(0, rxBytesPerSec);
                    txBytesPerSec = Math.max(0, txBytesPerSec);
                }
            }

            // Update tracking state
            lastNetworkCheckTime = now;
            lastRxBytes = rxBytes;
            lastTxBytes = txBytes;

            return new MCPanelEvent.NetworkInfo(rxBytes, txBytes, rxBytesPerSec, txBytesPerSec);
        } catch (Exception e) {
            logDebug("Failed to collect network metrics: " + e.getMessage());
            return null;
        }
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
     * Send system info event with static hardware/software details.
     */
    private void sendSystemInfoEvent() {
        // JVM info
        String javaVersion = System.getProperty("java.version", "unknown");
        String javaVendor = System.getProperty("java.vendor", "unknown");
        String jvmName = System.getProperty("java.vm.name", "unknown");

        // Server info
        String serverVersion = Bukkit.getVersion();
        String bukkitVersion = Bukkit.getBukkitVersion();
        String minecraftVersion = Bukkit.getMinecraftVersion();

        // OS info
        String osName = System.getProperty("os.name", "unknown");
        String osVersion = System.getProperty("os.version", "unknown");
        String osArch = System.getProperty("os.arch", "unknown");

        // Hardware info
        int cpuCores = Runtime.getRuntime().availableProcessors();
        int cpuPhysicalCores = cpuCores; // May be same or different
        String cpuModel = "unknown";

        // Try to get CPU model from /proc/cpuinfo (Linux) or via JMX
        try {
            java.io.File cpuInfo = new java.io.File("/proc/cpuinfo");
            if (cpuInfo.exists()) {
                try (java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(cpuInfo))) {
                    String line;
                    int physicalIds = 0;
                    java.util.Set<String> seenPhysicalIds = new java.util.HashSet<>();

                    while ((line = reader.readLine()) != null) {
                        if (line.startsWith("model name") && cpuModel.equals("unknown")) {
                            int colonIdx = line.indexOf(':');
                            if (colonIdx > 0) {
                                cpuModel = line.substring(colonIdx + 1).trim();
                            }
                        }
                        if (line.startsWith("physical id")) {
                            int colonIdx = line.indexOf(':');
                            if (colonIdx > 0) {
                                seenPhysicalIds.add(line.substring(colonIdx + 1).trim());
                            }
                        }
                        if (line.startsWith("cpu cores")) {
                            int colonIdx = line.indexOf(':');
                            if (colonIdx > 0) {
                                try {
                                    int cores = Integer.parseInt(line.substring(colonIdx + 1).trim());
                                    cpuPhysicalCores = Math.max(cpuPhysicalCores, cores * Math.max(1, seenPhysicalIds.size()));
                                } catch (NumberFormatException ignored) {}
                            }
                        }
                    }
                    // Adjust for multi-socket systems
                    if (!seenPhysicalIds.isEmpty()) {
                        cpuPhysicalCores = Math.min(cpuPhysicalCores, cpuCores);
                    }
                }
            }
        } catch (Exception e) {
            logDebug("Failed to read CPU info: " + e.getMessage());
        }

        // On macOS, try sysctl
        if (cpuModel.equals("unknown") && osName.toLowerCase().contains("mac")) {
            try {
                Process process = Runtime.getRuntime().exec(new String[]{"sysctl", "-n", "machdep.cpu.brand_string"});
                try (java.io.BufferedReader reader = new java.io.BufferedReader(
                        new java.io.InputStreamReader(process.getInputStream()))) {
                    String line = reader.readLine();
                    if (line != null && !line.isEmpty()) {
                        cpuModel = line.trim();
                    }
                }
            } catch (Exception ignored) {}
        }

        // Total system memory
        long totalMemoryMB = 0;
        try {
            java.lang.management.OperatingSystemMXBean osBean =
                    java.lang.management.ManagementFactory.getOperatingSystemMXBean();
            if (osBean instanceof com.sun.management.OperatingSystemMXBean sunBean) {
                totalMemoryMB = sunBean.getTotalMemorySize() / (1024 * 1024);
            }
        } catch (Exception e) {
            // Fall back to JVM max memory
            totalMemoryMB = Runtime.getRuntime().maxMemory() / (1024 * 1024);
        }

        // Network interfaces
        List<String> networkInterfaces = new ArrayList<>();
        try {
            java.util.Enumeration<java.net.NetworkInterface> nets = java.net.NetworkInterface.getNetworkInterfaces();
            while (nets.hasMoreElements()) {
                java.net.NetworkInterface netIf = nets.nextElement();
                if (netIf.isUp() && !netIf.isLoopback() && !netIf.isVirtual()) {
                    networkInterfaces.add(netIf.getDisplayName());
                }
            }
        } catch (Exception ignored) {}

        MCPanelEvent.SystemInfoPayload payload = new MCPanelEvent.SystemInfoPayload(
                javaVersion,
                javaVendor,
                jvmName,
                serverVersion,
                bukkitVersion,
                minecraftVersion,
                osName,
                osVersion,
                osArch,
                cpuModel,
                cpuCores,
                cpuPhysicalCores,
                totalMemoryMB,
                networkInterfaces
        );

        sendEvent(MCPanelEvent.systemInfo(payload));
        logDebug("System info sent - CPU: " + cpuModel + " (" + cpuCores + " cores)");
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
        sendPlayersUpdateEvent();
    }

    @EventHandler(priority = EventPriority.MONITOR)
    public void onPlayerQuit(PlayerQuitEvent event) {
        Player player = event.getPlayer();
        sendEvent(MCPanelEvent.playerLeave(player.getName(), player.getUniqueId().toString()));
        sendPlayersUpdateEvent();
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
