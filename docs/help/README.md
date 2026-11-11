# Cloudpane help: how these files work

These Markdown files are the help that ships in the app. The Mac app copies the topics
from this folder into its bundle at build time (see `project.yml`), so there is no copy step
to run: edit a file here and the next build has it. This README stays out of the bundle. `HelpCatalog` in CloudpaneCore reads them, so an iOS app could use the same files.

## Front matter

Every topic starts with front matter between two `---` lines:

```
---
title: Backup grade
order: 5
platforms: macOS, iOS
summary: One sentence, shown under the title in search results.
---
```

- `title`: the name in the sidebar, in sentence case.
- `order`: the sidebar position, lowest first.
- `platforms`: `macOS, iOS` for a shared topic, `macOS` for a Mac-only one.
- `summary`: one plain sentence.

This README has no front matter and is not a topic.

## Platform sections

Inside a shared topic, a paragraph or list that applies to one platform only goes between
markers on lines of their own:

```
<!-- macOS -->
Choose Reveal in Finder.
<!-- /macOS -->
```

The catalog drops the section, markers included, on other platforms. Folder grants, menus,
the Dock, Finder and keyboard shortcuts are Mac-only. Concepts such as the grade,
duplicates, plans and privacy are shared.

## Links

Link to another topic by file name: `[Providers](providers.md)`. To land on a section, add
the heading's anchor, made the way GitHub makes it (lowercase, spaces to hyphens, other
punctuation dropped): `[Hashing](duplicates.md#hashing)`, or `[Hashing](#hashing)` within the
same page. The help window follows these links and scrolls to the heading, and a test fails
if a link points at a topic or heading that does not exist.

## Writing

US English, sentence case headings, no exclamation marks, no emoji. Describe only what the
app does today; check each claim against the code. Put paths in backticks: outside a code
span, a tilde would render as strikethrough, and a test rejects it. The renderer handles headings, paragraphs,
bullet and numbered lists, tables, and inline bold, code and links.
