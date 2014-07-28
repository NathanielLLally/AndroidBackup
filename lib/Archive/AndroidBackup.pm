package Archive::AndroidBackup;
use Moose;
use MooseX::NonMoose;
use File::Find;
use Compress::Raw::Zlib;
use Archive::AndroidBackup::TarIndex;
extends 'Archive::Tar';

our $VERSION = '1.12';

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

=head 2 read($file)

  performs 

=cut
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
  while (read($inFH, $inbuf, 4096)) {
    $status = $z->inflate($inbuf, $outbuf);
    print $tmpFHout $outbuf;
    last if $status != Z_OK;
  }
  die "inflation failed" unless $status == Z_STREAM_END;
  $tmpFHout->flush;

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


=head2 add_dir($dir)
  emulate tar -cf dir

  will correctly sort directory index the way android backup needs it
  (aka the implementation peculiarity that spawned this whole project)

=cut
sub add_dir
{
  my ($self, $dir) = @_;

  return unless (-d $dir);

  my $index = new Archive::AndroidBackup::TarIndex;
  find(sub { $index->build_from_str($File::Find::name); }, $dir);

  $self->add_files( $index->as_array );
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
