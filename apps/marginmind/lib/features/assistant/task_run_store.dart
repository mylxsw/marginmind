import 'dart:io';

import 'package:mm_core/mm_core.dart';
import 'package:mm_data/mm_data.dart';
import 'package:mm_assistant/mm_assistant.dart';

/// Study-set scoped production assembly shared by task migrations. Routing and
/// secret lookup remain injected by the host, never persisted in run manifests.
SdkAgentRuntime createPersistentTaskRuntime({
  required String studySetDirectory,
  required TaskRegistry tasks,
  VersionedKnowledgeRegistry? knowledge,
  required Future<RuntimeModelBinding> Function(RunContext) loadModel,
}) => SdkAgentRuntime(
  store: FileRunStore(Directory(studySetDirectory)),
  tasks: tasks,
  knowledge: knowledge ?? standardKnowledgeRegistry(),
  loadModel: loadModel,
);
