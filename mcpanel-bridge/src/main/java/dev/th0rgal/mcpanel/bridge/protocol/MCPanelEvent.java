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
        COMMANDS_UPDATED
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

    // Payload records
    public record BridgeReadyPayload(String version, String platform, List<String> features) {}
    public record PlayerPayload(String name, String uuid) {}

    /**
     * Status update payload with TPS, memory, and basic info.
     */
    public record StatusPayload(
            double tps,
            Double mspt,
            int playerCount,
            int maxPlayers,
            long usedMemoryMB,
            long maxMemoryMB,
            long uptimeSeconds
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
}
