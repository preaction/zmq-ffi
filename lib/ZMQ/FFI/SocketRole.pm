package ZMQ::FFI::SocketRole;

use FFI::Platypus;

use Moo::Role;

with qw(ZMQ::FFI::ErrorHandler);

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
    is      => 'rw',
    default => -1,
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

1;
