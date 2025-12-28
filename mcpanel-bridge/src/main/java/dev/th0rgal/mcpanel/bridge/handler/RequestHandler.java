package dev.th0rgal.mcpanel.bridge.handler;

import dev.th0rgal.mcpanel.bridge.protocol.MCPanelRequest;
import dev.th0rgal.mcpanel.bridge.protocol.MCPanelResponse;
import org.jetbrains.annotations.NotNull;

import java.util.concurrent.CompletableFuture;

/**
 * Interface for handling MCPanel requests.
 */
public interface RequestHandler {

    /**
     * Handle a request and return a response.
     *
     * @param request The incoming request
     * @return A future that completes with the response
     */
    @NotNull
    CompletableFuture<MCPanelResponse> handle(@NotNull MCPanelRequest request);

    /**
     * Check if this handler can handle the given request type.
     */
    boolean canHandle(@NotNull MCPanelRequest.RequestType type);
}
