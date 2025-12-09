package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::File qw(path);
use Mojo::Util qw(url_unescape);
use Mojo::SQLite;
use lib '.';
use Bliptown::Sessions;

use Bliptown::Model::User;
use Bliptown::Model::Page;
use Bliptown::Model::File;
use Bliptown::Model::IPC;
use Bliptown::Model::TOTP;
use Bliptown::Model::QRCode;
use Bliptown::Model::DomainList;
use Bliptown::Model::Token;
use Bliptown::Model::Cache;

sub startup {
	my $app = shift;

	$app->config(
		user_home => $ENV{BLIPTOWN_USER_HOME},
	);
	$app->secrets(
		[ $ENV{BLIPTOWN_SECRET} ]
	);

	my $bliptown_domain = $app->mode eq 'production' ? 'blip.town' : 'blip.local';

	my $sessions = Bliptown::Sessions->new(default_expiration => 2592000);
	$app->sessions($sessions);
	$app->sessions->cookie_domain(".$bliptown_domain");

	$app->helper(
		sqlite => sub {
			my $db = path($ENV{BLIPTOWN_DB_HOME}, 'users.db');
			state $sql = Mojo::SQLite->new("sqlite:$db");
			return $sql;
		});

	my $migrations_path = $app->home->child('migrations.sql');
	$app->sqlite->migrations->from_file($migrations_path)->migrate(4);

	$app->helper(
		user => sub {
			my $c = shift;
			return Bliptown::Model::User->new(
				sqlite => $c->sqlite,
				totp => $c->totp,
				domain_list => $c->domain_list,
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
		domain_list => sub {
			my $c = shift;
			return Bliptown::Model::DomainList->new(
				sqlite => $c->sqlite,
				ipc => $c->ipc,
			);
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
		image_cache => sub {
			my $c = shift;
			return Bliptown::Model::Cache->new(
				config => $c->config,
				ipc => $c->ipc,
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
		get_user_home => sub {
			return $ENV{BLIPTOWN_USER_HOME};
		});
	
	$app->helper(
		get_req_user => sub {
			my $c = shift;
			my $host = $c->req->headers->header('Host') || '';
			$host =~ s/:.*//;
			$host =~ s/^www\.(.+)/$1/;
			if ($host =~ /\Q$bliptown_domain\E$/) {
				my @host_array = split(/\./, $host);
				my $username = @host_array >= 3 ? $host_array[-3] : 'mayor';
				return $username if $username;
			}
			my $user = $c->user->read_user(
				{ key => 'custom_domain', custom_domain => $host }
			);
			my $username = $user->{username};
			return $username if $username;
			return;
		});

	$app->helper(
		get_home => sub {
			my $c = shift;
			my $url = Mojo::URL->new;
			my $username = $c->session('username');
			if ($username) {
				$url->host("$username.$bliptown_domain");
			} else {
				$url->host("$bliptown_domain");
			}
			if ($c->app->mode eq 'production') {
				$url->scheme('https');
			} else {
				$url->scheme('http');
				$url->port(3000);
			}
			return $url;
		}
	);

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			my $root = path($c->get_user_home, $c->get_req_user)->to_abs;
			my $file = path($root, $slug)->to_abs;
			return $file if -f $file;
			$slug = $1 if $slug =~ /(.+)(\..+)$/;
			my @exts = qw(html css js txt md);
			foreach (@exts) {
				my $f = path($root, "$slug.$_")->to_abs;
				return $f if -f $f;
			}
			return;
		}
	);

	$app->defaults(
		bliptown_domain => $bliptown_domain,
		title => 'Untitled',
		head => '',
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

	my $r = $app->routes;

	$r->post('/join')->to(controller => 'User', action => 'user_join')->name('user_join');
	$r->get('/login')->to(controller => 'User', action => 'user_login')->name('token_auth');
	$r->post('/login')->to(controller => 'User', action => 'user_login')->name('user_login');
	$r->get('/logout')->to(controller => 'User', action => 'user_logout')->name('user_logout');

	$r->get('/totp')->to(controller => 'TOTP', action => 'totp_initiate')->name('totp_initiate');
	$r->post('/totp')->to(controller => 'TOTP', action => 'totp_update')->name('totp_update');

	$r->get('/mysite' => sub {
		my $c = shift;
		my $username = $c->session('username');
		unless ($username) {
			$c->flash(info => 'Login required');
			$c->redirect_to('/');
			return;
		}
		my $url = Mojo::URL->new;
		if ($c->app->mode eq 'production') {
			$url->scheme('https');
		} else {
			$url->scheme('http');
			$url->port(3000);
		}
		my $user = $c->user->read_user(
			{ key => 'username', username => $username }
		);
		my $custom_domain = $user->{custom_domain};
		if ($custom_domain) {
			$url->host($custom_domain);
		} elsif ($username) {
			$url->host("$username.$bliptown_domain");
		} else {
			$url->host("$bliptown_domain");
		}
		$c->redirect_to($url)
	})->name('my_site');

	my $protected = $r->under(
		'/' => sub {
			my $c = shift;
			my $username = $c->session('username');
			if ($username && $username eq $c->get_req_user) {
				return 1;
			} else {
				$c->flash(info => 'Login required');
				$c->reply->not_found;
				return;
			}
		}
	);

	$protected->get('/private/*catchall')->to(controller => 'Page', action => 'render_private', catchall => '')->name('render_private');

	$protected->get('/new/*catchall')->to(controller => 'Page', action => 'new_page', catchall => '')->name('new_page');
	$protected->get('/edit/*catchall')->to(controller => 'Page', action => 'edit_page', catchall => '')->name('edit_page');
	$protected->post('/edit/*catchall')->to(controller => 'Page', action => 'save_page', catchall => '')->name('save_page');

	$protected->get('/files')->to(controller => 'File', action => 'list_files')->name('list_files');
	$protected->get('/rename/*catchall')->to(controller => 'File', action => 'rename_file', catchall => '')->name('rename_file');
	$protected->get('/delete/*catchall')->to(controller => 'File', action => 'delete_file', catchall => '')->name('delete_file');
	$protected->post('/upload')->to(controller => 'File', action => 'upload_files')->name('upload_files');

	$protected->get('/cache/create')->to(controller => 'File', action => 'create_cache')->name('create_cache');
	$protected->get('/cache/delete')->to(controller => 'File', action => 'delete_cache')->name('delete_cache');

	$protected->get('/settings')->to(controller => 'Settings', action => 'list_settings')->name('list_settings');
	$protected->post('/settings')->to(controller => 'Settings', action => 'save_settings')->name('save_settings');

	$r->get('/raw/*catchall')->to(controller => 'Page', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Page', action => 'render_page', catchall => '')->name('render_page');
}

return 1;
