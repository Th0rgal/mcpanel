package dev.th0rgal.mcpanel.bridge.protocol;

import com.google.gson.JsonObject;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

/**
 * Request message from MCPanel to the server.
 */
public class MCPanelRequest {

    private final String id;
    private final RequestType type;
    private final JsonObject payload;

    public MCPanelRequest(@NotNull String id, @NotNull RequestType type, @Nullable JsonObject payload) {
        this.id = id;
        this.type = type;
        this.payload = payload;
    }

    @NotNull
    public String getId() {
        return id;
    }

    @NotNull
    public RequestType getType() {
        return type;
    }

    @Nullable
    public JsonObject getPayload() {
        return payload;
    }

    /**
     * Get a string from the payload.
     */
    @Nullable
    public String getString(@NotNull String key) {
        if (payload == null || !payload.has(key)) {
            return null;
        }
        return payload.get(key).getAsString();
    }

    /**
     * Get an integer from the payload.
     */
    public int getInt(@NotNull String key, int defaultValue) {
        if (payload == null || !payload.has(key)) {
            return defaultValue;
        }
        return payload.get(key).getAsInt();
    }

    public enum RequestType {
        /**
         * Request tab completions for a command buffer.
         * Payload: { "buffer": "oraxen re" }
         */
        COMPLETE,

        /**
         * Request the full command tree (Brigadier structure).
         * No payload required.
         */
        COMMANDS,

        /**
         * Request the current player list.
         * No payload required.
         */
        PLAYERS,

        /**
         * Request server status (TPS, memory, etc).
         * No payload required.
         */
        STATUS,

        /**
         * Request plugin list with metadata.
         * No payload required.
         */
        PLUGINS,

        /**
         * Request world list with statistics.
         * No payload required.
         */
        WORLDS,

        /**
         * Ping request for keepalive.
         * No payload required.
         */
        PING
    }
}
