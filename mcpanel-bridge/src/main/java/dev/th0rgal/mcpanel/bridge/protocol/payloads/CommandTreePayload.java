package dev.th0rgal.mcpanel.bridge.protocol.payloads;

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.List;
import java.util.Map;

/**
 * Payload for command tree responses.
 */
public record CommandTreePayload(
        @NotNull Map<String, CommandNode> commands
) {
    /**
     * A node in the command tree.
     * Can represent either a literal (subcommand) or an argument.
     */
    public record CommandNode(
            @Nullable String description,
            @Nullable List<String> aliases,
            @Nullable String permission,
            @Nullable String usage,
            @Nullable Map<String, CommandNode> children,
            @Nullable String type,           // "literal" or argument type (e.g., "integer", "string", "player", "entity")
            @Nullable Boolean required,      // Whether this argument is required
            @Nullable List<String> examples  // Example values for this argument
    ) {
        // Convenience constructor for literals (subcommands)
        public CommandNode(@Nullable String description) {
            this(description, null, null, null, null, "literal", null, null);
        }

        public CommandNode(@Nullable String description, @Nullable List<String> aliases) {
            this(description, aliases, null, null, null, "literal", null, null);
        }

        // Full constructor without type info (backwards compatible)
        public CommandNode(
                @Nullable String description,
                @Nullable List<String> aliases,
                @Nullable String permission,
                @Nullable String usage,
                @Nullable Map<String, CommandNode> children
        ) {
            this(description, aliases, permission, usage, children, "literal", null, null);
        }

        public CommandNode withChildren(@NotNull Map<String, CommandNode> children) {
            return new CommandNode(description, aliases, permission, usage, children, type, required, examples);
        }

        // Factory for argument nodes
        public static CommandNode argument(
                @NotNull String type,
                @Nullable Boolean required,
                @Nullable List<String> examples,
                @Nullable Map<String, CommandNode> children
        ) {
            return new CommandNode(null, null, null, null, children, type, required, examples);
        }
    }
}
