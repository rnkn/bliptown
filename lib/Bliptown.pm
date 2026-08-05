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
		render_exts => [ qw(md html css js txt) ],
		cdn_exts => [ qw(eot ttf woff woff2 jpg jpeg png webp gif mp3 mp4 mpeg webm) ],
	);

	$app->secrets([
		$ENV{BLIPTOWN_SECRET}
	]);

	$app->sessions->cookie_name('bliptown');
	$app->sessions->default_expiration(30 * 24 * 60 * 60);

	$app->max_request_size(1024 * 1024 * 100);

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
				req_user => $c->get_req_user,
				user => $c->user,
				metadata => $c->metadata,
				util => $c->util
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
		get_req_user => sub {
			my $c = shift;
			my $host = $c->req->url->to_abs->host;
			return unless $host;
			$host =~ s/^www\.//;
			my $domain = $ENV{BLIPTOWN_DOMAIN};
			my $username = '';
			if ($host =~ /\Q$domain\E$/) {
				my @host_array = split(/\./, $host);
				$username = @host_array >= 3 ? $host_array[-3] : 'mayor';
			} else {
				my $user_rec = $c->user->read_user({
					key => 'custom_domain',
					custom_domain => $host,
				});
				return '' unless $user_rec;
				$username = $user_rec->{username};
			}
			return '' unless $username;
			my $dir = path($ENV{BLIPTOWN_USER_HOME}, $username);
			return '' unless -d $dir;
			return $username;
		});

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			my $req_user = $c->get_req_user;
			return unless $req_user;
			my $root = path($ENV{BLIPTOWN_USER_HOME}, $req_user)->to_abs;
			my $file = path($root, $slug)->to_abs;
			return $file if -f $file;
			foreach my $ext (@{$c->config->{render_exts}}) {
				my $f = path($root, "$slug.$ext")->to_abs;
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
		title => 'Untitled',
		head => '',
		scripts => '',
		username => '',
		user_style => 0,
		show_sidebar => 0,
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
				my $req_user = shift @{$req_url->path->parts};
				return unless $req_user;
				my $path = join '/', @{$req_url->path->parts};
				my $user_home = $ENV{BLIPTOWN_USER_HOME};
				my $file = path($user_home, $req_user, $path);
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
			return $c->reply->file("$file") if -f $file;
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
			$c->redirect_to('/');
			return;
		}

		my $url = Mojo::URL->new;
		$url->scheme($ENV{BLIPTOWN_SCHEME});
		$url->port($ENV{BLIPTOWN_PORT});

		my $user_rec = $c->user->read_user({
			key => 'username',
			username => $username,
		});
		my $domain = $ENV{BLIPTOWN_DOMAIN};
		my $custom_domain = $user_rec->{custom_domain};
		if ($custom_domain) {
			$url->host($custom_domain);
		}
		else {
			$url->host("$username.$domain");
		}
		$c->redirect_to($url)
	})->name('my_site');

	my $protected = $r->under(
		sub {
			my $c = shift;
			my $username = $c->session('username');
			my $req_user = $c->get_req_user // '';
			if ($username && $username eq $req_user) {
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
		if ($username eq 'demo') {
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
