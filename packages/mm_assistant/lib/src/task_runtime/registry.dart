import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:mm_core/mm_core.dart';

/// Domain-owned codecs/validators are registered once. Tools must already carry
/// the application's permission/proposal hooks; runtime adds the task allowlist.
class TaskDefinition<T> {
  TaskDefinition({
    required this.spec,
    required this.instructions,
    required this.decode,
    required this.encode,
    required this.restore,
    required this.validator,
    required this.validateInput,
    this.createBindings,
    this.tools = const [],
    this.hooks = const [],
    this.maxTurns = 8,
  });
  final TaskSpec spec;
  final String instructions;
  final T Function(String) decode;
  final Map<String, dynamic> Function(T) encode;
  final T Function(Map<String, dynamic>) restore;
  final TaskValidator<T> validator;
  final ValidationReport Function(Map<String, dynamic>) validateInput;
  final TaskBindings Function(RunContext, AgentState, Map<String, dynamic>)? createBindings;
  final List<Tool> tools;
  final List<AgentHook> hooks;
  final int maxTurns;
}

class TaskRegistry {
  final _definitions = <TaskType, Object>{};
  void register<T>(TaskDefinition<T> definition) {
    if (_definitions.containsKey(definition.spec.type)) throw StateError('Task already registered');
    _definitions[definition.spec.type] = definition;
  }

  TaskDefinition<T> resolve<T>(TaskSpec spec) {
    final definition = _definitions[spec.type];
    if (definition is! TaskDefinition<T> || !identical(definition.spec, spec)) {
      throw const ConfigurationFailure('unregisteredTaskContract');
    }
    return definition;
  }
}

/// Per-run ownership for mutable citation, policy, permission and proposal hooks.
class TaskBindings {
  TaskBindings({List<Tool> tools = const [], List<AgentHook> hooks = const []})
    : tools = List.unmodifiable(tools),
      hooks = List.unmodifiable(hooks);
  final List<Tool> tools;
  final List<AgentHook> hooks;
}
