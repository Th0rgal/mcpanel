package dev.th0rgal.mcpanel.bridge.util;

import org.jetbrains.annotations.NotNull;

import java.util.Base64;

/**
 * Utility for encoding MCPanel messages as OSC escape sequences.
 */
public final class OSCEncoder {

    private static final String OSC_PREFIX = "\u001B]1337;MCPanel:";
    private static final String OSC_SUFFIX = "\u0007";

    private OSCEncoder() {}

    /**
     * Encode a JSON string as an OSC escape sequence.
     */
    @NotNull
    public static String encode(@NotNull String json) {
        String base64 = Base64.getEncoder().encodeToString(json.getBytes());
        return OSC_PREFIX + base64 + OSC_SUFFIX;
    }

    /**
     * Send an OSC-encoded message to stdout.
     * This writes directly to System.out to bypass any logging framework.
     */
    public static void send(@NotNull String json) {
        RawStdout.print(encode(json));
    }

    /**
     * Decode an OSC-encoded message back to JSON.
     */
    @NotNull
    public static String decode(@NotNull String osc) throws IllegalArgumentException {
        if (!osc.startsWith(OSC_PREFIX) || !osc.endsWith(OSC_SUFFIX)) {
            throw new IllegalArgumentException("Invalid OSC format");
        }
        String base64 = osc.substring(OSC_PREFIX.length(), osc.length() - OSC_SUFFIX.length());
        return new String(Base64.getDecoder().decode(base64));
    }

    /**
     * Check if a string is an OSC-encoded MCPanel message.
     */
    public static boolean isOSC(@NotNull String str) {
        return str.startsWith(OSC_PREFIX) && str.endsWith(OSC_SUFFIX);
    }
}
