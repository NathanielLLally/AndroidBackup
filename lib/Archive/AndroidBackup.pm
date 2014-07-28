package Printable;
use Moose::Role;

requires 'as_string';

package Tree;
use Moose;
with 'Printable';

=head1 NAME

   Tree

=head1 SYNOPSIS



=cut

has 'node' => (
  is => 'rw',
  isa => 'Any',
  predicate => 'has_node',
  lazy => 1,
  default => sub { die "cannot initialize node with no value";} ,
);

has 'root' => (
  is => 'ro',
  isa => 'Tree',
  weak_ref    => 1,
  lazy => 1,
  default => sub {
    my $leaf = shift;
    while ($leaf->has_parent) {
      $leaf = $leaf->parent;
    }
    $leaf;
  },
);

has 'level' => (is => 'rw', isa => 'Num', default => 0);

after 'node' => sub {
  my ($self, $value) = @_;
  
  $self->add_sibling($self->node => $self) if $self->has_parent and defined $value;
};

has 'parent' => (
    is          => 'ro',
    isa         => 'Tree',
    weak_ref    => 1,
    predicate   => 'has_parent',
    handles     => {
      parent_node => 'node',
      siblings    => 'children',
      add_sibling => 'set_child',
      }
    );

has '_children' => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef',
    default => sub { {} },
    handles => {
      children => 'values',
      child_nodes => 'keys',
      total_children => 'count',
      has_no_children => 'is_empty',
      get_child => 'get',
      set_child => 'set',
      orphan_child => 'delete',
      has_child_node => 'exists',
    },
    );

sub has_children
{
  my $self = shift;
  not $self->has_no_children;
}

=head2 add_child(;$node)

  add's a new child to tree

=cut
sub add_child
{
  my ($self, $node) = @_;

  my $class = ref $self if ref $self;
  my $branch = $class->new( parent => $self );
  $branch->level($self->level + 1);
  if (defined $node) {
    $branch->node($node);
  }
  $branch;
}

=head2 get_or_add_child($node);

  adds or gets an existing child
  returns an un-intialized orphan if node is undef
    *this will be added to the family upon setting node

=cut

sub get_or_add_child {
  my ($self,$key) = @_;

  my ($child) = (undef);
  if (defined $key) {
    if ($self->has_child_node($key)) {

      $child = $self->get_child($key);
    } else {
      $child = $self->add_child($key);
    }
  } else {
    print "child with no node\n";
    $child = $self->add_child;
  }
  return $child;
}

sub node_as_string
{
  my $self = shift;
  sprintf "%*s%s", $self->level * 4, "", $self->node;
} 

=head2 as_string

  print node via note_as_string, then recurse to children

=cut
sub as_string {
  my $self = shift;
  my @out = ( $self->node_as_string );
  foreach my $child ($self->children) {
    push @out, $child->as_string;
  }
  return join("\n", @out); 
}

package DirTree;

=head1 NAME

  DirTree

  subclass of Tree specifically for unix paths

=cut

use Moose;
extends 'Tree';
with 'Printable';

=head1 METHODS

=head2 build_from_str($unixPath);

  splits on / and add children as appropriate
  ie.  ->build_from_str('apps/com.your.namespace/_manifest');

=cut
sub build_from_str
{
  my ($self, $str) = @_;

  my $trunk = $self;
  foreach my $dirPart (split(/\//, $str)) {
    if (not $trunk->has_node or $trunk->node eq $dirPart) {
      $trunk->node($dirPart);
    } else {
      $trunk = $trunk->get_or_add_child($dirPart);
    }
  }
  $trunk;
}

=head2 build_from_file($fh)

  build tree from STDIN
  ie. ->build_from_file(FileHandle->new_from_fd(0, "r")); 

=cut
sub build_from_file {
  my ($self,$input) = @_;
  $input->isa("IO::Handle") or die "input not IO::handle";

  while (<$input>) {
    chomp;
    $self->build_from_str($_);
  }
}

=head2 node_as_string

  print fully qualified path

=cut
sub node_as_string
{
  my $self = shift;
 
  my $str = $self->parent->node_as_string if ($self->has_parent);
  if (defined $str and $self->has_node) {
    return join("/", $str, $self->node);
  } elsif ($self->has_node) {
    return $self->node;
  }
}

package abDirTree;
use Moose;

extends 'DirTree';
with 'Printable';

has namespace => (
  is => 'rw',
  isa => 'Str',
  predicate => 'has_namespace',
  lazy => 1,
  default => sub { ''; },
);

sub as_arrayref
{
  my $self = shift;
  return "invalid android backup: missing _manifest"
    unless ($self->root->has_namespace);

  #  adb restore will break if you try to 
  #  create an exiting private directory (at least on moto x)
  #
  my %specialDirs = (
      $self->root->namespace => 0,
      apps => 0,
      ef => 0,
      sp => 0,
      db => 0,
      );

  my @out;
  push @out,$self->node_as_string unless (exists $specialDirs{$self->node});
  if ($self->node eq $self->root->namespace) {
    my $specialChild = $self->get_child('_manifest');

    push @out, $specialChild->node_as_string;

    $self->orphan_child($specialChild->node);
  }
  foreach my $child (sort { $a->node cmp $b->node } $self->children) {
    push @out, @{ $child->as_arrayref };
  }
  return \@out;
}

override as_string => sub {
  my $self = shift;

  return join("\n", @{ $self->as_arrayref });
};

=head2 build_from_str

  augments super->build_from_str to
    infer package namespace from _manifest entry,
  *also serve as validation on list of files to have _manifest
=cut
around 'build_from_str' => sub {
  my ($orig, $self, $str) = @_;

  my $leaf = $self->$orig($str);
  if ($leaf->node eq '_manifest') {
     $self->root->namespace($leaf->parent->node);
  }
};

package Archive::AndroidBackup;
use Moose;
use MooseX::NonMoose;
use File::Find;
use Compress::Raw::Zlib;
extends 'Archive::Tar';

has 'file' => (
  is => 'rw',
  isa => 'Str',
  default => 'backup.ab',
);

has '_header' => (
  is => 'ro',
  isa => 'Str',
  default => "ANDROID BACKUP\n1\n1\nnone\n",
);

around 'read' => sub 
{
  my ($orig, $self, @args) = @_;
  my $file = shift @args;
  if (not defined $file) {
    $file = $self->file;
  }

  # if IO::Zlib's constructor could handle a scalar or open filehandle
  #   I would have used it
  #

  my $z = new Compress::Raw::Zlib::Inflate;
  my ($inFH, $tmpFHout, $tmpFHin, $tmpbuf, $header, $inbuf, $outbuf, $status);
  open($tmpFHout, ">", \$tmpbuf) || die "no write access memory?!";
  open($tmpFHin, "<", \$tmpbuf) || die "no read access memory?!";
  open($inFH, "<",$file) || die "Cannot open $file";
  map { binmode $_, ":bytes"; } $inFH, $tmpFHin, $tmpFHout;

  my $bytes = read $inFH, $header, 24;
  while (read($inFH, $inbuf, 1024)) {
    $status = $z->inflate($inbuf, $outbuf);
    print $tmpFHout $outbuf;
    last if $status != Z_OK;
  }
  die "inflation failed" unless $status == Z_STREAM_END;

  $self->$orig($tmpFHin);

  map { close $_; } $inFH, $tmpFHout, $tmpFHin;
};

around 'write' => sub 
{
  my ($orig, $self, @args) = @_;
  my $file = shift @args;
  if (not defined $file) {
    $file = $self->file;
  }

  my $z = new Compress::Raw::Zlib::Deflate;

  my ($outbuf, $status, $outFH, $tmpFHout, $tmpFHin, $tmpbuf);
  open($outFH, ">", $file) || die "cannot write to file [$file]";
  open($tmpFHout, ">", \$tmpbuf) || die "no write access memory ?!";
  open($tmpFHin, "<", \$tmpbuf) || die "no read access memory ?!";

  map { binmode $_, ":bytes"; } $outFH, $tmpFHout, $tmpFHin;

  #  Archive::Tar will space pad numbers by default
  #  (which makes sense considering they are ascii formatted numbers)
  #  however, according to the android code, these entries can be space
  #  or nul terminated
  #  see BackupManagerService.java :: extractRadix
  #
  $Archive::Tar::ZERO_PAD_NUMBERS = 1;
  $self->$orig($tmpFHout);

  print $outFH $self->_header;

  while (<$tmpFHin>) {
    $status = $z->deflate($_, $outbuf) ;

    $status == Z_OK or die "deflation failed\n" ;

    print $outFH $outbuf;
  }
  $status = $z->flush($outbuf);

  $status == Z_OK or die "deflation failed\n" ;

    print $outFH $outbuf;

  map { close $_; } $outFH, $tmpFHout, $tmpFHin;
};

#  archive::tar doesn't have this method
#
sub add_dir
{
  my ($self, $dir) = @_;

  return unless (-d $dir);

  my $abDirTree = new abDirTree;
  find(sub { $abDirTree->build_from_str($File::Find::name); }, $dir);

  my @files = @{ $abDirTree->as_arrayref };

  $self->add_files(@files);
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
