import strutils, sequtils
import ../../../common/utils
import ../../../types/[common, protocol]

# Recursively matches a string to a pattern
# - Case-insensitive
# - * wildcard matches any pattern
# - ? wildcard matches one character
proc matchString(s, pattern: string): bool =
    if pattern == "*":
        return true
    if pattern.len == 0:
        return s.len == 0

    if s.len == 0:
        for c in pattern:
            if c != '*': return false
        return true

    if pattern[0] == '*':
        return matchString(s, pattern[1..^1]) or matchString(s[1..^1], pattern)

    if pattern[0] == '?' or pattern[0].toLowerAscii() == s[0].toLowerAscii():
        return matchString(s[1..^1], pattern[1..^1])

    return false

# Check if a value matches the configured guardrail
# - At least one of the comma-separated entries must match the value
# - If an entry is negated using "!", it must not match
proc checkGuardrail(value, input: string): bool =
    let entries = input.split(',').mapIt(it.strip()).filterIt(it.len > 0)
    for entry in entries:
        if entry.startsWith("!") and matchString(value, entry[1..^1]):
            return false

    let positives = entries.filterIt(not it.startsWith("!"))
    return positives.len == 0 or positives.anyIt(matchString(value, it))

proc has(guardrails: Guardrails, guardrail: GuardrailType): bool =
    return (guardrails.guardrails and uint32(guardrail)) != 0

proc checkGuardrails*(guardrails: Guardrails, metadata: AgentMetadata): bool =
    if guardrails == nil or guardrails.guardrails == 0:
        return true # No guardrail set

    if guardrails.has(GUARDRAIL_DOMAIN):
        let domain = Bytes.toString(metadata.domain)
        if domain == "":
            return false # System is not domain-joined
        if guardrails.domain.strip().len > 0 and not checkGuardrail(domain, guardrails.domain.strip()):
            return false # System is not joined to a specific AD domain

    if guardrails.has(GUARDRAIL_IP):
        if not checkGuardrail(Bytes.toString(metadata.ip), guardrails.ip):
            return false # System IP does not match the guardrail

    if guardrails.has(GUARDRAIL_HOSTNAME):
        if not checkGuardrail(Bytes.toString(metadata.hostname), guardrails.hostname):
            return false # System hostname does not match the guardrail

    return true
