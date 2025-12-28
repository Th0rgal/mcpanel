package dev.th0rgal.mcpanel.bridge.protocol.payloads;

import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.List;

/**
 * Payload for tab completion responses.
 */
public record CompletionPayload(
        @NotNull List<Completion> completions,
        boolean isAsync
) {
    /**
     * A single completion suggestion.
     */
    public record Completion(
            @NotNull String text,
            @Nullable String tooltip
    ) {
        public Completion(@NotNull String text) {
            this(text, null);
        }
    }
}
