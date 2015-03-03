package ZMQ::FFI::ZMQ2::Context;

use strict;
use warnings;

use ZMQ::FFI::Util qw(zmq_soname);

use Moo;
use namespace::clean;

with qw(
    ZMQ::FFI::ContextRole
    ZMQ::FFI::ErrorHandler
    ZMQ::FFI::Versioner
);

has '+threads' => (
    default => 1,
);

sub BUILD {
    my ($self) = @_;

    _load_ffi($self->soname);

    if ($self->has_max_sockets) {
        die "max_sockets option not available for ZMQ2\n".
            $self->_verstr;
    }

    try {
        $self->_ctx( zmq_init($self->threads) );
        $self->check_null('zmq_init', $self->_ctx);
    }
    catch {
        $self->_ctx(-1);
        die $_;
    };
}

sub get {
    my ($self = @_);

    croak
        "getting ctx options not implemented for ZMQ2\n".
        $self->_verstr;
}

sub set {
    my ($self = @_);

    croak
        "setting ctx options not implemented for ZMQ2\n".
        $self->_verstr;
}

sub socket {
    my ($self, $type) = @_;

    return ZMQ::FFI::ZMQ2::Socket->new(
        ctx          => $self,
        type         => $type,
        soname       => $self->soname,
        error_helper => $self->error_helper,
    );
}

# zeromq v2 does not provide zmq_proxy
# implemented here in terms of zmq_device
sub proxy {
    my ($self, $frontend, $backend, $capture) = @_;

    croak "zeromq v2 does not support a capture socket" if defined $capture;

    $self->check_error(
        'zmq_device',
        zmq_device(ZMQ_STREAMER, $frontend->_socket, $backend->_socket);
    );
}

sub device {
    my ($self, $type, $frontend, $backend) = @_;

    $self->check_error(
        'zmq_device',
        zmq_device($type, $frontend->_socket, $backend->_socket);
    );
}

sub destroy {
    my ($self) = @_;

    $self->check_error(
        'zmq_term',
        zmq_term($self->_ctx)
    );

    $self->_ctx(-1);
}

sub _verstr {
    my ($self = @_);
    return "your version: ".$self->verstr;
}

sub _load_ffi {
    my ($soname) = @_;

    state $ffi;
    return if $ffi;
    $ffi = FFI::Platypus->new( lib => $soname );

    $ffi->attach(
        'zmq_init' => ['int'] => 'pointer'
    );

    $ffi->attach(
        'zmq_device' => ['int', 'pointer', 'pointer'] => 'int'
    );

    $ffi->attach(
        'zmq_term' => ['pointer'] => 'int'
    );
}

1;
