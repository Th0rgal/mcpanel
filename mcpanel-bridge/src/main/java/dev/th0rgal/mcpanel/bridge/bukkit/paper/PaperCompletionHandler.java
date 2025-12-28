package dev.th0rgal.mcpanel.bridge.bukkit.paper;

import com.destroystokyo.paper.event.server.AsyncTabCompleteEvent;
import dev.th0rgal.mcpanel.bridge.handler.CompletionHandler;
import dev.th0rgal.mcpanel.bridge.protocol.payloads.CompletionPayload;
import org.bukkit.Bukkit;
import org.bukkit.command.CommandSender;
import org.bukkit.event.EventHandler;
import org.bukkit.event.EventPriority;
import org.bukkit.event.Listener;
import org.bukkit.plugin.java.JavaPlugin;
import org.jetbrains.annotations.NotNull;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

/**
 * Paper-specific completion handler using AsyncTabCompleteEvent.
 * Provides real-time, async tab completions with rich tooltips.
 */
public class PaperCompletionHandler implements CompletionHandler, Listener {

    private final JavaPlugin plugin;

    // Pending completion requests waiting for AsyncTabCompleteEvent
    private final Map<String, CompletableFuture<CompletionPayload>> pendingRequests = new ConcurrentHashMap<>();

    public PaperCompletionHandler(JavaPlugin plugin) {
        this.plugin = plugin;
        Bukkit.getPluginManager().registerEvents(this, plugin);
    }

    @Override
    public @NotNull CompletableFuture<CompletionPayload> complete(@NotNull String buffer) {
        // Execute directly - RCON runs on its own thread and we need immediate response
        // The command map is thread-safe for reads
        try {
            List<String> completions = getCompletionsFromCommandMap(buffer);
            List<CompletionPayload.Completion> result = completions.stream()
                    .map(CompletionPayload.Completion::new)
                    .collect(Collectors.toList());
            return CompletableFuture.completedFuture(new CompletionPayload(result, true));
        } catch (Exception e) {
            plugin.getLogger().warning("Completion error: " + e.getMessage());
            return CompletableFuture.completedFuture(new CompletionPayload(Collections.emptyList(), true));
        }
    }

    /**
     * Get completions directly from Bukkit's command map.
     */
    private List<String> getCompletionsFromCommandMap(String buffer) {
        try {
            // Remove leading slash if present
            String cleanBuffer = buffer.startsWith("/") ? buffer.substring(1) : buffer;

            // Parse the buffer into command and args
            String[] parts = cleanBuffer.split(" ", -1);
            if (parts.length == 0) {
                return Collections.emptyList();
            }

            // Get command map
            var commandMap = Bukkit.getCommandMap();

            if (parts.length == 1) {
                // Completing command name
                String prefix = parts[0].toLowerCase();
                return commandMap.getKnownCommands().keySet().stream()
                        .map(cmd -> {
                            if (cmd == null) return null;
                            if (cmd.contains(":")) {
                                String[] p = cmd.split(":", 2);
                                if (p.length == 2 && "minecraft".equalsIgnoreCase(p[0])) return null;
                                return p.length == 2 ? p[1] : cmd;
                            }
                            return cmd;
                        })
                        .filter(Objects::nonNull)
                        .filter(cmd -> cmd.toLowerCase().startsWith(prefix))
                        .distinct()
                        .sorted()
                        .limit(50)
                        .collect(Collectors.toList());
            } else {
                // Completing arguments
                String commandName = parts[0].toLowerCase();
                var command = commandMap.getCommand(commandName);
                if (command == null) {
                    // Some plugins register only namespaced entries (plugin:cmd). Try to resolve by suffix.
                    for (String key : commandMap.getKnownCommands().keySet()) {
                        if (key == null) continue;
                        if (key.equalsIgnoreCase(commandName) || key.toLowerCase().endsWith(":" + commandName)) {
                            command = commandMap.getKnownCommands().get(key);
                            break;
                        }
                    }
                }
                if (command != null) {
                    String[] args = Arrays.copyOfRange(parts, 1, parts.length);
                    // Use console sender for tab complete
                    CommandSender sender = Bukkit.getConsoleSender();
                    return command.tabComplete(sender, commandName, args);
                }
            }
        } catch (Exception e) {
            plugin.getLogger().warning("Completion error: " + e.getMessage());
        }

        return Collections.emptyList();
    }

    /**
     * Listen for AsyncTabCompleteEvent to capture completions with tooltips.
     */
    @EventHandler(priority = EventPriority.MONITOR)
    public void onAsyncTabComplete(AsyncTabCompleteEvent event) {
        // Only handle console completions
        if (!(event.getSender() instanceof org.bukkit.command.ConsoleCommandSender)) {
            return;
        }

        // If we have pending requests, complete them with rich data
        if (!pendingRequests.isEmpty()) {
            List<CompletionPayload.Completion> completions = event.completions().stream()
                    .map(c -> new CompletionPayload.Completion(
                            c.suggestion(),
                            c.tooltip() != null ? c.tooltip().toString() : null
                    ))
                    .collect(Collectors.toList());

            // Complete all pending requests (there should only be one)
            for (var entry : pendingRequests.entrySet()) {
                entry.getValue().complete(new CompletionPayload(completions, true));
            }
            pendingRequests.clear();
        }
    }

    @Override
    public boolean isAsync() {
        return true;
    }
}
