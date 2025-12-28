package dev.th0rgal.mcpanel.bridge.util;

import java.io.BufferedOutputStream;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * Write directly to the raw stdout file descriptor to avoid logger interception.
 * Paper replaces System.out with a logging PrintStream, which causes OSC payloads
 * to be prefixed and stored in latest.log. Writing to the raw FD bypasses that.
 */
public final class RawStdout {

    private static final Object LOCK = new Object();
    private static final OutputStream RAW_OUT = initRawOut();
    private static volatile boolean rawFailed = false;

    private RawStdout() {}

    private static OutputStream initRawOut() {
        try {
            return new BufferedOutputStream(new FileOutputStream(FileDescriptor.out));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Print to raw stdout. Falls back to System.out if raw stdout is unavailable.
     */
    public static void print(String data) {
        if (data == null || data.isEmpty()) {
            return;
        }

        OutputStream out = RAW_OUT;
        if (out == null || rawFailed) {
            System.out.print(data);
            System.out.flush();
            return;
        }

        synchronized (LOCK) {
            try {
                out.write(data.getBytes(StandardCharsets.UTF_8));
                out.flush();
            } catch (IOException e) {
                rawFailed = true;
                System.out.print(data);
                System.out.flush();
            }
        }
    }
}
