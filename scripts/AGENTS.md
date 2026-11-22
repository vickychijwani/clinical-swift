Keep Swift scripts short, direct, and low-ceremony:

- Decode JSON with `Decodable` structs and `JSONDecoder`; avoid manual `[String: Any]` unwrapping.
- Avoid duplicate input/output structs and trivial wrapper functions.
- Limit scripts to deterministic work (API calls, auth, security filtering, data normalization). Do not hardcode brittle workflow heuristics or state machines that a calling agent can judge from clean structured facts.
- Prefer standard CLI tools (`gh`, `git`, `curl`, `openssl`) over verbose Foundation networking or custom parsers.
