package dev.th0rgal.mcpanel.bridge.util;

import dev.th0rgal.mcpanel.bridge.protocol.payloads.CommandTreePayload;
import dev.th0rgal.mcpanel.bridge.protocol.payloads.CommandTreePayload.CommandNode;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.*;

/**
 * Utility for exporting Brigadier command trees to MCPanel format.
 * Platform-specific implementations should extend this with access to their Brigadier API.
 */
public abstract class BrigadierExporter {

    /**
     * Export the full command tree.
     */
    @NotNull
    public abstract CommandTreePayload export();

    /**
     * Get a filtered command tree (only commands matching prefix).
     */
    @NotNull
    public CommandTreePayload export(@NotNull String prefix) {
        CommandTreePayload full = export();
        if (prefix.isEmpty()) {
            return full;
        }

        String lowerPrefix = prefix.toLowerCase();
        Map<String, CommandNode> filtered = new LinkedHashMap<>();

        for (Map.Entry<String, CommandNode> entry : full.commands().entrySet()) {
            if (entry.getKey().toLowerCase().startsWith(lowerPrefix)) {
                filtered.put(entry.getKey(), entry.getValue());
            }
        }

        return new CommandTreePayload(filtered);
    }

    /**
     * Helper method to create a command node with children.
     */
    @NotNull
    protected CommandNode createNode(
            @Nullable String description,
            @Nullable List<String> aliases,
            @Nullable String permission,
            @Nullable String usage,
            @NotNull Map<String, CommandNode> children
    ) {
        return new CommandNode(description, aliases, permission, usage, children.isEmpty() ? null : children);
    }

    /**
     * Helper method to create a leaf command node.
     */
    @NotNull
    protected CommandNode createLeaf(@Nullable String description) {
        return new CommandNode(description);
    }

    /**
     * Helper method to create a leaf command node with aliases.
     */
    @NotNull
    protected CommandNode createLeaf(@Nullable String description, @Nullable List<String> aliases) {
        return new CommandNode(description, aliases);
    }
}
