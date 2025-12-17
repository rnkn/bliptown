package Bliptown::Model::Cache;
use Mojo::Base -base;
use Mojo::File qw(path);
use Digest::SHA qw(sha1_hex);
use Imager;
use Encode;

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
		my $filename = decode_utf8($_->to_string);
		my $rel_filename = decode_utf8($_->to_rel($root));
		my $sha = sha1_hex($rel_filename);
		my $cache_file = path($cache, $sha);

		my $img = Imager->new;
		$img->read(file => $filename)
			or die "Cannot read file: ", $img->errstr;

		my $width = $img->getwidth;
		my $height = $img->getheight;
		$width = $width < 2048 ? $width : 2048;
		$height = $height < 2048 ? $height : 2048;
		my $side = $width < $height ? $width : $height;

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

return 1;
