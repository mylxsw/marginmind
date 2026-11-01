# Model metadata and request behavior

## Configured models can be used directly

As of 2026-11-01, model capability records are optional metadata, not an
allowlist. All enabled configured models, including aliases, proxy endpoints,
custom services, Anthropic and Ollama, can resolve and dispatch without a
maintained profile or a connection test. Real provider errors are reported by
the existing request error handling.

- Settings and model menus show no compatibility warning, approval action or
  “not adapted” label. Connection testing remains available in model settings.
- Task capability requirements document what a feature uses. Unknown or
  unsupported metadata does not block tools, history, images or a task request.
- Tool execution still follows the task's allowed tools, the user's tools/network
  settings and proposal confirmation rules. Capability metadata no longer
  silently disables those tools.
- Known provider reasoning recipes are used when available. Otherwise the app
  omits optional reasoning parameters and uses the provider's defaults. The
  stored effective policy is `auto`, so it does not falsely claim that thinking
  was disabled. Quick tasks display Auto in this case and remain usable.
- A corrupt/unavailable metadata cache does not prevent model use. Credentials,
  enabled/deleted model state and endpoint/configuration identity are still
  checked; an edit during a pending request cannot dispatch an obsolete snapshot.

## Metadata and connection tests

`maintained.dart` supplies exact provider/model reasoning recipes and known
context/output sizes. Its match rules only select optional defaults; a missing
match never means the model is incompatible. `AssistantCapabilityProfiles`
continues to store exact identities and connection observations. A connection
test checks whether the service responds; it neither grants nor denies access.

## Request integrity

`DefaultProviderPolicyCompiler` freezes the optional parameters and output limit
for each call. `verifyPolicyPayload` checks that the SDK sends that frozen
configuration. Task/request output limits, cancellation, transport timeouts,
schema validation and retries keep their existing behavior. These checks are
independent of capability approval.

## Regression coverage

- Model routing, compiler and connection-probe tests cover models without records,
  aliases, proxy endpoints, provider defaults and failed metadata loading.
- SDK HTTP adapter tests resolve `deepseek-flash` at a custom proxy, execute a tool
  call, send the result and replay persisted history without any model profile.
- Runtime tests exercise initial calls and schema repair with no capability
  record, including a Heavy request with an image.
- Settings tests cover all twelve features, proxy selection, always-on models,
  metadata-cache failure and narrow screens without compatibility warnings.

The HTTP tests use recorded mock responses with the real SDK encoder. They do
not claim live service acceptance or model quality for a particular account.
