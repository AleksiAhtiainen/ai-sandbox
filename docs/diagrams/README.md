# Threat-model diagrams

These diagrams use the five symbols from
[DFD3](https://github.com/adamshostack/DFD3):

| Element | PlantUML representation |
| --- | --- |
| External entity | Sharp-cornered rectangle |
| Process | Rounded rectangle |
| Data store | Cylinder |
| Data flow | Solid arrow |
| Trust boundary | Dashed rectangle |

Every element and flow has a stable ID so findings can refer to it without
depending on the diagram layout. Color is not used to convey meaning.

## Diagrams

[system-context.puml](system-context.puml) models the sandbox at context level.
The locally administered host, UTM VM, host Git workflow, and optional local
model are in scope. The developer and third-party services are external
entities.

Lower-level diagrams decompose distinct parts of that context:

| Diagram | Scope | Rendered |
| --- | --- | --- |
| [System context](system-context.puml) | Major actors, boundaries, stores, and flows | [SVG](generated/system-context.svg), [PNG](generated/system-context.png) |
| [Host and VM boundary](host-vm-boundary.puml) | UTM, virtio/9p, bindfs, SPICE, networking, disk, and host Git paths | [SVG](generated/host-vm-boundary.svg), [PNG](generated/host-vm-boundary.png) |
| [AI runtime and MCP](ai-runtime-mcp.puml) | Claude Code, OpenCode, tools, MCP servers, Chromium, IDEA, and persistent state | [SVG](generated/ai-runtime-mcp.svg), [PNG](generated/ai-runtime-mcp.png) |
| [Host-local model](host-local-model.puml) | OpenCode-to-llama.cpp inference over UTM vmnet | [SVG](generated/host-local-model.svg), [PNG](generated/host-local-model.png) |
| [Supply chain](supply-chain.puml) | Source publication, GitHub Actions seed builds, first boot, local builds, updates, and runtime downloads | [SVG](generated/supply-chain.svg), [PNG](generated/supply-chain.png) |

The diagrams intentionally overlap at their interfaces. Stable IDs are local
to each diagram; for example, `P1` in one diagram is unrelated to `P1` in
another.

## Rendering

Docker must be available. From any directory, run:

```sh
docs/diagrams/render.sh
```

The script renders every `.puml` file in this directory to `generated/` as SVG
and PNG. The PlantUML container is pinned by digest. The source directory is
mounted read-only and only the generated-output directory is writable.
