---
name: commit-message
description: Use when writing a git commit message (git commit, jj describe, jj commit, etc.).
---

# Commit messages

Follow the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) format.

```
<type>[(scope)][!]: <description>

<body>
```

## Rules

1. The first line is `<type>[(scope)]: <description>`. Choose the type from `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Mark a breaking change with `!` right after the type or scope.
2. Write the body after one blank line following the first line, and keep it to about 5 lines. Prefer explaining why the change was made over what changed. If the change is self-evident, the body may be omitted.
3. Do not add a footer. Do not write trailers such as `Co-Authored-By` or `BREAKING CHANGE:`.
4. Match the language of the existing commit history. If unsure, check recent messages with `git log`.
