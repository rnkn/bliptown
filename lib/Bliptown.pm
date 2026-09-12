package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape);
use Mojo::SQLite;
use lib '.';

use Geo::Location::IP::Database::SimpleReader;

use Bliptown::Model::User;
use Bliptown::Model::File;
use Bliptown::Model::Page;
use Bliptown::Model::Metadata;
use Bliptown::Model::Mustache;
use Bliptown::Model::DNS;
use Bliptown::Model::Customer;
use Bliptown::Model::Checkout;
use Bliptown::Model::IPC;
use Bliptown::Model::Email;
use Bliptown::Model::Token;
use Bliptown::Model::Util;

sub startup {
	my $app = shift;

	my $health_file = path($ENV{BLIPTOWN_HEALTH_FILE})->remove->touch;
	$app->log->debug("Creating worker health file '$health_file'");

	$app->config(
		reverse_proxy => $app->mode eq 'production' ? 1 : 0,
		render_exts => [ qw(md html css txt) ],
		cdn_exts => {
			eot		=> 1,
			ttf		=> 1,
			woff	=> 1,
			woff2	=> 1,
			jpg		=> 1,
			jpeg	=> 1,
			png		=> 1,
			webp	=> 1,
			gif		=> 1,
			mp3		=> 1,
			mp4		=> 1,
			mpeg	=> 1,
			webm	=> 1,
			pdf		=> 1,
		},
		prettydate_fmts => {
			euro		=> '%e %B %Y',
			us			=> '%B %e, %Y',
			monthyear	=> '%B %Y',
			year		=> '%Y',
			iso			=> '%F',
		},
	);

	$app->secrets([
		$ENV{BLIPTOWN_SECRET}
	]);

	$app->max_request_size(1024 * 1024 * 250);

	delete $app->static->extra->{'favicon.ico'};

	$app->helper(
		sqlite => sub {
			my $db = path($ENV{BLIPTOWN_DB});
			state $sql = Mojo::SQLite->new("sqlite:$db");
			return $sql;
		});

	my $migrations_path = $app->home->child('migrations.sql');
	$app->sqlite->migrations->from_file($migrations_path)->migrate($ENV{BLIPTOWN_DB_SCHEMA});

	$app->helper(
		db => sub {
			my $c = shift;
			state $db = $c->sqlite->db;
			$db->query("PRAGMA busy_timeout = 10000");
			return $db;
		});

	$app->helper(
		geoip => sub {
			my $db = path($ENV{BLIPTOWN_GEOIP_DB});
			state $reader = Geo::Location::IP::Database::SimpleReader->new(
				file => $db,
				locales => ['en']
			);
			return $reader;
		});

	$app->helper(
		ipc => sub {
			state $ipc = Bliptown::Model::IPC->new;
			return $ipc;
		});

	$app->helper(
		customer => sub {
			my $c = shift;
			return Bliptown::Model::Customer->new(
				util => $c->util,
			);
		});

	$app->helper(
		checkout => sub {
			my $c = shift;
			return Bliptown::Model::Checkout->new(
				util => $c->util,
			);
		});

	$app->helper(
		user => sub {
			my $c = shift;
			return Bliptown::Model::User->new(
				db => $c->db,
				customer => $c->customer,
			);
		});

	$app->helper(
		page => sub {
			my $c = shift;
			return Bliptown::Model::Page->new(
				user => $c->user,
				metadata => $c->metadata,
				mustache => $c->mustache,
				util => $c->util
			);
		});

	$app->helper(
		metadata => sub {
			return Bliptown::Model::Metadata->new;
		});

	$app->helper(
		mustache => sub {
			my $c = shift;
			my $fmt = $c->get_user_prettydate_fmt($c->get_req_username);
			return Bliptown::Model::Mustache->new(
				user => $c->user,
				metadata => $c->metadata,
				util => $c->util,
				prettydate_fmt => $fmt,
			);
		});

	$app->helper(
		file => sub {
			return Bliptown::Model::File->new;
		});

	$app->helper(
		token => sub {
			my $c = shift;
			return Bliptown::Model::Token->new(
				db => $c->db
			);
		});

	$app->helper(
		email => sub {
			my $c = shift;
			return Bliptown::Model::Email->new(
				user => $c->user,
				token => $c->token,
				util => $c->util,
			);
		}
	);

	$app->helper(
		dns => sub {
			return Bliptown::Model::DNS->new;
		}
	);

	$app->helper(
		util => sub {
			my $c = shift;
			my $user_path = $c->get_req_user_path;
			return Bliptown::Model::Util->new(
				user_path => $user_path,
			);
		}
	);

	$app->helper(
		get_slug => sub {
			my $slug = shift->req->url->path->to_string;
			$slug = url_unescape($slug);
			$slug =~ s{^/}{};
			return $slug;
		});

	$app->helper(
		get_req_user_path => sub {
			my $c = shift;
			my $path = $c->stash('user_home_path');
			unless ($path) {
				my $host = $c->req->url->to_abs->host;
				return unless $host;
				$host =~ s/^www\.//;
				if ($host =~ /\Q$ENV{BLIPTOWN_DOMAIN}\E$/) {
					my @host_parts = split(/\./, $host);
					my $username = @host_parts >= 3 ? $host_parts[-3] : 'mayor';
					$path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
				}
				else {
					$path = path($ENV{BLIPTOWN_DATA_HOME}, 'domains', $host)->realpath;
				}
				return unless -d $path;
				$c->stash(user_home_path => $path);
			};
			return $path;
		});

	$app->helper(
		get_req_username => sub {
			my $c = shift;
			my $req_username = $c->stash('req_username');
			unless ($req_username) {
				my $path = $c->get_req_user_path;
				return unless $path;
				$req_username = ${$path->to_array}[-1];
			}
			return $req_username;
		});

	$app->helper(
		get_user_custom_domain => sub {
			my ($c, $username) = @_;
			my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, '_domain.txt');
			if (-f $path) {
				my $domain = $c->util->read_file_line($path) // '';
				my $domain_re = qr/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
				return $domain if $domain =~ $domain_re;
			}
			return;
		});

	$app->helper(
		get_user_prettydate_fmt => sub {
			my ($c, $username) = @_;
			my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, '_prettydate.txt');
			my $style = -f $path ? $c->util->read_file_line($path) : 'euro';
			my $fmt = $c->app->config->{prettydate_fmts}->{$style};
			return $fmt;
		});

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			my $user_path = $c->get_req_user_path;
			return unless $user_path;
			my $path = path($user_path, $slug)->to_abs;
			return $path if -f $path;
			foreach my $ext (@{$c->app->config->{render_exts}}) {
				my $f = path($user_path, "$slug.$ext")->to_abs;
				return $f if -f $f;
			}
			return;
		}
	);

	my %accesslogs;
	$SIG{USR1} = sub { undef %accesslogs };

	$app->helper(
		accesslog => sub {
			my ($c, $logpath) = @_;

			return $accesslogs{$logpath} ||= do {
				my $log = Mojo::Log->new(
					level => 'info',
					path => $logpath,
				);

				$log->format(
					sub {
						my ($time, $level, @lines) = @_;
						$time = int($time);
						return join("\t", $time, @lines) . "\n";
					}
				);
				$log;
			}
		}
	);

	$app->defaults(
		site_title => 'Bliptown',
		page_title => 'Untitled',
		description => 'A very talented artist',
		author => 'Anonymous',
		username => '',
		user_style => 0,
		editable => 0,
		header => '',
		menu => '',
		footer => '',
		content => '',
		ext => 'md',
		redirect => '/',
		includes => [],
		theme => '',
	);

	$app->hook(
		before_server_start => sub {
			my $server = shift;
			$server->on(
				heartbeat => sub {
					my $prefork = shift;
					path($ENV{BLIPTOWN_HEALTH_FILE})->spew($prefork->healthy);
				}
			);
		}
	);

	$app->hook(
		before_routes => sub {
			my $c = shift;
			my $req_url = $c->req->url->to_abs;
			my $host = $req_url->host;
			return unless $host;

			$host =~s/^www\.//;

			$c->app->sessions->cookie_domain(
				$host =~ /\Q$ENV{BLIPTOWN_DOMAIN}\E$/ ? $ENV{BLIPTOWN_DOMAIN} : $host
			);

			if ($host eq "cdn-origin.$ENV{BLIPTOWN_DOMAIN}") {
				my $req_username = shift @{$req_url->path->parts};
				return unless $req_username;
				my $slug = join '/', @{$req_url->path->parts};
				my $path = path($c->get_req_user_path, $slug)->to_abs;
				if (-f $path) {
					my $max_age = 24 * 60 * 60;
					$c->res->headers->cache_control("public, must-revalidate, max-age=$max_age");
					return $c->reply->file($path);
				}
			}
			else {
				$c->res->headers->cache_control('no-cache');
			}
			return;
		}
	);

	my $r = $app->routes;

	$r->get(
		'/.well-known/acme-challenge/:file' => sub {
			my $c = shift;
			my $path = path('/var/www/acme/', $c->param('file'));
			if (-f $path) {
				return $c->reply->file($path);
			}
			return $c->reply->not_found;
		})->name('acme_challenge');

	$r->post('/_login')->to(controller => 'Users', action => 'generate_login')->name('generate_login');
	$r->post('/_generate_logout')->to(controller => 'Users', action => 'generate_logout')->name('generate_logout');
	$r->post('/_logout')->to(controller => 'Users', action => 'user_logout')->name('user_logout');
	$r->get('/_auth')->to(controller => 'Users', action => 'user_auth')->name('user_auth');
	$r->get('/_login')->to(controller => 'Users', action => 'user_login')->name('user_login');

	$r->get('/track/:rand')->to(controller => 'Analytics', action => 'track_visit')->name('track_visit');

	$r->get('/mysite' => sub {
		my $c = shift;
		my $username = $c->session('username');

		unless ($username) {
			$c->flash(info => 'Login required');
			return $c->redirect_to('/');
		}

		my $host = $c->get_user_custom_domain($username) // "$username.$ENV{BLIPTOWN_DOMAIN}";
		my $url = $c->util->create_bliptown_url({
			host => $host,
		});

		return $c->redirect_to($url);
	})->name('my_site');

	my $protected = $r->under(
		sub {
			my $c = shift;
			my $username = $c->session('username');
			my $req_username = $c->get_req_username;
			return unless $req_username;
			if ($username && $username eq $req_username) {
				return 1;
			}
			else {
				$c->flash(info => 'Login required');
				$c->render(
					status => 403,
					template => 'message',
					title => 'Bliptown :: 403 Forbidden',
					content => '403 Forbidden: sorry, this page requires a login.'
				);
				return;
			}
		}
	);

	my $private = $protected->under(
		sub {
			my $c = shift;
			$c->stash(subdir => 'private');
			return 1;
		}
	);

	my $block_demo = sub {
		my $c = shift;
		my $username = $c->session('username') // '';
		if ($username eq $ENV{BLIPTOWN_DEMO_USER}) {
			$c->render(
				status => 403,
				template => 'message',
				title => 'Bliptown :: 403 Forbidden',
				content => '403 Forbidden: demo user cannot perform this action.'
			);
			return;
		}
		return 1;
	};

	$private->get('/_raw/private/*catchall')->to(controller => 'Pages', action => 'render_raw', catchall => '')->name('render_private_raw');
	$private->get('/private/*catchall')->to(controller => 'Pages', action => 'render_page', catchall => '')->name('render_private_page');

	$protected->post('/_new_directory')->to(controller => 'Files', action => 'new_directory')->name('new_directory');
	$protected->post('/_new')->to(controller => 'Files', action => 'new_file')->name('new_file');
	$protected->post('/_delete')->to(controller => 'Files', action => 'delete_files')->name('delete_files');
	$protected->post('/_rename')->to(controller => 'Files', action => 'rename_file')->name('rename_file');
	$protected->post('/_backup')->to(controller => 'Files', action => 'backup_file')->name('backup_file');
	$protected->under($block_demo)->post('/_upload')->to(controller => 'Files', action => 'upload_files')->name('upload_files');
	$protected->get('/_files/*catchall')->to(controller => 'Files', action => 'list_files', catchall => '')->name('list_files');

	$protected->post('/_edit')->to(controller => 'Pages', action => 'save_page')->name('save_page');
	$protected->get('/_new/*catchall')->to(controller => 'Pages', action => 'new_page', catchall => '')->name('new_page');
	$protected->get('/_edit/*catchall')->to(controller => 'Pages', action => 'edit_page', catchall => '')->name('edit_page');

	$protected->under($block_demo)->post('/_settings')->to(controller => 'Settings', action => 'save_settings')->name('save_settings');
	$protected->get('/_settings')->to(controller => 'Settings', action => 'list_settings')->name('list_settings');

	$protected->post('/_snapshots/new')->to(controller => 'Snapshots', action => 'take_snapshot')->name('take_snapshot');
	$protected->post('/_snapshots/restore')->to(controller => 'Snapshots', action => 'restore_snapshot')->name('restore_snapshot');
	$protected->get('/_snapshots/download/:hash')->to(controller => 'Snapshots', action => 'download_snapshot')->name('download_snapshot');
	$protected->get('/_snapshots/diff/:hash')->to(controller => 'Snapshots', action => 'render_diff')->name('render_diff');
	$protected->get('/_snapshots')->to(controller => 'Snapshots', action => 'list_snapshots')->name('list_snapshots');

	$r->get('/_health')->to(controller => 'Health', action => 'health_check')->name('health_check');

	$r->get('/style.css')->to(controller => 'Pages', action => 'render_style')->name('render_style');

	$r->get('/_raw/*catchall')->to(controller => 'Pages', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Pages', action => 'render_page', catchall => '')->name('render_page');
}

return 1;

=head1 NAME

Bliptown - A portfolio platform for artists and creatives.

Bliptown is a a flat-file CMS using the Perl Mojolicious web framework
and Markdown files. There is a small SQLite database for user settings
and credentials. The server runs OpenBSD.

=head1 DESCRIPTION

=head2 Commands

=over

=item * Install dependencies: C<carmel install>

=item * Run tests: C<carmel exec prove>

=item * Run a single test: C<carmel exec prove t/controller_files.t>

=item * Syntax check a file: C<carmel exec perl -w -c lib/Bliptown.pm>

=item * The deployed app starts with C<perl
  -Ilocal/lib/perl5/script/bliptown>

=item * Generate an analytics report from access logs:
  C<script/bliptown_analytics>

=back

=head2 Architecture

=over

=item * C<lib/Bliptown.pm> wires config, helpers, hooks, and routes.

=item * Controllers live in C<lib/Bliptown/Controller/>; models/helpers live
  in C<lib/Bliptown/Model/>.

=item * User content under each user's home directory C<~/site>, while
  account state lives in SQLite via C<Mojo::SQLite>.

=item * Privileged filesystem, git, and certificate operations are not done
  directly in controllers. They go through C<script/bliptown_helper>
  over a Unix socket using JSON.

=item * Markdown page rendering is handled by C<Model::Page>, which combines
  YAML frontmatter, Mustache-style templating, md4c rendering, and DOM
  post-processing.

=item * Routing is host-aware: C<get_req_username> maps subdomains/custom
  domains to a user, and the page/file helpers always resolve paths
  relative to that user's home.

=item * Site versioning (history, restore, diff) is implemented as git
  operations (C<git_commit>, C<git_log>, C<git_show>, C<git_checkout>,
  C<git_archive>) run by C<script/bliptown_helper> and surfaced through
  C<Controller::Snapshots>, reusing the same privileged-IPC mechanism
  as filesystem operations.

=item * Custom domains are verified in C<Model::DNS>, which checks that a
  domain's A/AAAA records point at the server and that a C<_bliptown>
  TXT record matches the owning user.

=item * User login is passwordless: C<Controller::Users> and C<Model::Email>
  implement a magic-link flow (one-time tokens in SQLite, emailed via
  C<Mojo::SMTP::Client>).

=item * Billing (C<Model::Checkout>, C<Model::Customer>) talks to the Stripe
  REST API directly via C<Mojo::UserAgent>.

=back

=head2 Conventions

=over

=item * Use the existing C<Mojo::Base> package style, keep modules ending
  with C<return 1;>, and prefer small controller actions that delegate
  work to models or IPC helpers.

=item * Keep file access constrained to the user root and reuse C<get_file>,
  C<get_slug>, and C<ipc->send_message> instead of open-coding path
  resolution or helper calls.

=item * Preserve the existing page syntax: C<---> YAML frontmatter, C<{{ }}>
  variables, C<{{ # ... }}> sections, and C<{{ E<gt> ... }}> partials.

=item * Preserve the current error flow: helper failures are surfaced with
  C<reply->exception>, while user-facing validation issues use flash
  messages and redirects.

=item * C<demo> is treated as a restricted account for destructive actions.

=item * Controller/model tests avoid the real C<bliptown_helper> socket by
  swapping in C<t/lib/FakeIPC.pm> for the C<ipc> helper.

=item * Prefer simple, pragmatic, clear, elegant code. Follow the 12 Factor
  App methodology, except for "Twelve-factor apps also do not rely on
  the implicit existence of any system tools" as Bliptown is deeply
  integrated with OpenBSD.

=back

=head2 Configuration

Initial system setup:

  # syspatch
  # cat <<EOF >> /etc/mail/aliases
  root: rnkn
  mayor: rnkn
  # newaliases
  # cat <<EOF > /etc/doas.conf
  permit persist keepenv :wheel
  # usermod -G wheel,wsrc rnkn
  # cat <<EOF > /etc/ssh/sshd_config
  PermitRootLogin no
  StrictModes no
  DenyUsers demo
  AuthorizedKeysFile /home/bliptown/users/%u/_pubkeys.txt
  PasswordAuthentication no
  # rcctl restart sshd
  # cat <<EOF > /etc/hostname.vio0
  inet autoconf
  inet alias **.***.**.*** 255.255.255.255
  # cat <<EOT > /etc/fstab
  ***********.b none swap sw
  ***********.a / ffs rw 1 1
  ***********.l /home ffs rw,nodev,nosuid,userquota=/var/quotas/home.user 1 2
  ***********.d /tmp ffs rw,nodev,nosuid,userquota=/var/quotas/tmp.user 1 2
  ***********.f /usr ffs ro,nodev 1 2
  ***********.g /usr/X11R6 ffs rw,nodev 1 2
  ***********.h /usr/local ffs rw,wxallowed,nodev 1 2
  ***********.k /usr/obj ffs rw,nodev,nosuid 1 2
  ***********.j /usr/src ffs rw,nodev,nosuid 1 2
  ***********.e /var ffs rw,nodev,nosuid 1 2
  # quotacheck -a
  # quotaon /home /tmp
  # ln -s /usr/bin/openrsync rsync
  # crontab -l | head -2
  MAXMIND_ID=*******
  MAXMIND_KEY=************************************_mmk

=head2 Installation

Install required packages:

  # pkg_add sqlite3 libffi md4c git sqlports libmaxminddb jq monit \
    p5-DBI p5-DBD-SQLite pkglocatedb

Build and install [Carmel](https://metacpan.org/pod/Carmel):

  $ cd /tmp
  $ ftp https://cdn.openbsd.org/pub/OpenBSD/$(uname -r)/{ports.tar.gz,SHA256.sig}
  $ signify -Cp /etc/signify/openbsd-$(uname -r | cut -c 1,3)-base.pub -x SHA256.sig ports.tar.gz
  # cd /usr
  # tar xzf /tmp/ports.tar.gz
  # chown -R :wsrc ports
  # chmod -R g+w ports
  $ /usr/ports/infrastructure/bin/portgen p5 Carmel
  $ cd /usr/ports/mystuff/cpan/p5-Carmel
  # make install

Install Bliptown app:

  $ git init --bare /home/rnkn/git/bliptown.git
  $ cd /usr/local/www
  $ git clone /home/rnkn/git/bliptown.git
  $ cd bliptown
  # carmel install
  # carmel rollout
  # cd etc
  # cp hourly.local daily.local weekly.local \
    httpd.conf pf.conf relayd.conf rc.local newsyslog.conf \
    gitignore monitrc motd usermgmt.conf /etc
  # mv /tmp/syslog.conf.tmp /etc/syslog.conf
  # cat newsyslog.conf >> /etc/newsyslog.conf
  # install -m 755 -o root -g bin etc/rc.d/bliptown_helper /etc/rc.d/
  # install -m 755 -o root -g bin etc/rc.d/bliptown /etc/rc.d/
  # install -m 755 -o root -g bin etc/rc.d/block_php /etc/rc.d/
  # cat <<EOF >> /etc/login.conf
  bliptown:\
    :setenv=\
  BLIPTOWN_SECRET=***********,\
  BLIPTOWN_HEALTH_FILE=
  BLIPTOWN_HELPER_HEALTH_FILE=
  BLIPTOWN_HELPER_SOCKET=
  BLIPTOWN_DOMAIN=blip.town,\
  BLIPTOWN_IPV4=**.***.**.***,\
  BLIPTOWN_IPV6=****:****:****:****::*,\
  BLIPTOWN_USER_HOME=/home/bliptown/users,\
  BLIPTOWN_DB=/var/db/bliptown/users.db,\
  BLIPTOWN_LOG_HOME=/var/log/bliptown,\
  BLIPTOWN_GEOIP_DB=/var/db/GeoIP/geolite2-country-current.mmdb,\
  BLIPTOWN_MD4C_LIB=/usr/local/lib/libmd4c-html.so.0.0,\
  BLIPTOWN_MD4C_HTML_LIB=/usr/local/lib/libmd4c-html.so.0.0,\

  BLIPTOWN_SECRET=*************,\
  BLIPTOWN_HEALTH_FILE=/tmp/bliptown.health,\
  BLIPTOWN_HELPER_HEALTH_FILE=/tmp/bliptown_helper.health,\
  BLIPTOWN_HELPER_SOCKET=/var/run/bliptown_helper.sock,\
  BLIPTOWN_DOMAIN=blip.town,\
  BLIPTOWN_SCHEME=https,\
  BLIPTOWN_PORT=,\
  BLIPTOWN_IPV4=**.**.**.**,\
  BLIPTOWN_IPV6=****\c****\c****\c****\c\c1,\
  BLIPTOWN_SMTP_ADDR=*************,\
  BLIPTOWN_SMTP_PORT=465,\
  BLIPTOWN_SMTP_LOGIN=*************,\
  BLIPTOWN_SMTP_PASS=*************,\
  BLIPTOWN_DATA_HOME=/home/bliptown,\
  BLIPTOWN_DB=/var/db/bliptown/users.db,\
  BLIPTOWN_DB_SCHEMA=**,\
  BLIPTOWN_LOG_HOME=/var/log/bliptown,\
  BLIPTOWN_GEOIP_DB=/var/db/GeoIP/geolite2-country-current.mmdb,\
  BLIPTOWN_MD4C_HTML_LIB=/usr/local/lib/libmd4c-html.so.0.0,\
  BLIPTOWN_CDN_API_HOST=*************,\
  BLIPTOWN_CDN_API_KEY=*************,\
  BLIPTOWN_STRIPE_API_KEY=sk_live_*************,\
  BLIPTOWN_STRIPE_PRICE_ID=price_*************,\
  BLIPTOWN_DEMO_USER=demo,\
  BLIPTOWN_THEME_USER=themes,\

  bliptown_helper:\
        :setenv=\
  BLIPTOWN_HELPER_HEALTH_FILE=/tmp/bliptown_helper.health,\
  BLIPTOWN_HELPER_SOCKET=/var/run/bliptown_helper.sock,\
  BLIPTOWN_HELPER_PREFORK=4,\
  BLIPTOWN_GID=****,\
  BLIPTOWN_DATA_HOME=/home/bliptown,\
  BLIPTOWN_KEYPAIR_FILE=/etc/relayd-keypairs.conf,\
  BLIPTOWN_ACME_FILE=/etc/acme-domains.conf:
  EOF
  # sh /etc/hourly.local
  # sh /etc/daily.local
  # sh /etc/weekly.local
  # rcctl enable httpd relayd bliptown_helper bliptown monit
  # rcctl start httpd relayd bliptown_helper bliptown monit

C<etc/rc.d/bliptown_staging> and C<bliptown_staging_helper> run a second,
separate instance of the app (as the C<bliptown_staging> user, on
C<127.0.0.1:8081>) for testing changes before they go live; install and
enable them the same way as the production C<bliptown>/C<bliptown_helper>
scripts if a staging instance is needed.

=head1 COPYRIGHT & LICENSE

Copyright (C) 2025-2026, Paul W. Rankin

This program is free software, you can redistribute it and/or modify
it under the terms of the Artistic License version 2.0.

=cut
