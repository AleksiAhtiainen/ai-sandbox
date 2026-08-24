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

## System context

[system-context.puml](system-context.puml) models the sandbox at context level.
The locally administered host, UTM VM, host Git workflow, and optional local
model are in scope. The developer and third-party services are external
entities. AI tools, MCP servers, VM mount layers, and build infrastructure are
deferred to lower-level diagrams.

Rendered versions:

- [SVG](generated/system-context.svg)
- [PNG](generated/system-context.png)

## Rendering

Docker must be available. From any directory, run:

```sh
docs/diagrams/render.sh
```

The script renders every `.puml` file in this directory to `generated/` as SVG
and PNG. The PlantUML container is pinned by digest. The source directory is
mounted read-only and only the generated-output directory is writable.
