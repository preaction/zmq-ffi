package ZMQ::FFI::ErrorHelper;

use Carp;
use FFI::Raw;
use ZMQ::FFI::Util q(zmq_version);

use Moo;
use namespace::clean;

has soname => (
    is       => 'ro',
    required => 1,
);

has _err_ffi => (
    is      => 'ro',
    lazy    => 1,
    builder => '_init_err_ffi',
);

sub BUILD {
    my $self = shift;
    $self->_err_ffi;
}

sub check_error {
    my ($self, $func, $rc) = @_;

    if ( $rc == -1 ) {
        $self->fatal($func);
    }
}

sub check_null {
    my ($self, $func, $obj) = @_;

    unless ($obj) {
        $self->fatal($func);
    }
}

sub fatal {
    my ($self, $func) = @_;

    my $ffi = $self->_err_ffi;

    my $errno  = $ffi->{zmq_errno}->();
    my $strerr = $ffi->{zmq_strerror}->($errno);

    confess "$func: $strerr";
}

sub bad_version {
    my ($self, $msg, $use_carp) = @_;

    my $verstr = join ".", zmq_version($self->soname);

    if ($use_carp) {
        croak   "$msg\n"
              . "your version: $verstr";
    }
    else {
        die   "$msg\n"
            . "your version: $verstr";

    }
}

sub _init_err_ffi {
    my $self = shift;

    my $ffi    = {};
    my $soname = $self->soname;

    $ffi->{zmq_errno} = FFI::Raw->new(
        $soname => 'zmq_errno',
        FFI::Raw::int # returns errno
        # void
    );

    $ffi->{zmq_strerror} = FFI::Raw->new(
        $soname => 'zmq_strerror',
        FFI::Raw::str,  # returns error str
        FFI::Raw::int   # errno
    );

    return $ffi;
}

1;
