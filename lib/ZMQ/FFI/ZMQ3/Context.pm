package ZMQ::FFI::ZMQ3::Context;

use FFI::Platypus;
use ZMQ::FFI::Util qw(zmq_soname);
use ZMQ::FFI::Constants qw(ZMQ_IO_THREADS ZMQ_MAX_SOCKETS);
use ZMQ::FFI::ZMQ3::Socket;
use Try::Tiny;

use Moo;
use namespace::clean;

with qw(
    ZMQ::FFI::ContextRole
    ZMQ::FFI::ErrorHandler
    ZMQ::FFI::Versioner
);

my $FFI_LOADED;

sub BUILD {
    my ($self) = @_;

    unless ($FFI_LOADED) {
        _load_zmq3_ffi($self->soname);
        $FFI_LOADED = 1;
    }

    try {
        $self->_ctx( zmq_ctx_new() );
        $self->check_null('zmq_ctx_new', $self->_ctx);
    }
    catch {
        $self->_ctx(-1);
        die $_;
    };

    if ( $self->has_threads ) {
        $self->set(ZMQ_IO_THREADS, $self->threads);
    }

    if ( $self->has_max_sockets ) {
        $self->set(ZMQ_MAX_SOCKETS, $self->max_sockets);
    }
}

sub _load_zmq3_ffi {
    my ($soname) = @_;

    my $ffi = FFI::Platypus->new( lib => $soname );

    $ffi->attach(
        'zmq_ctx_new' => ['pointer'] => 'void'
    );

    $ffi->attach(
        'zmq_ctx_get' => ['pointer', 'int'] => 'int'
    );

    $ffi->attach(
        'zmq_ctx_set' => ['pointer', 'int', 'int'] => 'int'
    );

    $ffi->attach(
        'zmq_proxy' => ['pointer', 'pointer', 'pointer'] => 'int'
    );

    $ffi->attach(
        'zmq_ctx_destroy' => ['pointer'] => 'int'
    );
}

sub get {
    my ($self, $option) = @_;

    my $option_val = zmq_ctx_get($self->_ctx, $option);
    $self->check_error('zmq_ctx_get', $option_val);

    return $option_val;
}

sub set {
    my ($self, $option, $option_val) = @_;

    $self->check_error(
        'zmq_ctx_set',
        zmq_ctx_set($self->_ctx, $option, $option_val)
    );
}

sub socket {
    my ($self, $type) = @_;

    return ZMQ::FFI::ZMQ3::Socket->new(
        ctx          => $self,
        type         => $type,
        soname       => $self->soname,
        error_helper => $self->error_helper,
    );
}

sub proxy {
    my ($self, $frontend, $backend, $capture) = @_;

    $self->check_error(
        'zmq_proxy',
        zmq_proxy(
            $frontend->_socket,
            $backend->_socket,
            defined $capture ? $capture->_socket : undef,
        )
    );
}

sub device {
    my ($self, $type, $frontend, $backend) = @_;

    $self->bad_version(
        "zmq_device not available in zmq >= 3.x",
        "use_carp"
    );
}

sub destroy {
    my ($self) = @_;

    $self->check_error(
        'zmq_ctx_destroy',
        zmq_ctx_destroy($self->_ctx)
    );

    $self->_ctx(-1);
};


1;
__END__

sub _init_ffi {
    my $self = shift;

    my $ffi    = {};
    my $soname = $self->soname;

    $ffi->{zmq_ctx_new} = FFI::Raw->new(
        $soname => 'zmq_ctx_new',
        FFI::Raw::ptr, # returns ctx ptr
        # void
    );

    $ffi->{zmq_ctx_set} = FFI::Raw->new(
        $soname => 'zmq_ctx_set',
        FFI::Raw::int, # error code,
        FFI::Raw::ptr, # ctx
        FFI::Raw::int, # opt constant
        FFI::Raw::int  # opt value
    );

    $ffi->{zmq_ctx_get} = FFI::Raw->new(
        $soname => 'zmq_ctx_get',
        FFI::Raw::int, # opt value,
        FFI::Raw::ptr, # ctx
        FFI::Raw::int  # opt constant
    );

    $ffi->{zmq_proxy} = FFI::Raw->new(
        $soname => 'zmq_proxy',
        FFI::Raw::int, # error code
        FFI::Raw::ptr, # frontend
        FFI::Raw::ptr, # backend
        FFI::Raw::ptr, # captuer
    );

    $ffi->{zmq_device} = FFI::Raw->new(
        $soname => 'zmq_device',
        FFI::Raw::int, # error code
        FFI::Raw::int, # type
        FFI::Raw::ptr, # frontend
        FFI::Raw::ptr, # backend
    );

    $ffi->{zmq_ctx_destroy} = FFI::Raw->new(
        $soname => 'zmq_ctx_destroy',
        FFI::Raw::int, # retval
        FFI::Raw::ptr  # ctx to destroy
    );

    return $ffi;
}

__PACKAGE__->meta->make_immutable();

1;
