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
use Bliptown::Model::Customer;
use Bliptown::Model::Checkout;
use Bliptown::Model::IPC;
use Bliptown::Model::Email;
use Bliptown::Model::Token;
use Bliptown::Model::Util;

sub startup {
	my $app = shift;

	my $health_file = path($ENV{BLIPTOWN_HEALTH_FILE})->remove->touch;
	$app->log->info("Creating worker health file \"$health_file\"");

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

	$app->sessions->cookie_name('bliptown');
	$app->sessions->default_expiration(30 * 24 * 60 * 60);

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
			return Bliptown::Model::Mustache->new(
				user => $c->user,
				metadata => $c->metadata,
				util => $c->util,
				prettydate_fmt => $c->get_user_prettydate_fmt($c->get_req_username),
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
			return Bliptown::Model::Util->new;
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
		get_user_home_path => sub {
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
				my $path = $c->get_user_home_path;
				return unless $path;
				$req_username = ${$path->to_array}[-1];
			}
			return $req_username;
		});

	$app->helper(
		get_user_domain => sub {
			my ($c, $username) = @_;
			my $file = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, '_domain.txt');
			if (-f $file) {
				my $domain = $c->util->read_file_line($file);
				my $domain_re = qr/^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
				return $domain if $domain =~ $domain_re;
			}
			return "$username.$ENV{BLIPTOWN_DOMAIN}";
		});

	$app->helper(
		get_user_prettydate_fmt => sub {
			my ($c, $username) = @_;
			my $file = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $username, '_prettydate.txt');
			my $style = -f $file ? $c->util->read_file_line($file) : 'euro';
			my $fmt = $c->config->{prettydate}->{$style};
			return $fmt;
		});

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			my $home = $c->get_user_home_path;
			return unless $home;
			my $file = path($home, $slug)->to_abs;
			return $file if -f $file;
			foreach my $ext (@{$c->config->{render_exts}}) {
				my $f = path($home, "$slug.$ext")->to_abs;
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
		title => '',
		description => '',
		author => '',
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
			$c->app->sessions->cookie_domain($host);

			if ($host eq "cdn-origin.$ENV{BLIPTOWN_DOMAIN}") {
				my $req_username = shift @{$req_url->path->parts};
				return unless $req_username;
				my $slug = join '/', @{$req_url->path->parts};
				my $file = path($ENV{BLIPTOWN_DATA_HOME}, 'users', $req_username, $slug);
				if (-f $file) {
					my $max_age = 24 * 60 * 60;
					$c->res->headers->cache_control("public, must-revalidate, max-age=$max_age");
					return $c->reply->file($file);
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
			my $file = path('/var/www/acme/', $c->param('file'));
			if (-f $file) {
				return $c->reply->file("$file");
			}
			return $c->reply->not_found;
		})->name('acme_challenge');

	$r->get('/login')->to(controller => 'Users', action => 'user_login')->name('user_login');
	$r->post('/login')->to(controller => 'Users', action => 'generate_login')->name('generate_login');
	$r->get('/auth')->to(controller => 'Users', action => 'user_auth')->name('user_auth');
	$r->get('/logout')->to(controller => 'Users', action => 'user_logout')->name('user_logout');

	$r->get('/track/:rand')->to(controller => 'Analytics', action => 'track_visit')->name('track_visit');

	$r->get('/mysite' => sub {
		my $c = shift;
		my $username = $c->session('username');

		unless ($username) {
			$c->flash(info => 'Login required');
			return $c->redirect_to('/');
		}

		my $url = Mojo::URL->new;
		$url->scheme($ENV{BLIPTOWN_SCHEME});
		$url->port($ENV{BLIPTOWN_PORT});
		my $host = $c->get_user_domain($username);
		$url->host($host);

		return $c->redirect_to($url);
	})->name('my_site');

	my $protected = $r->under(
		sub {
			my $c = shift;
			my $username = $c->session('username');
			my $req_username = $c->get_req_username;
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

	$private->get('/raw/private/*catchall')->to(controller => 'Pages', action => 'render_raw', catchall => '')->name('render_private_raw');
	$private->get('/private/*catchall')->to(controller => 'Pages', action => 'render_page', catchall => '')->name('render_private_page');

	$protected->get('/new/*catchall')->to(controller => 'Pages', action => 'new_page', catchall => '')->name('new_page');
	$protected->get('/edit/*catchall')->to(controller => 'Pages', action => 'edit_page', catchall => '')->name('edit_page');
	$protected->post('/edit/*catchall')->to(controller => 'Pages', action => 'save_page', catchall => '')->name('save_page');

	$protected->post('/files/*catchall')->to(controller => 'Files', action => 'file_action', catchall => '')->name('file_action');
	$protected->get('/files/*catchall')->to(controller => 'Files', action => 'list_files', catchall => '')->name('list_files');
	$protected->get('/rename/*catchall')->to(controller => 'Files', action => 'rename_file', catchall => '')->name('rename_file');
	$protected->get('/delete/*catchall')->to(controller => 'Files', action => 'delete_file', catchall => '')->name('delete_file');
	$protected->get('/backup/*catchall')->to(controller => 'Files', action => 'backup_file', catchall => '')->name('backup_file');
	$protected->under($block_demo)->post('/upload/*catchall')->to(controller => 'Files', action => 'upload_files', catchall => '')->name('upload_files');

	$protected->get('/settings')->to(controller => 'Settings', action => 'list_settings')->name('list_settings');
	$protected->under($block_demo)->post('/settings')->to(controller => 'Settings', action => 'save_settings')->name('save_settings');

	$protected->get('/snapshots')->to(controller => 'Snapshots', action => 'list_snapshots')->name('list_snapshots');
	$protected->get('/snapshots/new')->to(controller => 'Snapshots', action => 'take_snapshot')->name('take_snapshot');
	$protected->get('/snapshots/download/:hash')->to(controller => 'Snapshots', action => 'download_snapshot')->name('download_snapshot');
	$protected->get('/snapshots/restore/:hash')->to(controller => 'Snapshots', action => 'restore_snapshot')->name('restore_snapshot');
	$protected->get('/snapshots/diff/:hash')->to(controller => 'Snapshots', action => 'render_diff')->name('render_diff');

	$r->get('/health')->to(controller => 'Health', action => 'health_check')->name('health_check');

	$r->get('/style.css')->to(controller => 'Pages', action => 'render_style')->name('render_style');

	$r->get('/raw/*catchall')->to(controller => 'Pages', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Pages', action => 'render_page', catchall => '')->name('render_page');
}

return 1;

=head1 NAME

Bliptown - A portfolio platform for artists and creatives.

=head1 COPYRIGHT & LICENSE

Copyright (C) 2025-2026, Paul W. Rankin

This program is free software, you can redistribute it and/or modify
it under the terms of the Artistic License version 2.0.

=cut
