"""Static checks on the Philips Hue plugin file. Usage: python tests/structural.py philips-hue.qplug

Checks, each printed PASS/FAIL:
  - brackets and quotes balance, and Lua blocks balance (function/if/do against end, repeat against until)
  - every Controls.X / Controls["X"] the runtime touches is declared in GetControls
  - every slot field the runtime reaches through L(i, "F") / G(i, "F") is in LIGHT_FIELDS / GROUP_FIELDS
  - every Properties["X"] the runtime reads is declared in GetProperties
  - no local function is called above the line that declares it (the call would hit a nil global)
  - philips-hue.lua and philips-hue.qplug are byte-identical (Designer takes the .lua by import, the .qplug by double-click)
Exit 0 when all pass, 1 otherwise. Comments and strings are stripped before counting.
"""
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
results = []


def check(name, ok, detail=""):
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {name}{('  -- ' + detail) if detail and not ok else ''}")


def strip(code):
    """Blank out comments and string contents, keeping line structure."""
    out, i, n = [], 0, len(code)
    while i < n:
        if code.startswith("--[[", i):
            j = code.find("]]", i + 4)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", code[i:j])); i = j
        elif code.startswith("--", i):
            j = code.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif code.startswith("[[", i):
            j = code.find("]]", i + 2)
            j = n if j < 0 else j + 2
            out.append('""' + re.sub(r"[^\n]", " ", code[i + 2:j])); i = j
        elif code[i] in "\"'":
            q, j = code[i], i + 1
            while j < n and code[j] != q:
                j += 2 if code[j] == "\\" else 1
            out.append(q + " " * (j - i - 1) + q); i = j + 1
        else:
            out.append(code[i]); i += 1
    return "".join(out)


code = strip(src)

# --- balance ---
pairs = {"(": ")", "[": "]", "{": "}"}
stack, bad = [], None
for ln, line in enumerate(code.split("\n"), 1):
    for ch in line:
        if ch in pairs:
            stack.append((ch, ln))
        elif ch in pairs.values():
            if not stack or pairs[stack[-1][0]] != ch:
                bad = bad or f"unexpected {ch} on line {ln}"
            else:
                stack.pop()
check("brackets balance", bad is None and not stack, bad or (f"unclosed {stack[-1][0]} from line {stack[-1][1]}" if stack else ""))

words = re.findall(r"\b[A-Za-z_]\w*\b", code)
opens = sum(words.count(k) for k in ("function", "if", "do"))
check("blocks balance (function/if/do vs end)", opens == words.count("end"), f"{opens} openers, {words.count('end')} ends")
check("repeat/until balance", words.count("repeat") == words.count("until"))

# --- declared controls, slot fields, properties ---
def field_list(name):
    m = re.search(r"\b" + name + r"\s*=\s*\{([^}]*)\}", src)
    return set(re.findall(r'"(\w+)"', m.group(1))) if m else set()

light_fields, group_fields = field_list("LIGHT_FIELDS"), field_list("GROUP_FIELDS")
get_controls = re.search(r"function GetControls\(.*?\n(.*?)\nend", src, re.S).group(1)
declared = set(re.findall(r'Name\s*=\s*"([^"]+)"\s*,\s*ControlType', get_controls))
declared_lf = set(re.findall(r'Name\s*=\s*LKey\(i,\s*"(\w+)"\)', get_controls))
declared_gf = set(re.findall(r'Name\s*=\s*GKey\(i,\s*"(\w+)"\)', get_controls))
# Fields declared in loops: Name = LKey(i, f) over an ipairs list, and Name = GKey(i, "Sc" .. b).
for lst in re.findall(r'for _, f in ipairs\(\{([^}]*)\}\) do\s*table\.insert\(ctls, \{ Name = LKey\(i, f\)', get_controls):
    declared_lf |= set(re.findall(r'"(\w+)"', lst))
# Per-room buttons generated from a count (GKey(i, "Sc" .. b)) are checked by prefix, not listed.
declared_gprefix = set(re.findall(r'Name\s*=\s*GKey\(i,\s*"(\w+)"\s*\.\.\s*b\)', get_controls))
check("GetControls declares exactly LIGHT_FIELDS per light slot", declared_lf == light_fields, f"declared {sorted(declared_lf)}, list {sorted(light_fields)}")
check("GetControls declares exactly GROUP_FIELDS per group slot", declared_gf == group_fields, f"declared {sorted(declared_gf)}, list {sorted(group_fields)}")
switch_fields, motion_fields = field_list("SWITCH_FIELDS"), field_list("MOTION_FIELDS")
declared_sf = set(re.findall(r'Name\s*=\s*SKey\(i,\s*"(\w+)"\)', get_controls))
nb = int(re.search(r"SWITCH_BUTTONS\s*=\s*(\d+)", src).group(1))
for prefix in re.findall(r'Name\s*=\s*SKey\(i,\s*"(\w)"\s*\.\.\s*b\)', get_controls):
    declared_sf |= {f"{prefix}{b}" for b in range(1, nb + 1)}
declared_mf = set(re.findall(r'Name\s*=\s*MKey\(i,\s*"(\w+)"\)', get_controls))
check("GetControls declares exactly SWITCH_FIELDS per switch slot", declared_sf == switch_fields, f"declared {sorted(declared_sf)}, list {sorted(switch_fields)}")
check("GetControls declares exactly MOTION_FIELDS per motion slot", declared_mf == motion_fields, f"declared {sorted(declared_mf)}, list {sorted(motion_fields)}")
props = set(re.findall(r'\{\s*Name\s*=\s*"([^"]+)"\s*,\s*Type\s*=', src))

runtime_at = src.find("if Controls then")
runtime = src[runtime_at:] if runtime_at >= 0 else ""
used = set(re.findall(r"Controls\.([A-Za-z_]\w*)", runtime)) | set(re.findall(r'Controls\["([^"]+)"\]', runtime))
missing = sorted(used - declared)
check(f"runtime control refs are declared ({len(used)} named refs, {len(declared)} declared)", not missing, ", ".join(missing))

lf_used = set(re.findall(r'\bL\(i,\s*"(\w+)"\)', runtime))
gf_used = set(re.findall(r'\bG\(i,\s*"(\w+)"\)', runtime))
gprefix_used = set(re.findall(r'\bG\(i,\s*"(\w+)"\s*\.\.\s*b\)', runtime))
check(f"per-room button prefixes used at runtime are declared ({', '.join(sorted(gprefix_used))})", gprefix_used <= declared_gprefix, ", ".join(sorted(gprefix_used - declared_gprefix)))
# L(i, f) / L(i, f .. "V") over a literal field list
for lst, suffix in re.findall(r'for _, f in ipairs\(\{([^}]*)\}\) do[^\n]*L\(i, f \.\. "(\w+)"\)', runtime):
    lf_used |= {f + suffix for f in re.findall(r'"(\w+)"', lst)}
check(f"light slot fields used at runtime are declared ({len(lf_used)})", lf_used <= light_fields, ", ".join(sorted(lf_used - light_fields)))
check(f"group slot fields used at runtime are declared ({len(gf_used)})", gf_used <= group_fields, ", ".join(sorted(gf_used - group_fields)))
sf_used = set(re.findall(r'\bS\(i,\s*"(\w+)"\)', runtime))
for prefix in re.findall(r'\bS\(i,\s*"(\w)"\s*\.\.\s*b\)', runtime):
    sf_used |= {f"{prefix}{b}" for b in range(1, nb + 1)}
mf_used = set(re.findall(r'\bM\(i,\s*"(\w+)"\)', runtime))
check(f"switch slot fields used at runtime are declared ({len(sf_used)})", sf_used <= switch_fields, ", ".join(sorted(sf_used - switch_fields)))
check(f"motion slot fields used at runtime are declared ({len(mf_used)})", mf_used <= motion_fields, ", ".join(sorted(mf_used - motion_fields)))

props_used = set(re.findall(r'Properties\["([^"]+)"\]', runtime))
check("property reads are declared", props_used <= props, ", ".join(sorted(props_used - props)))
check("no stale Properties.X access", re.search(r"Properties\.[A-Za-z_]", strip(runtime)) is None)

# --- local functions called before they are declared ---
late = []
for m in re.finditer(r"\blocal\s+function\s+([A-Za-z_]\w*)", code):
    name, decl = m.group(1), m.start()
    before = code[:decl]
    for c in re.finditer(r"\b" + re.escape(name) + r"\s*\(", before):
        if not re.search(r"function\s+$", before[:c.start()][-20:]):
            late.append(f"{name} called on line {before.count(chr(10), 0, c.start()) + 1}, declared on line {before.count(chr(10)) + 1}")
check("no local function is called above its declaration", not late, "; ".join(late))

# --- the .lua and .qplug copies are the same file ---
import os
base, ext = os.path.splitext(path)
twin = base + (".lua" if ext == ".qplug" else ".qplug")
if os.path.exists(twin):
    check(f"{os.path.basename(twin)} is identical to {os.path.basename(path)}", open(twin, "rb").read() == open(path, "rb").read(), "copy the .qplug over the .lua")

# --- timers are global ---
check("no Timer is scoped local", re.search(r"\blocal\s+\w+\s*=\s*Timer\.New", code) is None)

sys.exit(0 if all(results) else 1)
