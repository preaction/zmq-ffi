package ZMQ::FFI::SocketRole;

use FFI::Platypus;
use FFI::Platypus::Buffer;
use ZMQ::FFI::Constants qw(:all);

use Moo::Role;

has soname => (
    is       => 'ro',
    required => 1,
);

# context to associate socket instance with.
# reference necessary to guard against premature object destruction
has ctx => (
    is       => 'ro',
    required => 1,
);

# zmq constant socket type, e.g. ZMQ_REQ
has type => (
    is       => 'ro',
    required => 1,
);

# real underlying zmq socket pointer
has _socket => (
    is      => 'ro',
    lazy    => 1,
    builder => '_build_socket',
);

requires qw(
    connect
    disconnect
    bind
    unbind
    send
    send_multipart
    recv
    recv_multipart
    get_fd
    get_linger
    set_linger
    get_identity
    set_identity
    subscribe
    unsubscribe
    has_pollin
    has_pollout
    get
    set
    close
);

sub _build_socket {
    my ($self) = @_;

    my $socket = zmq_socket($self->ctx->_ctx, $self->type);
    $self->check_null('zmq_socket', $socket);
    return $socket;
}

sub connect {
    my ($self, $endpoints) = @_;

    unless ($endpoint) {
        croak 'usage: $socket->connect($endpoint)'
    }

    $self->check_error(
        'zmq_connect',
        zmq_connect($self->_socket, $endpoint)
    );
}

sub bind {
    my ($self, $endpoint) = @_;

    unless ($endpoint) {
        croak 'usage: $socket->bind($endpoint)'
    }

    $self->check_error(
        'zmq_bind',
        zmq_bind($self->_socket, $endpoint)
    );
}

sub send_multipart {
    my ($self, $partsref, $flags) = @_;

    my @parts = @{$partsref // []};
    unless (@parts) {
        croak 'usage: send_multipart($parts, $flags)';
    }

    $flags //= 0;

    for my $i (0..$#parts-1) {
        $self->send($parts[$i], $flags | ZMQ_SNDMORE);
    }

    $self->send($parts[$#parts], $flags);
}

sub recv_multipart {
    my ($self, $flags) = @_;

    my @parts = ( $self->recv($flags) );

    my ($major) = $self->version;
    my $type    = $major == 2 ? 'int64_t' : 'int';

    while ( $self->get(ZMQ_RCVMORE, $type) ){
        push @parts, $self->recv($flags);
    }

    return @parts;
}

sub get_fd {
    my $self = shift;

    return $self->get(ZMQ_FD, 'int');
}

sub set_linger {
    my ($self, $linger) = @_;

    $self->set(ZMQ_LINGER, 'int', $linger);
}

sub get_linger {
    return shift->get(ZMQ_LINGER, 'int');
}

sub set_identity {
    my ($self, $id) = @_;

    $self->set(ZMQ_IDENTITY, 'binary', $id);
}

sub get_identity {
    return shift->get(ZMQ_IDENTITY, 'binary');
}

sub subscribe {
    my ($self, $topic) = @_;

    $self->set(ZMQ_SUBSCRIBE, 'binary', $topic);
}

sub unsubscribe {
    my ($self, $topic) = @_;

    $self->set(ZMQ_UNSUBSCRIBE, 'binary', $topic);
}

sub has_pollin {
    my $self = shift;

    my $zmq_events = $self->get(ZMQ_EVENTS, 'int');
    return $zmq_events & ZMQ_POLLIN;
}

sub has_pollout {
    my $self = shift;

    my $zmq_events = $self->get(ZMQ_EVENTS, 'int');
    return $zmq_events & ZMQ_POLLOUT;
}

sub get {
    my ($self, $opt, $opt_type) = @_;

    my $optval;
    my $optval_len;

    for ($opt_type) {
        when (/^(binary|string)$/) {
            my $optval_ptr = malloc(256);
            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_string(
                    $self->_socket,
                    $opt,
                    $optval_ptr,
                    \$optval_len
                )
            );

            $optval = buffer_to_scalar($optval_ptr, $optval_len);
        }

        when (/^int$/) {
            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_int(
                    $self->_socket,
                    $opt,
                    \$optval,
                    \$optval_len
                )
            );
        }

        when (/^int64_t$/) {
            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_int64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    \$optval_len
                )
            );
        }

        when (/^uint64_t$/) {
            $self->check_error(
                'zmq_getsockopt',
                zmq_getsockopt_uint64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    \$optval_len
                )
            );
        }

        default {
            croak "unknown type $opt_type";
        }
    }

    return $optval;
}

sub set {
    my ($self, $opt, $opt_type, $opt_val) = @_;

    for ($opt_type) {
        when (/^(binary|string)$/) {
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_string(
                    $self->_socket,
                    $opt,
                    $optval_val,
                    length($optval_len)
                )
            );
        }

        when (/^int$/) {
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_int(
                    $self->_socket,
                    $opt,
                    \$optval,
                    sizeof('int')
                )
            );
        }

        when (/^int64_t$/) {
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_int64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    sizeof('sint64')
                )
            );
        }

        when (/^uint64_t$/) {
            $self->check_error(
                'zmq_setsockopt',
                zmq_setsockopt_uint64(
                    $self->_socket,
                    $opt,
                    \$optval,
                    sizeof('uint64')
                )
            );
        }

        default {
            croak "unknown type $opt_type";
        }
    }

    return;
}

sub _load_common_ffi {
    my ($soname) = @_;

    my $ffi = FFI::Platypus->new( lib => $soname );

    $ffi->attach(
        'zmq_socket' => ['pointer', 'int'] => 'pointer'
    );

    $ffi->attach(
        'zmq_getsockopt_string'
            => ['pointer', 'int', 'string', 'size_t*'] => 'int'
    );

    $ffi->attach(
        'zmq_getsockopt_int'
            => ['pointer', 'int', 'int*', 'size_t*'] => 'int'
    );

    $ffi->attach(
        'zmq_getsockopt_int64'
            => ['pointer', 'int', 'sint64*', 'size_t*'] => 'int'
    );

    $ffi->attach(
        'zmq_getsockopt_uint64'
            => ['pointer', 'int', 'uint64*', 'size_t*'] => 'int'
    );

    $ffi->attach(
        'zmq_setsockopt_string'
            => ['pointer', 'int', 'string', 'size_t'] => 'int'
    );

    $ffi->attach(
        'zmq_setsockopt_int'
            => ['pointer', 'int', 'int*', 'size_t'] => 'int'
    );

    $ffi->attach(
        'zmq_setsockopt_int64'
            => ['pointer', 'int', 'sint64*', 'size_t'] => 'int'
    );

    $ffi->attach(
        'zmq_setsockopt_uint64'
            => ['pointer', 'int', 'uint64*', 'size_t'] => 'int'
    );

    $ffi->attach(
        'zmq_connect' => ['pointer', 'string'] => 'int'
    );

    $ffi->attach(
        'zmq_bind' => ['pointer', 'string'] => 'int'
    );

    $ffi->attach(
        'zmq_msg_init' => ['pointer'] => 'int'
    );

    $ffi->attach(
        'zmq_msg_init_size' => ['pointer', 'int'] => 'int'
    );

    $ffi->attach(
        'zmq_msg_size' => ['pointer'] => 'int'
    );

    $ffi->attach(
        'zmq_msg_data' => ['pointer'] => 'pointer'
    );

    $ffi->attach(
        'zmq_msg_close' => ['pointer'] => 'int'
    );

    $ffi->attach(
        'zmq_close' => ['pointer'] => 'int'
    );
}

1;
