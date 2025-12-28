package dev.th0rgal.mcpanel.bridge.protocol;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import org.jetbrains.annotations.NotNull;
import org.jetbrains.annotations.Nullable;

import java.util.Base64;

/**
 * Base class for MCPanel protocol messages.
 * Messages are transmitted as OSC escape sequences to avoid interfering with normal console output.
 */
public abstract class MCPanelMessage {

    protected static final Gson GSON = new GsonBuilder()
            .disableHtmlEscaping()
            .create();

    /**
     * OSC sequence prefix for MCPanel messages.
     * Uses iTerm2's custom sequence number (1337) with MCPanel identifier.
     */
    private static final String OSC_PREFIX = "\u001B]1337;MCPanel:";
    private static final String OSC_SUFFIX = "\u0007";

    /**
     * Alternative input marker for requests embedded in stdin.
     * MCPanel sends: ///mcpanel:<base64-json>
     */
    private static final String INPUT_PREFIX = "///mcpanel:";

    /**
     * Encode this message as an OSC escape sequence for stdout.
     * Includes trailing newline to ensure line-buffered output (required by mcwrap).
     */
    @NotNull
    public String encode() {
        String json = GSON.toJson(this);
        String base64 = Base64.getEncoder().encodeToString(json.getBytes());
        return OSC_PREFIX + base64 + OSC_SUFFIX + "\n";
    }

    /**
     * Check if a line contains an MCPanel request.
     */
    public static boolean isRequest(@NotNull String line) {
        return line.startsWith(INPUT_PREFIX);
    }

    /**
     * Parse an MCPanel request from an input line (legacy format with prefix).
     */
    @Nullable
    public static MCPanelRequest parseRequest(@NotNull String line) {
        if (!isRequest(line)) {
            return null;
        }

        try {
            String base64 = line.substring(INPUT_PREFIX.length()).trim();
            return parseRequestBase64(base64);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Parse an MCPanel request from raw base64 data.
     */
    @Nullable
    public static MCPanelRequest parseRequestBase64(@NotNull String base64) {
        try {
            String json = new String(Base64.getDecoder().decode(base64.trim()));
            return GSON.fromJson(json, MCPanelRequest.class);
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Decode an OSC-encoded message (for testing/debugging).
     */
    @Nullable
    public static JsonObject decodeOSC(@NotNull String osc) {
        if (!osc.startsWith(OSC_PREFIX) || !osc.endsWith(OSC_SUFFIX)) {
            return null;
        }

        try {
            String base64 = osc.substring(OSC_PREFIX.length(), osc.length() - OSC_SUFFIX.length());
            String json = new String(Base64.getDecoder().decode(base64));
            return JsonParser.parseString(json).getAsJsonObject();
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Get the raw JSON representation of this message.
     */
    @NotNull
    public String toJson() {
        return GSON.toJson(this);
    }
}
