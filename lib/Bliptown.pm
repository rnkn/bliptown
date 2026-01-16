package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape);
use Mojo::SQLite;
use lib '.';
use Bliptown::Sessions;

use Geo::Location::IP::Database::Reader;

use Bliptown::Model::User;
use Bliptown::Model::Page;
use Bliptown::Model::File;
use Bliptown::Model::IPC;
use Bliptown::Model::TOTP;
use Bliptown::Model::QRCode;
use Bliptown::Model::Token;

sub startup {
	my $app = shift;

	my $health_file = path($ENV{BLIPTOWN_HEALTH_FILE})->remove->touch;
	$app->log->info("Creating worker health file \"$health_file\"");

	$app->config(
		domain => $ENV{BLIPTOWN_DOMAIN},
		scheme => $app->mode eq 'production' ? 'https' : 'http',
		port => $app->mode eq 'production' ? '' : '3000',
		user_home => $ENV{BLIPTOWN_USER_HOME},
		log_home => $ENV{BLIPTOWN_LOG_HOME},
	);

	$app->secrets(
		[ $ENV{BLIPTOWN_SECRET} ]
	);

	my $sessions = Bliptown::Sessions->new(default_expiration => 2592000);
	$app->sessions($sessions);
	$app->sessions->cookie_domain('.' . $app->config->{domain});

	$app->helper(
		sqlite => sub {
			my $db = path($ENV{BLIPTOWN_DB});
			state $sql = Mojo::SQLite->new("sqlite:$db");
			return $sql;
		});

	my $migrations_path = $app->home->child('migrations.sql');
	$app->sqlite->migrations->from_file($migrations_path)->migrate(5);

	$app->helper(
		geoip => sub {
			my $db = path($ENV{BLIPTOWN_GEOIP_DB});
			state $reader = Geo::Location::IP::Database::Reader->new(
				file => $db,
				locales => ['en']
			);
			return $reader;
		});

	$app->helper(
		user => sub {
			my $c = shift;
			return Bliptown::Model::User->new(
				sqlite => $c->sqlite,
				totp => $c->totp,
			);
		});

	$app->helper(
		ipc => sub {
			state $ipc = Bliptown::Model::IPC->new;
			return $ipc;
		});

	$app->helper(
		page => sub {
			return Bliptown::Model::Page->new;
		});

	$app->helper(
		file => sub {
			return Bliptown::Model::File->new;
		});

	$app->helper(
		totp => sub {
			return Bliptown::Model::TOTP->new;
		});

	$app->helper(
		qrcode => sub {
			return Bliptown::Model::QRCode->new;
		});

	$app->helper(
		token => sub {
			my $c = shift;
			return Bliptown::Model::Token->new(
				sqlite => $c->sqlite
			);
		});

	$app->helper(
		get_slug => sub {
			my $slug = shift->req->url->path->to_string;
			$slug = url_unescape($slug);
			$slug =~ s/^\///;
			return $slug;
		});

	$app->helper(
		get_req_user => sub {
			my $c = shift;
			my $host = $c->req->url->to_abs->host;
			return unless $host;
			$host =~ s/^www\.//;
			my $domain = $c->config->{domain};
			my $username;
			if ($host =~ /\Q$domain\E$/) {
				my @host_array = split(/\./, $host);
				$username = @host_array >= 3 ? $host_array[-3] : 'mayor';
			} else {
				my $user = $c->user->read_user(
					{ key => 'custom_domain', custom_domain => $host }
				);
				$username = $user->{username};
			}
			return unless $username;
			my $dir = path($c->config->{user_home}, $username);
			return unless -d $dir;
			return $username;
		});

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			return unless my $req_user = $c->get_req_user;
			my $root = path($c->config->{user_home}, $req_user)->to_abs;
			my $file = path($root, $slug)->to_abs;
			return $file if -f $file;
			$slug = $1 if $slug =~ /(.+)(\..+)$/;
			my @exts = qw(html css js txt md);
			foreach my $ext (@exts) {
				my $f = path($root, "$slug.$ext")->to_abs;
				return $f if -f $f;
			}
			return;
		}
	);

	my %accesslogs;
	$SIG{USR1} = sub {
		undef %accesslogs;
		$app->log->info('Logfile handler rotated');
	};

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
		show_join => 0,
		show_sidebar => 0,
		editable => 0,
		header => '',
		menu => '',
		footer => '',
		content => '',
		ext => 'md',
		redirect => '/',
		includes => [],
	);

	$app->hook(
		before_server_start => sub {
			my ($server, $app) = @_;
			$server->on(
				heartbeat => sub {
					my ($prefork, $pid) = @_;
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
			my $domain = $c->config->{domain};

			if ($host eq "cdn-origin.$domain") {
				my $req_user = shift @{$req_url->path->parts};
				my $path = join '/', @{$req_url->path->parts};
				my $user_home = $c->config->{user_home};
				my $file = path($user_home, $req_user, $path);
				return $c->reply->file($file) if -f $file;
			}
			return;
		}
	);

	$app->hook(
		after_dispatch => sub {
			my $c = shift;
			my $logpath = path($c->config->{log_home}, 'master', 'access.log');
			my $logdir = $logpath->dirname;
			$logdir->make_path unless -d $logdir;
			$logpath->touch unless -f $logpath;
			$logpath->chmod(0600);
			my $log = $c->accesslog($logpath);

			my $tx = $c->tx;

			my @data = (
				$tx->remote_address					// '',
				$tx->req->method					// '',
				'HTTP/' . $tx->req->version			// '',
				$tx->req->headers->host				// '',
				$tx->req->url->path_query			// '',
				$tx->req->headers->referrer			// '',
				$tx->req->headers->user_agent		// '',
				$tx->res->code						// '',
				$tx->res->body_size					// '',
				$tx->res->headers->content_type		// '',
			);

			$log->info(@data);
		}
	);

	my $r = $app->routes;

	$r->get(
		'/.well-known/acme-challenge/:file' => sub {
			my $c = shift;
			my $file = $c->param('file');
			$c->reply->file("/var/www/acme/$file");
		})->name('acme_challenge');

	$r->get('/login')->to(controller => 'Users', action => 'user_login')->name('token_auth');
	$r->post('/login')->to(controller => 'Users', action => 'user_login')->name('user_login');
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
		$url->scheme($c->config->{scheme});
		$url->port($c->config->{port});

		my $user = $c->user->read_user(
			{ key => 'username', username => $username }
		);
		my $domain = $c->config->{domain};
		my $custom_domain = $user->{custom_domain};
		if ($custom_domain) {
			$url->host($custom_domain);
		} else {
			$url->host("$username.$domain");
		}
		$c->redirect_to($url)
	})->name('my_site');

	my $protected = $r->under(
		sub {
			my $c = shift;
			my $username = $c->session('username');
			my $req_user = $c->get_req_user;
			if ($username && $username eq $req_user) {
				return 1;
			} else {
				$c->flash(info => 'Login required');
				$c->render(
					status => 403,
					template => 'message',
					title => '403 Forbidden',
					content => '403 Forbidden: sorry, this page requires a login.'
				);
				return;
			}
		}
	);

	my $block_demo = sub {
		my $c = shift;
		my $username = $c->session('username') // '';
		if ($username eq 'demo') {
			$c->render(
				status => 403,
				template => 'message',
				title => '403 Forbidden',
				content => '403 Forbidden: demo user cannot perform this action.'
			);
			return;
		}
		return 1;
	};

	$protected->get('/private/*catchall')->to(controller => 'Pages', action => 'render_private', catchall => '')->name('render_private');

	$protected->get('/new/*catchall')->to(controller => 'Pages', action => 'new_page', catchall => '')->name('new_page');
	$protected->get('/edit/*catchall')->to(controller => 'Pages', action => 'edit_page', catchall => '')->name('edit_page');
	$protected->post('/edit/*catchall')->to(controller => 'Pages', action => 'save_page', catchall => '')->name('save_page');
	$protected->get('/backup/*catchall')->to(controller => 'Pages', action => 'backup_page', catchall => '')->name('backup_page');

	$protected->get('/files')->to(controller => 'Files', action => 'list_files')->name('list_files');
	$protected->get('/rename/*catchall')->to(controller => 'Files', action => 'rename_file', catchall => '')->name('rename_file');
	$protected->get('/delete/*catchall')->to(controller => 'Files', action => 'delete_file', catchall => '')->name('delete_file');
	$protected->under($block_demo)->post('/upload')->to(controller => 'Files', action => 'upload_files')->name('upload_files');

	$protected->get('/settings/totp')->to(controller => 'TOTP', action => 'totp_initiate')->name('totp_initiate');
	$protected->under($block_demo)->post('/settings/totp')->to(controller => 'TOTP', action => 'totp_update')->name('totp_update');
	$protected->get('/settings')->to(controller => 'Settings', action => 'list_settings')->name('list_settings');
	$protected->under($block_demo)->post('/settings')->to(controller => 'Settings', action => 'save_settings')->name('save_settings');

	$protected->get('/snapshots')->to(controller => 'Snapshots', action => 'list_snapshots')->name('list_snapshots');
	$protected->get('/snapshots/new')->to(controller => 'Snapshots', action => 'take_snapshot')->name('take_snapshot');
	$protected->get('/snapshots/download/:hash')->to(controller => 'Snapshots', action => 'download_snapshot')->name('download_snapshot');
	$protected->get('/snapshots/restore/:hash')->to(controller => 'Snapshots', action => 'restore_snapshot')->name('restore_snapshot');

	$r->get('/health')->to(controller => 'Health', action => 'health_check')->name('health_check');

	$r->get('/raw/*catchall')->to(controller => 'Pages', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Pages', action => 'render_page', catchall => '')->name('render_page');
}

return 1;
