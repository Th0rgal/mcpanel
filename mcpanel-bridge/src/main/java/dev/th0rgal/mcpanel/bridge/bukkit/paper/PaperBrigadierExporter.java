package dev.th0rgal.mcpanel.bridge.bukkit.paper;

import com.mojang.brigadier.arguments.*;
import com.mojang.brigadier.tree.ArgumentCommandNode;
import com.mojang.brigadier.tree.CommandNode;
import com.mojang.brigadier.tree.LiteralCommandNode;
import dev.th0rgal.mcpanel.bridge.protocol.payloads.CommandTreePayload;
import dev.th0rgal.mcpanel.bridge.util.BrigadierExporter;
import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.plugin.java.JavaPlugin;
import org.jetbrains.annotations.NotNull;

import java.lang.reflect.Method;
import java.util.*;

/**
 * Paper-specific Brigadier exporter with full command tree access.
 * Exports literals (subcommands) and arguments with their types.
 */
public class PaperBrigadierExporter extends BrigadierExporter {

    private final JavaPlugin plugin;

    // Maximum depth for tree export (prevents infinite recursion)
    private static final int MAX_DEPTH = 6;

    public PaperBrigadierExporter(JavaPlugin plugin) {
        this.plugin = plugin;
    }

    @Override
    public @NotNull CommandTreePayload export() {
        Map<String, CommandTreePayload.CommandNode> commands = new LinkedHashMap<>();

        try {
            // Try to access Brigadier dispatcher via Paper's API
            var dispatcher = getBrigadierDispatcher();
            if (dispatcher != null) {
                CommandNode<?> root = dispatcher.getRoot();

                for (CommandNode<?> child : root.getChildren()) {
                    if (child instanceof LiteralCommandNode<?> literal) {
                        String name = normalizeRootName(literal.getName());
                        if (name == null) continue;
                        if (commands.containsKey(name)) continue;

                        // Get command description from Bukkit
                        Command bukkitCmd = Bukkit.getCommandMap().getCommand(name);
                        String description = bukkitCmd != null ? bukkitCmd.getDescription() : null;
                        List<String> aliases = bukkitCmd != null ? bukkitCmd.getAliases() : null;

                        // Export children (subcommands/arguments) with full depth
                        Map<String, CommandTreePayload.CommandNode> children;
                        try {
                            children = exportChildren(literal, 0);
                        } catch (Throwable t) {
                            // Don't let one broken node kill the whole export
                            plugin.getLogger().fine("Failed to export children for " + name + ": " + t.getMessage());
                            children = Collections.emptyMap();
                        }

                        commands.put(name, new CommandTreePayload.CommandNode(
                                description,
                                aliases,
                                null, // permission - not easily accessible
                                bukkitCmd != null ? bukkitCmd.getUsage() : null,
                                children.isEmpty() ? null : children,
                                "literal",
                                null,
                                null
                        ));
                    }
                }
            }
        } catch (Exception e) {
            plugin.getLogger().warning("Failed to export Brigadier tree: " + e.getMessage());
        }

        // Fallback: also include commands from plugin.yml that might not be in Brigadier
        try {
            Set<String> seen = new HashSet<>();
            for (Command cmd : Bukkit.getCommandMap().getKnownCommands().values()) {
                if (cmd == null) continue;
                String name = normalizeRootName(cmd.getName());
                if (name == null) continue;
                if (!seen.add(name)) continue;
                if (commands.containsKey(name)) continue;

                commands.put(name, new CommandTreePayload.CommandNode(
                        cmd.getDescription(),
                        cmd.getAliases(),
                        cmd.getPermission(),
                        cmd.getUsage(),
                        null
                ));
            }
        } catch (Throwable t) {
            plugin.getLogger().fine("Fallback command-map export failed: " + t.getMessage());
        }

        return new CommandTreePayload(commands);
    }

    /**
     * Normalize a Brigadier/Bukkit command name.
     * - If namespaced, keep the suffix unless it's minecraft: (to avoid duplicates)
     * - Returns null if the command should be skipped.
     */
    private String normalizeRootName(@NotNull String rawName) {
        String name = rawName;
        if (name.contains(":")) {
            String[] parts = name.split(":", 2);
            if (parts.length == 2) {
                String ns = parts[0];
                String suffix = parts[1];
                if ("minecraft".equalsIgnoreCase(ns)) {
                    return null;
                }
                name = suffix;
            }
        }
        if (name.isEmpty() || name.contains(":")) return null;
        return name;
    }

    /**
     * Get Brigadier dispatcher via reflection (Paper API).
     */
    @SuppressWarnings("unchecked")
    private com.mojang.brigadier.CommandDispatcher<?> getBrigadierDispatcher() {
        try {
            // Paper 1.20.4+: Bukkit.getCommandMap().getKnownCommands() includes Brigadier
            // Try CraftServer.getServer().getCommands().getDispatcher()
            Object craftServer = Bukkit.getServer();
            Method getHandle = craftServer.getClass().getMethod("getServer");
            Object minecraftServer = getHandle.invoke(craftServer);

            // Get command dispatcher
            Method getCommands = minecraftServer.getClass().getMethod("getCommands");
            Object commands = getCommands.invoke(minecraftServer);

            Method getDispatcher = commands.getClass().getMethod("getDispatcher");
            return (com.mojang.brigadier.CommandDispatcher<?>) getDispatcher.invoke(commands);
        } catch (Exception e) {
            plugin.getLogger().fine("Could not access Brigadier dispatcher: " + e.getMessage());
            return null;
        }
    }

    /**
     * Recursively export children of a command node (literals and arguments).
     */
    private Map<String, CommandTreePayload.CommandNode> exportChildren(CommandNode<?> node, int depth) {
        // Limit depth to avoid massive trees
        if (depth > MAX_DEPTH) return Collections.emptyMap();

        Map<String, CommandTreePayload.CommandNode> children = new LinkedHashMap<>();

        for (CommandNode<?> child : node.getChildren()) {
            if (child instanceof LiteralCommandNode<?> literal) {
                // Literal node (subcommand like "reload", "give", etc.)
                String name = literal.getName();
                Map<String, CommandTreePayload.CommandNode> grandchildren = exportChildren(child, depth + 1);

                children.put(name, new CommandTreePayload.CommandNode(
                        null,
                        null,
                        null,
                        null,
                        grandchildren.isEmpty() ? null : grandchildren,
                        "literal",
                        null,
                        null
                ));
            } else if (child instanceof ArgumentCommandNode<?, ?> argument) {
                // Argument node (like <player>, <amount>, etc.)
                String name = argument.getName();
                String type = getArgumentType(argument);
                List<String> examples = getArgumentExamples(argument);
                Map<String, CommandTreePayload.CommandNode> grandchildren = exportChildren(child, depth + 1);

                // Use angle brackets for argument names to distinguish from literals
                String displayName = "<" + name + ">";

                children.put(displayName, new CommandTreePayload.CommandNode(
                        null,
                        null,
                        null,
                        null,
                        grandchildren.isEmpty() ? null : grandchildren,
                        type,
                        null, // Never evaluate requirements here; Paper may deref permission context and NPE.
                        examples.isEmpty() ? null : examples
                ));
            }
        }

        return children;
    }

    /**
     * Extract the argument type from a Brigadier ArgumentCommandNode.
     */
    @NotNull
    private String getArgumentType(ArgumentCommandNode<?, ?> argument) {
        ArgumentType<?> type = argument.getType();

        // Check standard Brigadier types
        if (type instanceof IntegerArgumentType) {
            return "integer";
        } else if (type instanceof LongArgumentType) {
            return "long";
        } else if (type instanceof FloatArgumentType) {
            return "float";
        } else if (type instanceof DoubleArgumentType) {
            return "double";
        } else if (type instanceof BoolArgumentType) {
            return "boolean";
        } else if (type instanceof StringArgumentType stringArg) {
            return switch (stringArg.getType()) {
                case SINGLE_WORD -> "word";
                case QUOTABLE_PHRASE -> "string";
                case GREEDY_PHRASE -> "greedy_string";
            };
        }

        // Try to get type name from class name for Minecraft-specific types
        String typeName = type.getClass().getSimpleName();

        // Map common Minecraft argument types to friendly names
        return switch (typeName) {
            case "EntityArgument" -> "entity";
            case "GameProfileArgument" -> "player";
            case "BlockPosArgument" -> "block_pos";
            case "Vec3Argument" -> "position";
            case "Vec2Argument" -> "position_2d";
            case "BlockStateArgument" -> "block";
            case "ItemArgument" -> "item";
            case "ColorArgument" -> "color";
            case "ComponentArgument" -> "component";
            case "MessageArgument" -> "message";
            case "NbtCompoundTagArgument" -> "nbt";
            case "NbtPathArgument" -> "nbt_path";
            case "ObjectiveArgument" -> "objective";
            case "ObjectiveCriteriaArgument" -> "criteria";
            case "OperationArgument" -> "operation";
            case "ParticleArgument" -> "particle";
            case "AngleArgument" -> "angle";
            case "RotationArgument" -> "rotation";
            case "ScoreboardSlotArgument" -> "scoreboard_slot";
            case "ScoreHolderArgument" -> "score_holder";
            case "SwizzleArgument" -> "swizzle";
            case "TeamArgument" -> "team";
            case "TimeArgument" -> "time";
            case "UuidArgument" -> "uuid";
            case "ResourceLocationArgument" -> "resource_location";
            case "ResourceKeyArgument" -> "resource_key";
            case "DimensionArgument" -> "dimension";
            case "GameModeArgument" -> "gamemode";
            case "HeightmapTypeArgument" -> "heightmap";
            case "TemplateRotationArgument" -> "template_rotation";
            case "TemplateMirrorArgument" -> "template_mirror";
            default -> typeName.replace("Argument", "").toLowerCase();
        };
    }

    /**
     * Get example values for an argument type.
     * First tries the standard Brigadier getExamples() API (which plugins can override),
     * then falls back to hardcoded defaults for known types.
     */
    @NotNull
    private List<String> getArgumentExamples(ArgumentCommandNode<?, ?> argument) {
        ArgumentType<?> type = argument.getType();

        // First, try Brigadier's standard getExamples() method.
        // Well-implemented plugins (like Oraxen) can provide their own completions this way.
        Collection<String> nativeExamples = type.getExamples();
        if (nativeExamples != null && !nativeExamples.isEmpty()) {
            // Return up to 100 examples to avoid massive payloads
            return nativeExamples.stream().limit(100).toList();
        }

        // Fall back to hardcoded examples for standard Brigadier types
        if (type instanceof IntegerArgumentType) {
            return List.of("0", "1", "10", "64");
        } else if (type instanceof DoubleArgumentType || type instanceof FloatArgumentType) {
            return List.of("0.0", "1.0", "0.5");
        } else if (type instanceof BoolArgumentType) {
            return List.of("true", "false");
        }

        // Get type name for Minecraft-specific examples
        String typeName = type.getClass().getSimpleName();

        return switch (typeName) {
            case "EntityArgument", "GameProfileArgument" -> List.of("@p", "@a", "@e", "@s", "PlayerName");
            case "BlockPosArgument" -> List.of("~ ~ ~", "0 64 0", "~1 ~-1 ~1");
            case "Vec3Argument" -> List.of("~ ~ ~", "0.0 64.0 0.0");
            case "BlockStateArgument" -> List.of("stone", "minecraft:dirt", "oak_log[axis=y]");
            case "ItemArgument" -> List.of("diamond", "minecraft:stick", "iron_sword{Damage:0}");
            case "ColorArgument" -> List.of("red", "blue", "green", "white");
            case "GameModeArgument" -> List.of("survival", "creative", "adventure", "spectator");
            case "DimensionArgument" -> List.of("overworld", "the_nether", "the_end");
            case "TimeArgument" -> List.of("1d", "1s", "1t", "100");
            default -> Collections.emptyList();
        };
    }
}
