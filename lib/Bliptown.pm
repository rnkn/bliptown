package Bliptown;
use Mojo::Base 'Mojolicious';
use Mojo::SQLite;
use Mojo::File qw(curfile path);
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

	$app->helper(
		sqlite => sub {
			state $sql = Mojo::SQLite->new('sqlite:users.db');
		});

	my $migrations_path = $app->home->child('migrations.sql');
	$app->sqlite->migrations->from_file($migrations_path)->migrate;

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
		get_src_dir => sub {
			state $src = $ENV{'BLIPTOWN_SRC'};
			return $src;
		}
	);

	$app->helper(
		get_user => sub {
			my $c = shift;
			my @hostname = split(/\./, $c->req->url->to_abs->host);
			return @hostname >= 3 ? $hostname[-3] : 'mayor';
		});

	$app->helper(
		get_file => sub {
			my ($c, $slug) = @_;
			my $root = path($c->get_src_dir, $c->get_user);
			my @filetypes = qw(html css js txt md);
			foreach (@filetypes) {
				my $f = path($root, $slug)->to_abs;
				return $f if -f $f;
				$f = path($root, "$slug.$_")->to_abs;
				return $f if -f $f;
			}
		}
	);

	$app->defaults(
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

	$r->get(
		'/denied' => sub {
			my $c = shift;
			$c->render(text => 'Access denied', status => 403)
		}
	)->name('access_denied');

	$r->post('/join')->to(controller => 'User', action => 'user_join')->name('user_join');
	$r->post('/login')->to(controller => 'User', action => 'user_login')->name('user_login');
	$r->get('/logout')->to(controller => 'User', action => 'user_logout')->name('user_logout');

	my $protected = $r->under(
		'/' => sub {
			my $c = shift;
			if ($c->session('username') && $c->session('username') eq $c->get_user) {
				return 1;
			} else {
				return $c->redirect_to('access_denied');
			}
		}
	);

	$protected->get('/new/*catchall')->to(controller => 'Page', action => 'new_page', catchall => '')->name('new_page');
	$protected->get('/edit/*catchall')->to(controller => 'Page', action => 'edit_page', catchall => '')->name('edit_page');
	$protected->post('/edit/*catchall')->to(controller => 'Page', action => 'save_page', catchall => '')->name('save_page');

	$protected->get('/files')->to(controller => 'File', action => 'list_files')->name('list_files');
	$protected->get('/rename/*catchall')->to(controller => 'File', action => 'rename_file', catchall => '')->name('rename_file');
	$protected->get('/delete/*catchall')->to(controller => 'File', action => 'delete_file', catchall => '')->name('delete_file');

	$r->get('/raw/*catchall')->to(controller => 'Page', action => 'render_raw', catchall => '')->name('render_raw');
	$r->get('/*catchall')->to(controller => 'Page', action => 'render_page', catchall => '')->name('render_page');
}

return 1;
