package dev.th0rgal.mcpanel.bridge.protocol.payloads;

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.List;

/**
 * Payload for server status responses.
 */
public record ServerStatusPayload(
        @NotNull String version,
        @NotNull String software,
        @Nullable String softwareVersion,
        int onlinePlayers,
        int maxPlayers,
        @Nullable double[] tps,
        @Nullable Double mspt,
        @NotNull MemoryInfo memory,
        @Nullable List<WorldInfo> worlds
) {
    /**
     * Memory usage information.
     */
    public record MemoryInfo(
            long used,
            long max,
            long free
    ) {
        public static MemoryInfo current() {
            Runtime runtime = Runtime.getRuntime();
            long max = runtime.maxMemory() / 1024 / 1024;
            long total = runtime.totalMemory() / 1024 / 1024;
            long free = runtime.freeMemory() / 1024 / 1024;
            long used = total - free;
            return new MemoryInfo(used, max, max - used);
        }
    }

    /**
     * Information about a world.
     */
    public record WorldInfo(
            @NotNull String name,
            int players,
            int entities,
            int loadedChunks,
            @Nullable String environment
    ) {}
}
