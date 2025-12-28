package dev.th0rgal.mcpanel.bridge.protocol;

import com.google.gson.JsonElement;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.List;

/**
 * Unsolicited event message from server to MCPanel.
 */
public class MCPanelEvent extends MCPanelMessage {

    private final String event;
    private final JsonElement payload;

    private MCPanelEvent(@NotNull String event, @Nullable JsonElement payload) {
        this.event = event;
        this.payload = payload;
    }

    @NotNull
    public String getEvent() {
        return event;
    }

    @Nullable
    public JsonElement getPayload() {
        return payload;
    }

    /**
     * Create an event with a payload.
     */
    public static MCPanelEvent create(@NotNull EventType type, @NotNull Object payload) {
        return new MCPanelEvent(type.name().toLowerCase(), GSON.toJsonTree(payload));
    }

    /**
     * Create an event without a payload.
     */
    public static MCPanelEvent create(@NotNull EventType type) {
        return new MCPanelEvent(type.name().toLowerCase(), null);
    }

    /**
     * Create the bridge ready event with feature list.
     */
    public static MCPanelEvent bridgeReady(@NotNull String version, @NotNull String platform, @NotNull List<String> features) {
        return create(EventType.MCPANEL_BRIDGE_READY, new BridgeReadyPayload(version, platform, features));
    }

    /**
     * Create a player join event.
     */
    public static MCPanelEvent playerJoin(@NotNull String name, @NotNull String uuid) {
        return create(EventType.PLAYER_JOIN, new PlayerPayload(name, uuid));
    }

    /**
     * Create a player leave event.
     */
    public static MCPanelEvent playerLeave(@NotNull String name, @NotNull String uuid) {
        return create(EventType.PLAYER_LEAVE, new PlayerPayload(name, uuid));
    }

    public enum EventType {
        /**
         * Bridge is ready and listening for requests.
         */
        MCPANEL_BRIDGE_READY,

        /**
         * Player joined the server.
         */
        PLAYER_JOIN,

        /**
         * Player left the server.
         */
        PLAYER_LEAVE,

        /**
         * A new command was registered (plugin load/reload).
         */
        COMMAND_REGISTERED,

        /**
         * A plugin was loaded or enabled.
         */
        PLUGIN_LOADED,

        /**
         * A plugin was unloaded or disabled.
         */
        PLUGIN_UNLOADED,

        /**
         * Server finished startup.
         */
        SERVER_READY,

        /**
         * Periodic status update (TPS, memory, player count).
         */
        STATUS_UPDATE,

        /**
         * Player list update (periodic broadcast of all players).
         */
        PLAYERS_UPDATE,

        /**
         * Registry update (item IDs, custom data from plugins).
         */
        REGISTRY_UPDATE,

        /**
         * Command tree has been updated (plugins loaded/unloaded).
         * MCPanel should refresh commands.json via SFTP.
         */
        COMMANDS_UPDATED,

        /**
         * System info (static hardware/software info, sent once on startup).
         */
        SYSTEM_INFO
    }

    // Factory methods for new event types

    /**
     * Create a status update event.
     */
    public static MCPanelEvent statusUpdate(@NotNull StatusPayload payload) {
        return create(EventType.STATUS_UPDATE, payload);
    }

    /**
     * Create a players update event.
     */
    public static MCPanelEvent playersUpdate(@NotNull PlayersUpdatePayload payload) {
        return create(EventType.PLAYERS_UPDATE, payload);
    }

    /**
     * Create a registry update event.
     */
    public static MCPanelEvent registryUpdate(@NotNull RegistryPayload payload) {
        return create(EventType.REGISTRY_UPDATE, payload);
    }

    /**
     * Create a commands updated event.
     * Notifies MCPanel that commands.json has been regenerated.
     */
    public static MCPanelEvent commandsUpdated(@NotNull String reason) {
        return create(EventType.COMMANDS_UPDATED, new CommandsUpdatedPayload(reason, System.currentTimeMillis()));
    }

    /**
     * Create a system info event (static hardware/software details).
     */
    public static MCPanelEvent systemInfo(@NotNull SystemInfoPayload payload) {
        return create(EventType.SYSTEM_INFO, payload);
    }

    // Payload records
    public record BridgeReadyPayload(String version, String platform, List<String> features) {}
    public record PlayerPayload(String name, String uuid) {}

    /**
     * Status update payload with TPS, memory, CPU, disk, network metrics.
     * Designed to support gotop-style visualization.
     */
    public record StatusPayload(
            double tps,
            Double mspt,
            int playerCount,
            int maxPlayers,
            long usedMemoryMB,
            long maxMemoryMB,
            long uptimeSeconds,
            // CPU metrics
            Double cpuUsagePercent,      // JVM process CPU usage 0-100
            Double systemCpuPercent,     // System-wide CPU usage 0-100
            List<Double> perCoreCpu,     // Per-core CPU usage (0-100 each)
            Integer threadCount,         // Active thread count
            Integer peakThreadCount,     // Peak thread count since JVM start
            // Disk metrics (may be null if unavailable)
            List<DiskInfo> disks,
            // Network metrics (may be null if unavailable)
            NetworkInfo network
    ) {}

    /**
     * Disk partition info (like gotop's disk usage panel).
     */
    public record DiskInfo(
            String mount,           // Mount point (e.g., "/", "/home")
            String device,          // Device name (e.g., "sda1", "nvme0n1p1")
            long usedBytes,         // Used space in bytes
            long totalBytes,        // Total space in bytes
            double usagePercent     // Usage percentage 0-100
    ) {}

    /**
     * Network I/O info (like gotop's network panel).
     */
    public record NetworkInfo(
            long rxBytes,           // Total bytes received since boot
            long txBytes,           // Total bytes transmitted since boot
            long rxBytesPerSec,     // Current receive rate (bytes/sec)
            long txBytesPerSec      // Current transmit rate (bytes/sec)
    ) {}

    /**
     * Players update payload with list of online players.
     */
    public record PlayersUpdatePayload(
            int count,
            int max,
            List<PlayerInfo> players
    ) {
        public record PlayerInfo(String name, String uuid, String world, int ping) {}
    }

    /**
     * Registry payload for custom values from plugins (e.g., Oraxen item IDs).
     */
    public record RegistryPayload(
            String plugin,
            String type,
            List<String> values
    ) {}

    /**
     * Commands updated payload indicating why the tree was regenerated.
     */
    public record CommandsUpdatedPayload(
            String reason,
            long timestamp
    ) {}

    /**
     * System info payload - static hardware/software details (sent once on startup).
     * Like gotop's header info showing CPU model, core count, etc.
     */
    public record SystemInfoPayload(
            // JVM info
            String javaVersion,         // e.g., "21.0.1"
            String javaVendor,          // e.g., "Eclipse Adoptium"
            String jvmName,             // e.g., "OpenJDK 64-Bit Server VM"
            // Server info
            String serverVersion,       // e.g., "Paper 1.21.4-123"
            String bukkitVersion,       // e.g., "1.21.4-R0.1-SNAPSHOT"
            String minecraftVersion,    // e.g., "1.21.4"
            // OS info
            String osName,              // e.g., "Linux"
            String osVersion,           // e.g., "5.15.0-generic"
            String osArch,              // e.g., "amd64"
            // Hardware info
            String cpuModel,            // e.g., "AMD Ryzen 9 5900X 12-Core Processor"
            int cpuCores,               // Logical processor count
            int cpuPhysicalCores,       // Physical core count (may equal cpuCores if unavailable)
            long totalMemoryMB,         // Total system RAM in MB
            // Network interfaces (for display)
            List<String> networkInterfaces
    ) {}
}
