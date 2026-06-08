use Mojo::Base -strict;
use File::Basename;
use constant CWD => dirname(__FILE__);
use lib CWD . '/../lib';
use Test::More;

use Bliptown::Model::Metadata;

my $metadata = Bliptown::Model::Metadata->new;

subtest 'read_metadata parses keys' => sub {
	my $yaml = <<EOF;
---
title: My Post
date: 2999-12-31
layout: one-column
---
EOF
	my $data = $metadata->read_metadata($yaml);
	is $data->{title}, 'My Post', 'title parsed';
	is $data->{date}, '2999-12-31', 'date parsed';
	is $data->{layout}, 'one-column', 'layout parsed';
};

subtest 'read_metadata returns hashref for empty YAML' => sub {
	my $yaml = <<EOF;
---
---
EOF
	my $data = $metadata->read_metadata($yaml);
	ok ref($data) eq 'HASH', 'returned a hashref';
};

subtest 'read_metadata returns hashref for invalid YAML' => sub {
	my $yaml = <<EOF;
zzz
EOF
	my $data = $metadata->read_metadata($yaml);
	ok ref($data) eq 'HASH', 'returned a hashref';
};

done_testing;
