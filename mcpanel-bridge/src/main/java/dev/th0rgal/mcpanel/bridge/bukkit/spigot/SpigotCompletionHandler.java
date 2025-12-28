package dev.th0rgal.mcpanel.bridge.bukkit.spigot;

import dev.th0rgal.mcpanel.bridge.handler.CompletionHandler;
import dev.th0rgal.mcpanel.bridge.protocol.payloads.CompletionPayload;
import org.bukkit.Bukkit;
import org.bukkit.command.CommandSender;
import org.bukkit.plugin.java.JavaPlugin;
import org.jetbrains.annotations.NotNull;

import java.util.*;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;

/**
 * Spigot fallback completion handler.
 * Uses synchronous Bukkit API - less efficient than Paper's async handler.
 */
public class SpigotCompletionHandler implements CompletionHandler {

    private final JavaPlugin plugin;

    public SpigotCompletionHandler(JavaPlugin plugin) {
        this.plugin = plugin;
    }

    @Override
    public @NotNull CompletableFuture<CompletionPayload> complete(@NotNull String buffer) {
        CompletableFuture<CompletionPayload> future = new CompletableFuture<>();

        // Must run on main thread for Spigot
        Bukkit.getScheduler().runTask(plugin, () -> {
            try {
                List<String> completions = getCompletions(buffer);
                List<CompletionPayload.Completion> result = completions.stream()
                        .map(CompletionPayload.Completion::new)
                        .collect(Collectors.toList());

                future.complete(new CompletionPayload(result, false));
            } catch (Exception e) {
                future.completeExceptionally(e);
            }
        });

        return future;
    }

    /**
     * Get completions using Bukkit's command map.
     */
    private List<String> getCompletions(String buffer) {
        String[] parts = buffer.split(" ", -1);
        if (parts.length == 0) {
            return Collections.emptyList();
        }

        try {
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
                    CommandSender sender = Bukkit.getConsoleSender();
                    return command.tabComplete(sender, commandName, args);
                }
            }
        } catch (Exception e) {
            plugin.getLogger().warning("Completion error: " + e.getMessage());
        }

        return Collections.emptyList();
    }

    @Override
    public boolean isAsync() {
        return false;
    }
}



