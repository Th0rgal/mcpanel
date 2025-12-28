package dev.th0rgal.mcpanel.bridge.handler;

import dev.th0rgal.mcpanel.bridge.protocol.payloads.CompletionPayload;
import org.jetbrains.annotations.NotNull;

import java.util.concurrent.CompletableFuture;

/**
 * Interface for handling tab completion requests.
 * Implementations differ between Paper (async) and Spigot (sync).
 */
public interface CompletionHandler {

    /**
     * Get completions for a command buffer.
     *
     * @param buffer The current input buffer (e.g., "oraxen re")
     * @return A future that completes with completion suggestions
     */
    @NotNull
    CompletableFuture<CompletionPayload> complete(@NotNull String buffer);

    /**
     * Check if this handler supports async completions (Paper).
     */
    boolean isAsync();
}
