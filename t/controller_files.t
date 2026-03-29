use Mojo::Base -strict;
use lib 't/lib';

use Test::More;

# Test the format_human_size helper function from the Files controller.
# Load the controller module directly (it's a simple function).
BEGIN {
	$ENV{BLIPTOWN_MD4C_HTML_LIB} //= '/usr/lib/x86_64-linux-gnu/libmd4c-html.so.0';
}

use Bliptown::Controller::Files;

# Access the private function via the package namespace
my $fhs = \&Bliptown::Controller::Files::format_human_size;

subtest 'format_human_size bytes' => sub {
	is $fhs->(0),    '0B',    'zero bytes';
	is $fhs->(1),    '1B',    'one byte';
	is $fhs->(1023), '1023B', '1023 bytes stays as B';
};

subtest 'format_human_size kilobytes' => sub {
	is $fhs->(1024),  '1.00K',  '1 KB';
	is $fhs->(2048),  '2.00K',  '2 KB';
	like $fhs->(1536), qr/1\.50K/, '1.5 KB';
};

subtest 'format_human_size megabytes' => sub {
	my $one_mb = 1024 * 1024;
	is $fhs->($one_mb), '1.00M', '1 MB';
	like $fhs->($one_mb * 2.5), qr/2\.50M/, '2.5 MB';
};

subtest 'format_human_size gigabytes' => sub {
	my $one_gb = 1024 * 1024 * 1024;
	is $fhs->($one_gb), '1.00G', '1 GB';
};

done_testing;
