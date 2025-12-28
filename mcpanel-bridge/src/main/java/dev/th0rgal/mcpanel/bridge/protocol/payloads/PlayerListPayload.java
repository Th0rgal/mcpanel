package dev.th0rgal.mcpanel.bridge.protocol.payloads;

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.List;

/**
 * Payload for player list responses.
 */
public record PlayerListPayload(
        int count,
        int max,
        @NotNull List<PlayerInfo> players
) {
    /**
     * Information about a player.
     */
    public record PlayerInfo(
            @NotNull String name,
            @NotNull String uuid,
            @Nullable String world,
            @Nullable String displayName,
            double health,
            int foodLevel,
            int ping,
            boolean op,
            @Nullable String gameMode
    ) {
        // Simplified constructor for proxies (less info available)
        public PlayerInfo(@NotNull String name, @NotNull String uuid, int ping) {
            this(name, uuid, null, null, 20.0, 20, ping, false, null);
        }
    }
}
