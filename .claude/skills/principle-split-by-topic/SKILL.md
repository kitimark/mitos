---
name: principle-split-by-topic
description: "Apply when creating a file or module, adding to a large one, or when a file has section banners or a docstring that lists several topics. One file owns one topic, and each statement sits beside the definition it is about."
disable-model-invocation: true
---

# Split by Topic

One file or module owns one topic. A file that owns several makes every reader of one topic load the rest, and the next topic lands there too, because an agent copies the nearest file.

- **Name the topic.** If the name of a file's topic needs "and", split the file.
- **Keep statements beside their definitions.** A statement or proof sits in the file of the definition it is about. Never split one topic into definitions, proofs and fixtures files. That splits by kind of code, not by topic.
- **Banners mark seams.** A section banner, or a docstring that lists several topics, marks a split point. Extract one module per banner.
- **Split at design time.** The Design block's `modules:` field (`tasks/TEMPLATE.md`) names each file and its one topic. A build that outgrows it reports a deviation. The `/no-comments` pass reports banners as split points.
- **In Lean,** `private` is file-scoped, so a helper that two new files use can no longer be `private`. Every new module must still be built and axiom-checked.

Related: [Minimize Reader Load](../principle-minimize-reader-load/SKILL.md) counts layers and state, [Model the Domain](../principle-model-the-domain/SKILL.md) picks the structure, and [Encode Lessons in Structure](../principle-encode-lessons-in-structure/SKILL.md) turns this rule into a check (#252, a size tripwire).

**The test:** can you name each file's topic without "and", and does each statement live in the file of the definition it talks about? If not, split.
