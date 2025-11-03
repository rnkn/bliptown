package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::File qw(curfile path);
use Mojo::SQLite;
use lib curfile->dirname->sibling('lib')->to_string;

use Bliptown::Model::User;
use Bliptown::Model::Page;
use Bliptown::Model::File;

sub startup {
	my $app = shift;
	$app->secrets([ $ENV{'BLIPTOWN_SECRET'} ]);
	$app->config(
		hypnotoad => {
			proxy  => 1
		});

	my $domain = $app->mode eq 'production' ? 'blip.town' : 'blip.local';
	$app->sessions->cookie_domain($domain);

	$app->helper(
		sqlite => sub {
			state $sql = Mojo::SQLite->new('sqlite:users.db');
		});

	my $migrations_path = $app->home->child('migrations.sql');
	$app->sqlite->migrations->from_file($migrations_path)->migrate(2);

	$app->helper(
		user => sub {
			state $user = Bliptown::Model::User->new(sqlite => shift->sqlite);
		});

	$app->helper(
		page => sub {
			state $page = Bliptown::Model::Page->new;
		});

	$app->helper(
		file => sub {
			state $src = Bliptown::Model::File->new;
		});

	$app->helper(
		get_user_home => sub {
			return $ENV{'BLIPTOWN_USER_HOME'};
		}
	);
	
	$app->helper(
		get_req_user => sub {
			my $c = shift;
			my @hostname = split(/\./, $c->req->url->to_abs->host);
			return @hostname >= 3 ? $hostname[-3] : 'mayor';
		});

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			my $root = path($c->get_user_home, $c->get_req_user)->to_abs;
			my $file_path = path($root, $slug)->to_abs;
			return $file_path if -f $file_path;
			my @exts = qw(html css js txt md);
			foreach (@exts) {
				my $f = path($root, "$slug.$_")->to_abs;
				return $f if -f $f;
			}
			my $index_path = path("$file_path/index.md")->to_abs;
			return $index_path if -f $index_path;
			return;
		}
	);

	$app->defaults(
		home => '/',
		show_join => 0,
		head => '',
		header => '',
		sidebar => '',
		footer => '',
		title => 'Untitled',
		content => '',
		ext => 'md',
		editable => 0,
		relfile => '',
		redirect => '/',
		includes => [],
	);

	my $r = $app->routes;

	$r->post('/join')->to(controller => 'User', action => 'user_join')->name('user_join');
	$r->post('/login')->to(controller => 'User', action => 'user_login')->name('user_login');
	$r->get('/logout')->to(controller => 'User', action => 'user_logout')->name('user_logout');

	$r->get('/totp')->to(controller => 'TOTP', action => 'totp_initiate')->name('totp_initiate');
	$r->post('/totp')->to(controller => 'TOTP', action => 'totp_check')->name('totp_check');

	my $protected = $r->under(
		'/' => sub {
			my $c = shift;
			my $u = $c->session('username');
			if ($u && $u eq $c->get_req_user) {
				return 1;
			} else {
				$c->flash(info => 'Login required');
				return $c->redirect_to('/');
			}
		}
	);

	$protected->get('/new/*catchall')->to(controller => 'Page', action => 'new_page', catchall => '')->name('new_page');
	$protected->get('/edit/*catchall')->to(controller => 'Page', action => 'edit_page', catchall => '')->name('edit_page');
	$protected->post('/edit/*catchall')->to(controller => 'Page', action => 'save_page', catchall => '')->name('save_page');

	$protected->get('/files')->to(controller => 'File', action => 'list_files')->name('list_files');
	$protected->get('/rename/*catchall')->to(controller => 'File', action => 'rename_file', catchall => '')->name('rename_file');
	$protected->get('/delete/*catchall')->to(controller => 'File', action => 'delete_file', catchall => '')->name('delete_file');
	$protected->post('/upload')->to(controller => 'File', action => 'upload_files')->name('upload_files');

	$protected->get('/settings')->to(controller => 'Settings', action => 'list_settings')->name('list_settings');
	$protected->post('/settings')->to(controller => 'Settings', action => 'save_settings')->name('save_settings');

	$r->get('/raw/*catchall')->to(controller => 'Page', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Page', action => 'render_page', catchall => '')->name('render_page');
}

return 1;
