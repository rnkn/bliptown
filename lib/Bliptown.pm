package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape generate_secret encode);
use Mojo::SQLite;
use Mojo::Template;
use IO::Pipe;
use lib '.';
use POSIX qw(strftime);

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
		app_log_priority => {
			trace	=> 'local1.debug',
			debug	=> 'local1.debug',
			info	=> 'local1.info',
			warn	=> 'local1.warning',
			error	=> 'local1.err',
			fatal	=> 'local1.crit',
		},
		visitor_log_priority => 'local2.info',
		render_exts => [ qw(md html css txt js) ],
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
		csp_default =>
		  q{default-src 'self'; }
		. q{object-src 'none'; }
		. q{base-uri 'none'; }
		. q{frame-ancestors 'none'; }
		. q{form-action 'self'; }
		. q{img-src 'self'; }
		. q{style-src 'self'; }
		. q{script-src 'self'; }
		. q{connect-src 'self'; },
		csp_pages =>
		  q{default-src 'self'; }
		. q{object-src 'none'; }
		. q{base-uri 'none'; }
		. q{frame-ancestors blip.town staging-blip.town; }
		. q{img-src 'self' https:; }
		. q{font-src 'self' https:; }
		. q{style-src 'self' 'unsafe-inline' https:; }
		. q{script-src 'self'; }
		. q{frame-src 'self' https:; }
		. q{connect-src 'self'; },
	);

	if ($app->mode eq 'production') {
		my %log_pipe;
		$app->log->handle(undef);
		$app->log->format(sub {
			my ($time, $level, @lines) = @_;
			return "[$$] [$level] @lines\n";
		});
		$app->log->on(
			message => sub {
				my ($log, $level, @lines) = @_;
				my $pipe = $log_pipe{$level} //= do {
					my $logger = IO::Pipe->new;
					$logger->writer('/usr/bin/logger', '-t', 'bliptown', '-p', $app->config->{app_log_priority}->{$level});
					$logger->autoflush(1);
					$logger;
				};
				$pipe->print(encode('UTF-8', $log->format->(time, $level, @lines)))
					or undef $log_pipe{$level};
			}
		);
	}

	$app->secrets([
		$ENV{BLIPTOWN_SECRET_OLD},
		$ENV{BLIPTOWN_SECRET_NEW},
	]);

	my $cookie_name = $app->mode eq 'production' ? '__Host-bliptown' : 'bliptown';
	$app->sessions->cookie_name($cookie_name);
	$app->sessions->secure(1) if $app->mode eq 'production';
	$app->sessions->encrypted(1);

	$app->max_request_size(1024 * 1024 * 250);

	delete $app->static->extra->{'favicon.ico'};

	$app->hook(
		after_dispatch => sub {
			my $c = shift;
			return unless $app->mode eq 'production';
			return unless $c->res->code && $c->res->code == 500;

			my %data = (
				content => $c->stash('exception') // '500 internal server error',
				method => $c->req->method,
				url => $c->req->url->to_abs,
				date => strftime("%a, %d %b %Y %H:%M:%S %z", localtime),
				host => $ENV{BLIPTOWN_DOMAIN},
				id => substr(generate_secret, 0, 32),
			);

			my $template = Mojo::Template->new(vars => 1);
			my $content = $template->render(<<'EOF', \%data);
From: Bliptown Mayor <support@blip.town>
To: Bliptown Mayor <support@blip.town>
Date: <%= $date %>
Message-ID: <%= $id %>@<%= $host %>
Subject: Internal Server Error

We regret to inform you that Bliptown has suffered an internal server
error. Here are the details:

<%= $method %> <%= $url %>

<%= $content %>
EOF

			my $email = Bliptown::Model::Email->new;
			$email->send_email({
				recipient => 'support@blip.town',
				content => $content,
			})
		}
	);

	$app->helper(
		sqlite => sub {
			my $db = path($ENV{BLIPTOWN_DB});
			state $sql = Mojo::SQLite->new("sqlite:$db");
			return $sql;
		}
	);

	my $migrations_path = $app->home->child('migrations.sql');
	$app->sqlite->migrations->from_file($migrations_path)->migrate($ENV{BLIPTOWN_DB_SCHEMA});

	$app->helper(
		db => sub {
			my $c = shift;
			state $db = $c->sqlite->db;
			$db->query("PRAGMA busy_timeout = 10000");
			return $db;
		}
	);

	$app->helper(
		geoip => sub {
			my $db = path($ENV{BLIPTOWN_GEOIP_DB});
			state $reader = Geo::Location::IP::Database::SimpleReader->new(
				file => $db,
				locales => ['en']
			);
			return $reader;
		}
	);

	$app->helper(
		ipc => sub {
			state $ipc = Bliptown::Model::IPC->new;
			return $ipc;
		}
	);

	$app->helper(
		customer => sub {
			my $c = shift;
			return Bliptown::Model::Customer->new(
				util => $c->util,
			);
		}
	);

	$app->helper(
		checkout => sub {
			my $c = shift;
			return Bliptown::Model::Checkout->new(
				util => $c->util,
			);
		}
	);

	$app->helper(
		user => sub {
			my $c = shift;
			return Bliptown::Model::User->new(
				db => $c->db,
				customer => $c->customer,
			);
		}
	);

	$app->helper(
		page => sub {
			my $c = shift;
			return Bliptown::Model::Page->new(
				user => $c->user,
				metadata => $c->metadata,
				mustache => $c->mustache,
				util => $c->util
			);
		}
	);

	$app->helper(
		metadata => sub {
			return Bliptown::Model::Metadata->new;
		}
	);

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
		}
	);

	$app->helper(
		file => sub {
			return Bliptown::Model::File->new;
		}
	);

	$app->helper(
		token => sub {
			my $c = shift;
			return Bliptown::Model::Token->new(
				db => $c->db
			);
		}
	);

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
			my $c = shift;
			return Bliptown::Model::DNS->new(
				util => $c->util,
			);
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
		}
	);

	$app->helper(
		get_req_user_path => sub {
			my $c = shift;
			my $path = $c->stash('req_user_path');
			unless ($path) {
				my $host = $c->req->url->to_abs->host;
				return unless $host;
				if ($host =~ /(?:^|\.)\Q$ENV{BLIPTOWN_DOMAIN}\E$/ || $host eq 'localhost') {
					my @host_parts = split(/\./, $host);
					my $username = @host_parts >= 3 ? $host_parts[-3] : 'mayor';
					$path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
				}
				else {
					$path = path($ENV{BLIPTOWN_DATA_HOME}, 'domains', $host);
					-l $path ? $path = $path->realpath : return;
				}
				$c->stash(req_user_path => $path);
			};
			return $path;
		}
	);

	$app->helper(
		get_cur_user_path => sub {
			my $c = shift;
			my $username = $c->session('username');
			return unless $username;
			my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username);
			return unless -d $path;
			return $path->realpath;
		}
	);

	$app->helper(
		get_req_username => sub {
			my $c = shift;
			my $req_username = $c->stash('req_username');
			unless ($req_username) {
				my $path = $c->get_req_user_path;
				return unless $path;
				$req_username = ${$path->to_array}[-1];
				$c->stash(req_username => $req_username);
			}
			return $req_username;
		}
	);

	$app->helper(
		get_user_custom_domains => sub {
			my ($c, $username) = @_;
			my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, '_domains.txt');
			return unless -f $path;
			my $domain_re = qr/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
			my @domains = grep { $_ =~ $domain_re } split("\n", $path->slurp);
			return @domains;
		}
	);

	$app->helper(
		get_user_prettydate_fmt => sub {
			my ($c, $username) = @_;
			my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, '_prettydate.txt');
			my $style = -f $path ? $c->util->read_file_line($path) : 'euro';
			my $fmt = $c->app->config->{prettydate_fmts}->{$style};
			return $fmt;
		}
	);

	$app->helper(
		get_file => sub {
			my ($c, $slug, $ext) = @_;
			my $user_path = $c->get_req_user_path->realpath;
			return unless $user_path;
			my $path = path($user_path, $slug)->to_abs;
			if (-f $path && -r $path) {
				$path = $path->realpath;
				return unless index($path, $user_path) == 0;
				return $path;
			}

			my $defaults_path = path($c->app->static->paths->[0], 'defaults')->realpath;
			my $fallback_path = path($defaults_path, $slug)->to_abs;
			if (-f $fallback_path && -r $fallback_path) {
				$fallback_path = $fallback_path->realpath;
				return unless index($fallback_path, $defaults_path) == 0;
				return $fallback_path;
			}

			return if $ext;

			foreach my $ext (@{$c->app->config->{render_exts}}) {
				my $path_ext = path($user_path, "$slug.$ext")->to_abs;
				if (-f $path_ext && -r $path_ext) {
					$path_ext = $path_ext->realpath;
					next unless index($path_ext, $user_path) == 0;
					return $path_ext;
				}
			}
			return;
		}
	);

	my $visitor_log;

	$app->helper(
		visitor_log => sub {
			$visitor_log //= do {
				my $logger = IO::Pipe->new;
				$logger->writer('/usr/bin/logger', '-t', 'bliptown-visitor', '-p', $app->config->{visitor_log_priority});
				$logger->autoflush(1);
				Mojo::Log->new(
					level => 'info',
					handle => $logger,
					format => sub {
						my ($time, $level, @lines) = @_;
						return join("\t", int($time), @lines) . "\n";
					},
				);
			};
		}
	);

	$app->defaults(
		site_title => 'Bliptown',
		page_title => 'Untitled',
		description => 'A very talented artist',
		author => 'Anonymous',
		scripts => [],
		username => '',
		customize => 0,
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
		before_dispatch => sub {
			my $c = shift;
			my $req_url = $c->req->url->to_abs;
			my $host = $req_url->host;
			return unless $host;
			return if $host =~ /(?:^|\.)\Q$ENV{BLIPTOWN_DOMAIN}\E$/;
			return if $host eq 'localhost';
			my $username = $c->get_req_username;
			return unless $username;
			my @domains = $c->get_user_custom_domains($username);
			return unless grep { $_ eq $host } @domains;
			return if $host eq $domains[0];
			my $url = $req_url->host($domains[0]);
			$c->redirect_to($url);
			return;
		}
	);

	$app->hook(
		before_routes => sub {
			my $c = shift;
			my $req_url = $c->req->url->to_abs;
			my $host = $req_url->host;
			return unless $host;

			if ($host eq "cdn-origin.$ENV{BLIPTOWN_DOMAIN}") {
				my $req_username = shift @{$req_url->path->parts};
				return unless $req_username;
				my $slug = join '/', @{$req_url->path->parts};
				my $path = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $req_username, $slug);
				if (-f $path) {
					my $max_age = 365 * 24 * 60 * 60;
					$c->res->headers->cache_control("public, must-revalidate, max-age=$max_age");
					return $c->reply->file($path);
				}
			}
			elsif ($c->app->mode eq 'production' && $c->session('username') && $c->session('username') eq $c->get_req_username) {
				$c->res->headers->cache_control('no-cache');
			}
			elsif ($c->app->mode eq 'production') {
				$c->res->headers->cache_control('public, max-age=60, stale-while-revalidate=600');
				$c->res->headers->vary('Cookie');
			}
			return;
		}
	);

	$app->hook(
		after_dispatch => sub {
			my $c = shift;
			my $res = $c->res;
			return if $res->code && $res->code >= 300 && $res->code < 400;
			
			my $csp = $c->app->config->{csp_default} // '';
			my $endpoint_name = eval { $c->match->endpoint->name };

			if ($endpoint_name && ($endpoint_name eq 'render_page' || $endpoint_name eq 'render_private_page')) {
				$csp = $c->app->config->{csp_pages} // '';
			}

			$res->headers->content_security_policy($csp);
			return;
		}
	);

	my $r = $app->routes->under(sub {
		my $c = shift;
		my $path = $c->req->url->path;
		if ($path =~ /[\x00-\x1F\x7F]/) {
			$c->reply->not_found;
			return;
		}
		return 1;
	});

	$r->post('/_login')->to(controller => 'Users', action => 'generate_login')->name('generate_login');
	$r->post('/_logout')->to(controller => 'Users', action => 'generate_logout')->name('generate_logout');
	$r->get('/_logout')->to(controller => 'Users', action => 'user_logout')->name('user_logout');
	$r->get('/_auth')->to(controller => 'Users', action => 'user_auth')->name('user_auth');
	$r->get('/_login')->to(controller => 'Users', action => 'user_login')->name('user_login');

	$r->post('/_track')->to(controller => 'Analytics', action => 'track_visit')->name('track_visit');

	$r->get('/_mysite' => sub {
		my $c = shift;
		my $username = $c->session('username');

		unless ($username) {
			$c->flash(info => 'Login required');
			return $c->redirect_to('/');
		}

		my @custom_domains = $c->get_user_custom_domains($username);
		my $host = @custom_domains ? $custom_domains[0] : "$username.$ENV{BLIPTOWN_DOMAIN}";
		my $url = $c->util->create_bliptown_url({
			host => $host,
		});

		return $c->redirect_to($url);
	})->name('my_site');

	my $protected = $r->under(sub {
		my $c = shift;
		my $username = $c->session('username');
		my $req_username = $c->get_req_username;
		return unless $req_username;
		if ($c->req->method ne 'GET') {
			my $v = $c->validation;
			if ($v->csrf_protect->has_error('csrf_token')) {
				$c->render(
					status => 403,
					format => 'txt',
					text => '403 Forbidden: bad or missing CSRF token.'
				);
				return;
			}
		}

		if ($username && $username eq $req_username) {
			return 1;
		}
		else {
			$c->flash(info => 'Login required');
			$c->render(
				status => 403,
				template => 'message',
				page_title => '403 Forbidden',
				content => '403 Forbidden: sorry, this page requires a login.'
			);
			return;
		}
	});

	my $private = $protected->under(sub {
		my $c = shift;
		$c->stash(prefix => 'private');
		return 1;
	});

	my $block_demo = sub {
		my $c = shift;
		my $username = $c->session('username') // '';
		if ($username eq $ENV{BLIPTOWN_DEMO_USER}) {
			$c->render(
				status => 403,
				template => 'message',
				page_title => '403 Forbidden',
				content => '403 Forbidden: demo user cannot perform this action.'
			);
			return;
		}
		return 1;
	};

	$private->get('/_raw/private/*catchall')->to(controller => 'Pages', action => 'render_raw', catchall => '')->name('render_private_raw');
	$private->get('/private/*catchall')->to(controller => 'Pages', action => 'render_page', catchall => '')->name('render_private_page');

	$protected->post('/_edit')->to(controller => 'Pages', action => 'save_page')->name('save_page');
	$protected->get('/_new/*catchall')->to(controller => 'Pages', action => 'new_page', catchall => '')->name('new_page');
	$protected->get('/_edit/*catchall')->to(controller => 'Pages', action => 'edit_page', catchall => '')->name('edit_page');

	$protected->post('/_new_directory')->to(controller => 'Files', action => 'new_directory')->name('new_directory');
	$protected->post('/_new')->to(controller => 'Files', action => 'new_file')->name('new_file');
	$protected->post('/_delete')->to(controller => 'Files', action => 'delete_files')->name('delete_files');
	$protected->post('/_rename')->to(controller => 'Files', action => 'rename_files')->name('rename_files');
	$protected->post('/_backup')->to(controller => 'Files', action => 'backup_file')->name('backup_file');
	$protected->post('/_download_site')->to(controller => 'Files', action => 'download_site')->name('download_site');
	$protected->under($block_demo)->post('/_upload')->to(controller => 'Files', action => 'upload_files')->name('upload_files');
	$protected->get('/_files/*catchall')->to(controller => 'Files', action => 'list_files', catchall => '')->name('list_files');

	$protected->under($block_demo)->post('/_settings')->to(controller => 'Settings', action => 'save_settings')->name('save_settings');
	$protected->get('/_settings')->to(controller => 'Settings', action => 'list_settings')->name('list_settings');

	$protected->get('/_stats')->to(controller => 'Analytics', action => 'render_stats')->name('render_stats');

	$protected->under($block_demo)->get('/_billing')->to(controller => 'Users', action => 'billing_session')->name('billing_session');

	$r->get('/_health')->to(controller => 'Health', action => 'health_check')->name('health_check');
	$protected->get('/_error' => sub {
		my $c = shift;
		$c->reply->exception('500 internal server error test: everything has gone wrong!');
		return;
	})->name('error_check');

	$r->get('/style.css')->to(controller => 'Pages', action => 'render_style')->name('render_style');

	$r->get('/_raw/*catchall')->to(controller => 'Pages', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Pages', action => 'render_page', catchall => '')->name('render_page');
}

return 1;

=head1 NAME

Bliptown - A portfolio platform for artists and creatives.

Bliptown is a a flat-file CMS using the Perl Mojolicious web framework
and Markdown files. There is a small SQLite database for user settings
and credentials. The server runs NetBSD.

=head1 DESCRIPTION

=head2 Commands

=over

=item * Install dependencies: C<carmel install>

=item * Run tests: C<carmel exec prove>

=item * Run a single test: C<carmel exec prove t/controller_files.t>

=item * Syntax check a file: C<carmel exec perl -w -c lib/Bliptown.pm>

=item * Run a development server: C<carmel exec morbo script/bliptown>

=item * On macOS, run the helper locally under launchd with
  F<etc/town.blip.helper.plist> in inetd compatibility mode

=item * Inspect the outgoing mail queue: F<bin/msmtp-listqueue.sh>

=item * Send outgoing mail: F<bin/msmtp-runqueue.sh>

=item * The deployed app starts with C<perl -Ilocal/lib/perl5/script/bliptown>

=item * Generate F<stats.json> per user from the shared visitor log
  F</var/log/bliptown/visitor.log>: F<bin/bliptown_analytics> (run hourly
  by F</etc/hourly.local>)

=back

=head2 Architecture

=over

=item * F<lib/Bliptown.pm> wires config, helpers, hooks, and routes.

=item * Controllers live in F<lib/Bliptown/Controller/>; models/helpers live
  in F<lib/Bliptown/Model/>.

=item * User content under C<BLIPTOWN_DATA_HOME/users/<username>>
  symlinked to user's home directory F<~/site>, while account state
  lives in SQLite via C<Mojo::SQLite>.

=item * Logging goes through syslogd. C<Mojo::Log> levels are
  dispatched per level to logger(1) (facility local0, exact-severity
  routes in F</etc/syslog.conf> give F<info.log> and F<error.log>);
  raw fd 1/2 output is caught by F<etc/rc.d/bliptown> as local0.notice
  into F<daemon.log>. The visitor log writes to facility local1 and
  gives F<visitor.log> which is consumed hourly by
  F<bin/bliptown_analytics>.

=item * Privileged filesystem operations are not done directly in
  controllers. They go through F<bin/bliptown_helper>, an inetd(8)
  service listening on 127.0.0.1:9000, over a TCP socket using JSON
  (C<Model::IPC>). Allowed commands: C<write_blob>, C<update_file>,
  C<rename_files>, C<delete_files>, C<backup_file>, C<make_directory>,
  C<download_site>.

=item * Markdown page rendering is handled by C<Model::Page>, which combines
  YAML frontmatter, Mustache-style templating, md4c rendering, and DOM
  post-processing.

=item * Routing is host-aware: C<get_req_username> maps subdomains/custom
  domains to a user, and the page/file helpers always resolve paths
  relative to C<BLIPTOWN_DATA_HOME/users>.

=item * Custom domains are verified in C<Model::DNS>, which checks that a
  domain's A/AAAA records point at the server and that a C<_bliptown>
  TXT record matches the owning user.

=item * User login is passwordless: C<Controller::Users> and C<Model::Email>
  implement a magic-link flow (one-time tokens in SQLite, emailed as
  RFC 822 messages piped to C<$BLIPTOWN_SENDMAIL_PATH>).

=item * Outgoing mail has no local MTA: C<BLIPTOWN_SENDMAIL_PATH>
 points to s sendmail compatible binary, triggering
 F<bin/msmtp-enqueue.sh>, which spools messages in
 F</var/db/msmtp/queue> and hands them to msmtp through
 F<bin/msmtp-runqueue.sh> when the smarthost is reachable.
 F<etc/msmtprc> holds the smarthost account configuration and
 F</etc/msmtp.passwd> holds the password.

=item * Billing (C<Model::Checkout>, C<Model::Customer>) talks to the Stripe
  REST API directly via C<Mojo::UserAgent>.

=item * Static assets are served through Bunny CDN (C<cdn.blip.town>):
  the C<cdn-origin.BLIPTOWN_DOMAIN> route serves user files for the
  CDN to pull, and file deletions purge the CDN through its API
  (C<Model::File>, C<BLIPTOWN_CDN_API_HOST>/C<BLIPTOWN_CDN_API_KEY>).

=item * F<etc/weekly.local> refreshes the Bunny CDN edge-server IP
  allowlists and the GeoLite2 country database.

=item * nginx terminates TLS (uacme certificates), proxies to the
  Mojolicious prefork server on 127.0.0.1:8080, rate-limits per IP,
  and sends obvious probes (F<.php> requests, control characters) to
  F<bin/rate_limit>, an inetd(8) service on 127.0.0.1:9666 that adds
  the offender to the npf C<rate_limit> table; F<etc/hourly.local>
  expires entries after 24 hours.

=item * F<bin/npf-badhost> (run by F<etc/daily.local>) rebuilds
  F</etc/blocklist.txt> from public IP blocklists and loads it into
  the npf C<blocklist> table.

=item * F<etc/blocklistd.conf> defines rules for C<blocklistd> to track
  and block brute-force SSH login attempts.

=item * Daily maintenance (F<etc/daily.local>): dump(8) backups to a
  remote storage box with checksum verification, SQLite C<.backup>
  snapshots to F</var/db/bliptown/backups> with 30-day retention,
  expired login-token cleanup, database integrity check, and
  certificate renewal (uacme with the F<bin/nsupdate.sh> dns-01 hook
  for internal wildcard certificates,
  F</usr/pkg/libexec/uacme/uacme.sh> http-01 for user certificates).
  The staging instance syncs users, domains, and backups from
  production.

=item * Users also have SSH access to their site directory:
  F<bin/bliptown-dispatch.sh> as the forced command dispatches
  sftp/git-shell/rsync and drops other logins into F<bin/bliptown-shell>,
  a restricted interactive shell.

=item * F<skel/site/> is the skeleton for a new user's site
  (F<index.md>, F<_template.md>, F<style.css>, F<_header.md>, etc.).

=item * Shared page themes are served from the C<BLIPTOWN_THEME_USER>.
  F<style.css> parameter C<theme> selects theme from
  F<users/BLIPTOWN_THEME_USER/THEME.css>, otherwise serves user's
  style.css.

=back

=head2 Conventions

=over

=item * Use the existing C<Mojo::Base> package style, keep modules ending
  with C<return 1;>, and prefer small controller actions that delegate
  work to models or IPC helpers.

=item * Keep file access constrained to the user root and reuse
  C<get_file>, C<get_slug>, and C<ipc-E<gt>send_message> instead of
  open-coding path resolution or helper calls.

=item * Preserve the existing page syntax: C<---> YAML frontmatter,
  C<{{ }}> variables, C<{{ # ... }}> sections, and C<{{ E<gt> ... }}>
  partials.

=item * Preserve the current error flow: helper failures are surfaced
  with C<reply-E<gt>exception>, while user-facing validation issues use
  flash messages and redirects.

=item * C<demo> is treated as a restricted account for destructive
  actions.

=item * Tests use F<t/lib/BliptownTest.pm> to a initialize test
  environment.

=item * Tests avoid the real F<bliptown_helper> socket by swapping in
  F<t/lib/FakeIPC.pm> for the C<ipc> helper.

=item * Tests avoid production operations with F<t/lib/FakeDNS.pm> for
  DNS resolution, F<t/lib/FakeEmail.pm> for sending email, and
  F<t/lib/FakeVisitorLog.pm> for visitor logs.

=item * Prefer simple, pragmatic, clear, elegant code. Follow the I<12
  Factor App> methodology, except for "Twelve-factor apps also do not
  rely on the implicit existence of any system tools" as Bliptown is
  deeply integrated with NetBSD.

=back

=head2 Environment Variables

All runtime configuration comes from the environment, sourced from
F<$HOME/.envrc> by F<script/bliptown>. See F<.envrc.def> for the full
list.

=over

=item * C<BLIPTOWN_SECRET_OLD>, C<BLIPTOWN_SECRET_NEW>: application
  secrets for sessions and CSRF tokens; old first so rotated secrets
  keep validating existing cookies.

=item * C<BLIPTOWN_HEALTH_FILE>: file touched by the prefork heartbeat
  hook and read by the C<_health> route.

=item * C<BLIPTOWN_HELPER_HOST>, C<BLIPTOWN_HELPER_PORT>: TCP endpoint
  of the privileged helper (F<bin/bliptown_helper> via inetd).

=item * C<BLIPTOWN_DOMAIN>: the primary domain; used for subdomain to
  username mapping, custom-domain checks, CSP frame-ancestors, and
  outgoing email.

=item * C<BLIPTOWN_SCHEME>, C<BLIPTOWN_PORT>: scheme and optional port
  used when generating URLs (magic links, C<_mysite> redirect).

=item * C<BLIPTOWN_IPV4>, C<BLIPTOWN_IPV6>: the server addresses that a
  custom domain's A/AAAA records must match (C<Model::DNS>).

=item * C<BLIPTOWN_DATA_HOME>: root of all per-instance data:
  F<users/>, F<domains/>, F<repos/>, F<stats/>.

=item * C<BLIPTOWN_DB>, C<BLIPTOWN_DB_SCHEMA>: SQLite database path and
  migration version to migrate to (F<migrations.sql>).

=item * C<BLIPTOWN_GEOIP_DB>: GeoLite2 country database (F<.mmdb>) used
  by the C<geoip> helper for visitor stats.

=item * C<BLIPTOWN_LOG_HOME>: log directory for instance logs.

=item * C<BLIPTOWN_MD4C_HTML_LIB>: paths to the md4c shared libraries
  used via FFI by C<Model::Page>.

=item * C<BLIPTOWN_SENDMAIL_PATH>: sendmail-compatible binary used to
  send outgoing mail; points at F</usr/sbin/sendmail>.

=item * C<BLIPTOWN_CDN_API_HOST>, C<BLIPTOWN_CDN_API_KEY>: Bunny CDN
  purge API endpoint and access key (C<Model::File>).

=item * C<BLIPTOWN_STRIPE_API_KEY>, C<BLIPTOWN_STRIPE_PRICE_ID>: Stripe
  REST API credentials and subscription price (C<Model::Checkout>,
  C<Model::Customer>).

=item * C<BLIPTOWN_DEMO_USER>: the restricted demo account, blocked from
  destructive actions.

=item * C<BLIPTOWN_THEME_USER>: the account serving shared theme CSS.

=back

=head2 System Installation

NetBSD installation:

  > vesa on
  > boot

Follow installation prompts.

Ensure boot without black screen:

  # cat <<EOF > /boot.cfg
  menu=Boot normally:rndseed /var/db/entropy-file; vesa on; boot
  menu=Boot single user:rndseed /var/db/entropy-file; vesa on; boot -s
  menu=Drop to boot prompt: vesa on; prompt
  default=1
  timeout=5
  clear=1

Set up system user su privileges:

  # pkgin install priv
  # cat <<EOF > /usr/pkg/etc/rnkn
  0:root:0100000
  # cd /usr/pkg/bin
  # ln -s priv su-root
  # passwd root

Set up mail aliases:

  # cat <<EOF >> /etc/mail/aliases
  root: rnkn@rnkn.xyz
  mayor: support@blip.town

Set up bliptown user and _pubkeys.txt:

  # useradd -m bliptown
  # mkdir -p /home/bliptown/users/rnkn/
  # cat <<EOF > /home/bliptown/users/rnkn/_pubkeys.txt
  ssh-ed25519 AAAA... rnkn@sevastopol

Secure SSH:

  # cat <<EOF > /etc/ssh/sshd_config
  PermitRootLogin no
  StrictModes no
  DenyUsers demo
  AuthorizedKeysFile /home/bliptown/users/%u/_pubkeys.txt
  PasswordAuthentication no
  UsePAM no
  DenyUsers demo
  ForceCommand /usr/local/www/bliptown/bin/bliptown-dispatch.sh
  Match User bliptown
    AuthorizedKeysFile .ssh/authorized_keys
    ForceCommand none
  Match Group wheel
    ForceCommand none
  # service sshd reload

=head2 Configure Networking

Set up IPv6:

  # cat <<EOF > /etc/ifconfig.vioif0
  inet6 2a01:4f8:1c19:6498::1/64
  up
  # cat <<EOF >> /etc/rc.conf
  defaultroute6="fe80::1%vioif0"
  # service network restart

=head2 Package Installation

Install required packages:

  # pkgin install curl git-base git-docs jq libffi libmaxminddb md4c \
	mksh monit msmtp nano nginx perl p5-Carton pkgconf rlwrap rsync sqlite3 \
	sysupgrade tree uacme

=head2 Installation

Install Bliptown app:

  # mkdir -p /usr/local/www/bliptown
  # chown -R bliptown /usr/local/www/bliptown
  $ cd /usr/local/www/bliptown
  $ git clone /home/rnkn/git/bliptown.git .
  $ cd bliptown
  $ cp .envrc.def $HOME/.envrc

Add environemtn to F<.envrc>.

  $ cd /usr/local/www/bliptown
  $ carton install --deployment

  # cd etc
  # cp hourly.local daily.local weekly.local \
    inetd.conf npf.conf blocklistd.conf newsyslog.conf usermgmt.conf \
	gitignore /etc/
  # cp monitrc /usr/pkg/etc/monit/
  # cp msmtprc /usr/pkg/etc/
  # umask 0077
  # echo ************* > /etc/msmtp.passwd
  # umask 0022
  # cat syslog.conf >> /etc/syslog.conf
  local0.none,local1.none  /var/log/messag
  local0.<=info  /var/log/bliptown/info.log
  local0.>=err  /var/log/bliptown/error.log
  local0.=notice  /var/log/bliptown/daemon.log
  local1.info  /var/log/bliptown/visitor.log
  # service syslogd restart
  # cat motd >> /etc/motd
  # cp nginx.conf /usr/pkg/etc/nginx/
  # install -m 555 -o root -g bin rc.d/bliptown /etc/rc.d/

=head2 Services

Start required services:

  # echo inetd=YES >> /etc/rc.conf
  # echo inetd_env="PATH=/usr/pkg/bin:/usr/pkg/sbin:/bin:/sbin:/usr/bin:/usr/sbin" >> /etc/rc.conf
  # echo npf=YES >> /etc/rc.conf
  # echo blocklistd=YES >> /etc/rc.conf
  # echo nginx=YES >> /etc/rc.conf
  # echo bliptown=YES >> /etc/rc.conf
  # echo monit=YES >> /etc/rc.conf
  # echo fetch_pkg_vulnerabilities=YES >> /etc/daily.conf
  # mkdir -p /var/log/bliptown
  # chown -R bliptown /var/log/bliptown
  # service nginx start
  # service bliptown start

=head2 SSL

  # umask 0037
  # mkdir -p /etc/ssl/private
  # chown -R root:nginx /etc/ssl/private
  # cat <<EOF > /etc/ssl/private/porkbun-keys.json
  {
    "apikey": "...",
    "secretapikey": "..."
  }
  # uacme -c /etc/ssl new support@blip.town

=head2 Periodic Scripts

Run periodic scripts:

  # sh /etc/hourly.local
  # sh /etc/daily.local
  # sh /etc/weekly.local
  # crontab -e
  0 * * * * /bin/sh /etc/hourly.local

=head2 Set up GeoLite2

  # crontab -l | head -2
  MAXMIND_ID=...
  MAXMIND_KEY=..._mmk

=head1 COPYRIGHT & LICENSE

Copyright (C) 2025-2026, Paul W. Rankin

This program is free software, you can redistribute it and/or modify
it under the terms of the Artistic License version 2.0.

=cut
