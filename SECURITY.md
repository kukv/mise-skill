# Security Policy

## Supported versions

Only the latest commit on `main` is supported. Fixes are not backported; update the plugin
with `mise plugins update skill`.

## Reporting a vulnerability

Report privately through GitHub: open the **Security** tab of this repository and
choose **Report a vulnerability**. Please do not open a public issue.

Include the plugin commit (`mise plugins ls --urls`), what `mise --version` prints, your
operating system, the `skill:` entries in your mise config, and the steps or repository
that reproduce the problem.

## What counts as a security issue

- **Writing outside the managed places.** A crafted repository, skill name or option that
  makes mise-skill create, replace or remove a file or link anywhere other than its own
  install directory and `<dir>/<skill name>` in the configured skill directories.
- **Touching what it does not own.** An install or uninstall that replaces or removes a
  directory or working link that mise-skill did not create.
- **A token leaking.** The GitHub token mise attaches to mise-skill's API requests appearing
  in output, a log, or a file mise-skill writes.

Not a security issue:

- What an installed skill itself tells an agent to do. mise-skill installs the skills you
  list; review a skill's repository before you add it.
- An install that fails or a link that is missing without the effects above. Open an
  ordinary issue.

## Handling

Reports are acknowledged and triaged by the maintainer. Once a fix is released, the
advisory is published with credit to the reporter unless anonymity is requested.
