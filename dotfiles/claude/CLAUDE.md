# Shell

The user's interactive shell is Nushell (nu), whose syntax differs from bash and POSIX sh. Commands run through the Bash tool can stay in bash, but commands shown for the user to run must work in nu.

- `&&` cannot chain commands. Separate them with `;`. nu stops at the first failing command, so this behaves like `&&`.
- Reference environment variables as `$env.VAR`, not `$VAR`, and set them with `$env.VAR = "value"`, not `export VAR=value`. To pass one to a single command, use `with-env { VAR: value } { cmd }`.
- Write command substitution as `(cmd)`, not `$(cmd)`.
- Write to a file with `| save file`, not `> file`. To include an external command's stderr, use `o+e>| save file`.
- If bash syntax is truly needed, wrap it in `bash -c '...'`.

Commands the user runs with `! <command>` run in Claude Code's bash, so bash syntax is fine there.

# Version control

If the repository root has `.jj`, operate with jj instead of git. The same applies to colocated repositories that also have `.git`.

- Check status and history with `jj st`, `jj log`, and `jj diff`.
- Commit with `jj commit -m` or `jj describe -m`. jj tracks new files automatically, so `git add` is not needed.
- Use git only for operations jj cannot express, and tell the user why.
- In a colocated repository, git always sees a detached HEAD. This is jj's normal state, so do not treat it as an anomaly or go back to a branch with `git checkout` or `git switch`. The equivalent of a branch is a jj bookmark; check them with `jj bookmark list`.
