#!/bin/sh

cat <<'EOF'
# Bliptown #

Bliptown is a a flat-file CMS using the Perl Mojolicious web framework
and Markdown files. There is a small SQLite database for user settings
and credentials. The server runs OpenBSD.

## Commands ##

- Install dependencies: `carton install`
- Run tests: `carton exec prove -l t`
- Run a single test: `carton exec prove -l t/basic.t`
- Syntax check a file: `carton exec perl -w -c lib/Bliptown.pm`
- The deployed app starts through the existing wrapper scripts with
  `carton exec -- script/bliptown`

## Architecture ##

- `lib/Bliptown.pm` wires config, helpers, hooks, and routes.
- Controllers live in `lib/Bliptown/Controller/`; models/helpers live
  in `lib/Bliptown/Model/`.
- User content under each user's home directory, while account state
  lives in SQLite via `Mojo::SQLite`.
- Privileged filesystem, git, and certificate operations are not done
  directly in controllers. They go through `script/bliptown_helper`
  over a UNIX socket using Sereal messages.
- Markdown page rendering is handled by `Model::Page`, which combines
  YAML frontmatter, Mustache-style templating, md4c rendering, and DOM
  post-processing.
- Routing is host-aware: `get_req_user` maps subdomains/custom domains
  to a user, and the page/file helpers always resolve paths relative
  to that user's home.

## Conventions ##

- Use the existing `Mojo::Base` package style, keep modules ending
  with `return 1;`, and prefer small controller actions that delegate
  work to models or IPC helpers.
- Keep file access constrained to the user root and reuse `get_file`,
  `get_slug`, and `ipc->send_message` instead of open-coding path
  resolution or helper calls.
- Preserve the existing page syntax: `---` YAML frontmatter, `{{ }}`
  variables, `{{ # ... }}` sections, and `{{ > ... }}` partials.
- Preserve the current error flow: helper failures are surfaced with
  `reply->exception`, while user-facing validation issues use flash
  messages and redirects.
- `demo` is treated as a restricted account for destructive actions.
- Prefer simple, pragmatic, clear, elegant code. Follow the 12 Factor
  App methodology, except for "Twelve-factor apps also do not rely on
  the implicit existence of any system tools" as Bliptown is deeply
  integrated with OpenBSD.


EOF

find -f lib/ script/ t/ -type f ! -name '*~' ! -name '*_' | while read -r file
do
	echo "## File: $file ##"
	echo
	echo '```'
	cat "$file"
	echo '```'
	echo
done
