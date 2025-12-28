package dev.th0rgal.mcpanel.bridge.protocol;

import com.google.gson.JsonElement;
import org.jetbrains.annotations.NotNull;

/**
 * Response message from the server to MCPanel.
 */
public class MCPanelResponse extends MCPanelMessage {

    private final String id;
    private final String type;
    private final JsonElement payload;

    private MCPanelResponse(@NotNull String id, @NotNull String type, @NotNull JsonElement payload) {
        this.id = id;
        this.type = type;
        this.payload = payload;
    }

    @NotNull
    public String getId() {
        return id;
    }

    @NotNull
    public String getType() {
        return type;
    }

    @NotNull
    public JsonElement getPayload() {
        return payload;
    }

    /**
     * Create a response for a request.
     */
    public static MCPanelResponse create(@NotNull String requestId, @NotNull String type, @NotNull Object payload) {
        return new MCPanelResponse(requestId, type, GSON.toJsonTree(payload));
    }

    /**
     * Create an error response.
     */
    public static MCPanelResponse error(@NotNull String requestId, @NotNull String message) {
        return new MCPanelResponse(requestId, "error", GSON.toJsonTree(new ErrorPayload(message)));
    }

    private record ErrorPayload(String message) {}
}
