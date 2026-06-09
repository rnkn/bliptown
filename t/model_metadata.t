use Mojo::Base -strict;
use Mojo::File qw(path curfile);
use constant THIS_DIR => curfile->dirname;
use lib path(THIS_DIR, '../lib');
use Test::More;

use_ok qw(Bliptown::Model::Metadata);

my $metadata = Bliptown::Model::Metadata->new;

subtest 'read_metadata parses keys' => sub {
	my $yaml = <<'EOF';
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
	my $yaml = <<'EOF';
---
---
EOF
	my $data = $metadata->read_metadata($yaml);
	ok ref($data) eq 'HASH', 'returned a hashref';
};

subtest 'read_metadata returns hashref for invalid YAML' => sub {
	my $yaml = <<'EOF';
zzz
EOF
	my $data = $metadata->read_metadata($yaml);
	ok ref($data) eq 'HASH', 'returned a hashref';
};

done_testing;
