These are sanitized protocol fixtures derived from the vendors' documented SSE
schemas, not recordings from authenticated live calls. Each frame is replayed
with arbitrary byte fragmentation. Live service verification remains pending
because no API keys were present in the task environment.

References: https://platform.claude.com/docs/en/build-with-claude/streaming
https://developers.openai.com/api/docs/guides/streaming-responses

`tls-key.pem` is a public test-only RSA key, not a credential. The local TLS
test uses OpenSSL (available on macOS/Linux CI) to issue a fresh two-day
self-signed certificate for `research.test` into a temporary directory. Only
that test client's SecurityContext trusts it; the OS trust store is unchanged.
This avoids expired certificate fixtures and validates hostname mismatch.

Network smoke test (skipped by default):
`dart test --tags network --run-skipped`.
