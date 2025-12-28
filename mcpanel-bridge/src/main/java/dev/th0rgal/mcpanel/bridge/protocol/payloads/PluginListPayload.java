package dev.th0rgal.mcpanel.bridge.protocol.payloads;

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.List;

/**
 * Payload for plugin list responses.
 */
public record PluginListPayload(
        @NotNull List<PluginInfo> plugins
) {
    /**
     * Information about a plugin.
     */
    public record PluginInfo(
            @NotNull String name,
            @NotNull String version,
            boolean enabled,
            @Nullable String description,
            @Nullable List<String> authors,
            @Nullable String website,
            @Nullable List<String> commands,
            @Nullable List<String> dependencies,
            @Nullable List<String> softDependencies
    ) {
        // Simplified constructor
        public PluginInfo(@NotNull String name, @NotNull String version, boolean enabled) {
            this(name, version, enabled, null, null, null, null, null, null);
        }
    }
}
