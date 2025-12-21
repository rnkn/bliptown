package Bliptown::Model::Cache;
use Mojo::Base -base;
use Mojo::File qw(path);
use Mojo::Util qw(decode sha1_sum);
use Imager;

has 'config';
has 'ipc';

Imager->set_file_limits(reset=>1, bytes=>1_000_000_000);

sub create_cache {
	my ($self, $args) = @_;
	my $username = $args->{username};

	my $root = path($self->config->{user_home}, $username);
	my $cache = path($root, '.cache');
	my $tree = $root->list_tree;

	my @imgs = grep { /\.(jpe?g|png|tiff?)$/i } @$tree;
	foreach (@imgs) {
		my $filename = decode('utf-8', $_->to_string);
		my $rel_filename = decode('utf-8', $_->to_rel($root));
		my $sha = sha1_sum($rel_filename);
		my $cache_file = path($cache, $sha);

		if (-f $cache_file) {
			my @src_stats = stat($filename);
			my $src_mtime = $src_stats[9];
			my @cache_stats = stat($cache_file);
			my $cache_mtime = $cache_stats[9];
			next if $cache_mtime >= $src_mtime;
		}

		my $img = Imager->new;
		$img->read(file => $filename)
			or die "Cannot read file: ", $img->errstr;

		my $width = $img->getwidth;
		my $height = $img->getheight;
		$width = $width > 2048 ? 2048 : $width;
		$height = $height > 2048 ? 2048 : $height;
		my $side = $width > $height ? $width : $height;

		my $scaled_img = $img->scale(xpixels => $side, ypixels => $side, type => 'min');

		my $blob;
		$scaled_img->write(data => \$blob, type => 'jpeg', jpegquality => 75);

		$self->ipc->send_message(
			{
				username => $username,
				command => 'write_blob',
				filename => $cache_file->to_abs->to_string,
				blob => $blob,
			}
		);
	}
	return;
}

sub delete_cache {
	my ($self, $args) = @_;
	my $username = $args->{username};
	my $cache = path($self->config->{user_home}, $username, '.cache');

	my $tree = $cache->list_tree;

	foreach ($tree->each) {
		$self->ipc->send_message(
			{
				command => 'delete_file',
				username => $username,
				filename => $_->to_string,
			}
		)
	}

}

return 1;
